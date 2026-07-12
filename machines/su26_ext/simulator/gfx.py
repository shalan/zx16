"""su26-ext enhanced tile+sprite compositor (optimized for live GUI)."""

from __future__ import annotations

SCREEN_W = 320
SCREEN_H = 240
TILE = 16
MAP_COLS = 20
MAP_ROWS = 15

TILEMAP = 0xF000
TILEDATA_LO = 0xF200
TILEDATA_HI = 0xE800
ATTRMAP = 0xE100
PALETTE = 0xFA00
OAM = 0xE040
NUM_SPRITES = 8


def _tile_base(tid: int) -> int:
    tid &= 0x1F
    if tid < 16:
        return TILEDATA_LO + tid * 128
    return TILEDATA_HI + (tid - 16) * 128


def _expand_tiles(mem: bytearray) -> list[list[int]]:
    """Pre-expand all 32 tiles to 256 color indices each (row-major)."""
    tiles: list[list[int]] = []
    for tid in range(32):
        base = _tile_base(tid)
        pix: list[int] = []
        for bi in range(128):
            b = mem[(base + bi) & 0xFFFF]
            pix.append(b & 0x0F)
            pix.append((b >> 4) & 0x0F)
        tiles.append(pix)
    return tiles


def _expand_palette(mem: bytearray) -> list[list[tuple[int, int, int]]]:
    """4 banks × 16 RGB888 tuples."""
    banks: list[list[tuple[int, int, int]]] = []
    for bank in range(4):
        entries: list[tuple[int, int, int]] = []
        for idx in range(16):
            off = PALETTE + ((bank * 16 + idx) * 2)
            w = mem[off & 0xFFFF] | (mem[(off + 1) & 0xFFFF] << 8)
            r = ((w >> 11) & 0x1F) * 255 // 31
            g = ((w >> 5) & 0x3F) * 255 // 63
            b = (w & 0x1F) * 255 // 31
            entries.append((r, g, b))
        banks.append(entries)
    return banks


def _sample_idx(tile: list[int], tx: int, ty: int, flipx: bool, flipy: bool) -> int:
    if flipx:
        tx = 15 - tx
    if flipy:
        ty = 15 - ty
    return tile[ty * 16 + tx]


def render_frame_ext(
    mem: bytearray,
    *,
    scroll_x: int = 0,
    scroll_y: int = 0,
    bg_color565: int = 0,
    sprites_en: bool = True,
    blank: bool = False,
) -> bytes:
    """Return RGB888 bytes 320*240*3 — tile-blit based (fast enough for GUI)."""
    bg_rgb = (
        ((bg_color565 >> 11) & 0x1F) * 255 // 31,
        ((bg_color565 >> 5) & 0x3F) * 255 // 63,
        (bg_color565 & 0x1F) * 255 // 31,
    )
    if blank:
        return bytes(bg_rgb) * (SCREEN_W * SCREEN_H)

    tiles = _expand_tiles(mem)
    pals = _expand_palette(mem)
    out = bytearray(SCREEN_W * SCREEN_H * 3)

    sx = scroll_x % SCREEN_W
    sy = scroll_y % SCREEN_H

    # --- background: walk in screen space, sample map ---
    # Process in 16x16 screen tiles for better locality when scroll is multiple of 16;
    # still correct for arbitrary scroll.
    for py in range(SCREEN_H):
        my = (py + sy) % SCREEN_H
        row = my >> 4
        ty = my & 15
        row_base = row * MAP_COLS
        o_row = py * SCREEN_W * 3
        for px in range(SCREEN_W):
            mx = (px + sx) % SCREEN_W
            col = mx >> 4
            tx = mx & 15
            cell = row_base + col
            tid = mem[(TILEMAP + cell) & 0xFFFF] & 0x1F
            a = mem[(ATTRMAP + cell) & 0xFFFF]
            bank = a & 3
            flipx = bool(a & 4)
            flipy = bool(a & 8)
            ci = _sample_idx(tiles[tid], tx, ty, flipx, flipy)
            # BG layer: index 0 is opaque palette[bank][0] (not global key).
            # Sprites still treat 0 as transparent (below).
            r, g, b = pals[bank][ci]
            o = o_row + px * 3
            out[o] = r
            out[o + 1] = g
            out[o + 2] = b

    # --- sprites (blit 16x16) ---
    if sprites_en:
        for i in range(NUM_SPRITES):
            base = OAM + i * 8
            attr = mem[base + 3]
            if (attr & 1) == 0:
                continue
            spx = mem[base + 0]
            spy = mem[base + 1]
            tid = mem[base + 2] & 0x1F
            flipx = bool(attr & 2)
            flipy = bool(attr & 4)
            bank = (attr >> 3) & 3
            # prio ignored for speed if simple: always draw sprite on top when opaque
            tile = tiles[tid]
            for ty in range(TILE):
                dy = spy + ty
                if dy < 0 or dy >= SCREEN_H:
                    continue
                o_row = dy * SCREEN_W * 3
                for tx in range(TILE):
                    dx = spx + tx
                    if dx < 0 or dx >= SCREEN_W:
                        continue
                    ci = _sample_idx(tile, tx, ty, flipx, flipy)
                    if ci == 0:
                        continue
                    r, g, b = pals[bank][ci]
                    o = o_row + dx * 3
                    out[o] = r
                    out[o + 1] = g
                    out[o + 2] = b

    return bytes(out)
