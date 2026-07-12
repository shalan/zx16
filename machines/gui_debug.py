"""
ZX16 interactive GUI debugger (Su26 §8) — browser front-end.

Provides:
  - live 320×240 framebuffer
  - Run / Pause / Step / Step-Over / Reset, breakpoints
  - registers, memory view/edit, disassembly, console
  - **Tile viewer** (atlas of 16 or 32 tiles, palette-bank select)
  - **Tilemap viewer** (20×15 BG, ATTR-aware, cell hover)
  - **Palette viewer** (1 or 4 banks × 16 colours)
"""

from __future__ import annotations

import json
import struct
import threading
import time
import webbrowser
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


def rgb_to_png(rgb: bytes, w: int, h: int) -> bytes:
    """Minimal RGB8 PNG encoder (stdlib only — browsers need real PNG, not PPM)."""

    def chunk(tag: bytes, data: bytes) -> bytes:
        return (
            struct.pack(">I", len(data))
            + tag
            + data
            + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
        )

    raw = bytearray()
    row = w * 3
    for y in range(h):
        raw.append(0)  # filter None
        raw.extend(rgb[y * row : (y + 1) * row])
    return (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
        + chunk(b"IDAT", zlib.compress(bytes(raw), 6))
        + chunk(b"IEND", b"")
    )

try:
    from machines.common.isa_core import MASK, REG_NAMES
except ImportError:  # pragma: no cover
    MASK = 0xFFFF
    REG_NAMES = ["t0", "ra", "sp", "s0", "s1", "t1", "a0", "a1"]

# Optional course-era helpers (not required for machines/* sims)
_course_disasm = None
render_frame = None
scale_rgb = None
try:
    from sim.disasm import disassemble as _course_disasm  # type: ignore
except ImportError:
    pass
try:
    from sim.video import render_frame, scale_rgb  # type: ignore
except ImportError:
    pass


def _disassemble(w: int, pc: int) -> str:
    try:
        from machines.common.disasm import disassemble as d

        return d(w, pc)
    except Exception:
        if _course_disasm:
            return _course_disasm(w, pc)
        return f".word 0x{w:04x}"


def _scale_rgb(rgb: bytes, w: int, h: int, scale: int) -> tuple[bytes, int, int]:
    if scale_rgb is not None:
        return scale_rgb(rgb, w, h, scale)
    if scale <= 1:
        return rgb, w, h
    sw, sh = w * scale, h * scale
    out = bytearray(sw * sh * 3)
    for y in range(h):
        for x in range(w):
            i = (y * w + x) * 3
            pixel = rgb[i : i + 3]
            for dy in range(scale):
                for dx in range(scale):
                    o = ((y * scale + dy) * sw + (x * scale + dx)) * 3
                    out[o : o + 3] = pixel
    return bytes(out), sw, sh


def _sim_rgb(sim: Any) -> bytes:
    """Prefer machine render_rgb() (su26-ext); else tilemap view / course renderer."""
    if hasattr(sim, "render_rgb") and callable(sim.render_rgb):
        return sim.render_rgb()
    if render_frame is not None:
        return render_frame(sim.mem)
    # Built-in 20×15 tilemap compositor (works for su26 / su26-ext VRAM)
    try:
        rgb, _w, _h = render_tilemap_view(sim, scale=1)
        return rgb
    except Exception:
        return bytes(320 * 240 * 3)


def _sim_read_byte(sim: Any, addr: int) -> int:
    if hasattr(sim, "read_byte"):
        return sim.read_byte(addr & MASK) & 0xFF
    if hasattr(sim, "_read_byte"):
        return sim._read_byte(addr & MASK) & 0xFF
    return sim.mem[addr & MASK]


def _sim_write_byte(sim: Any, addr: int, val: int) -> None:
    if hasattr(sim, "write_byte"):
        sim.write_byte(addr & MASK, val & 0xFF)
    elif hasattr(sim, "_write_byte"):
        sim._write_byte(addr & MASK, val & 0xFF)
    else:
        sim.mem[addr & MASK] = val & 0xFF
    if hasattr(sim, "video_dirty"):
        sim.video_dirty = True


def _sim_lw(sim: Any, addr: int) -> int:
    if hasattr(sim, "lw"):
        return sim.lw(addr) & MASK
    return _sim_read_byte(sim, addr) | (_sim_read_byte(sim, addr + 1) << 8)


def _sim_sw(sim: Any, addr: int, val: int) -> None:
    if hasattr(sim, "sw"):
        sim.sw(addr, val & MASK)
    else:
        _sim_write_byte(sim, addr, val & 0xFF)
        _sim_write_byte(sim, addr + 1, (val >> 8) & 0xFF)


# --- GFX debug views (tiles / tilemap / palette) ---

TILEMAP_ADDR = 0xF000
TILEDATA_LO = 0xF200
TILEDATA_HI = 0xE800
ATTRMAP_ADDR = 0xE100
PALETTE_ADDR = 0xFA00
MAP_COLS = 20
MAP_ROWS = 15
TILE_PX = 16


def _is_ext_gfx(sim: Any) -> bool:
    name = str(getattr(sim, "name", "")).lower()
    return "ext" in name or hasattr(sim, "gfx_ctrl")


def _ntiles(sim: Any) -> int:
    return 32 if _is_ext_gfx(sim) else 16


def _tile_base(tid: int, ext: bool) -> int:
    tid &= 0x1F if ext else 0x0F
    if not ext or tid < 16:
        return TILEDATA_LO + tid * 128
    return TILEDATA_HI + (tid - 16) * 128


def _expand_tile_indices(mem: bytearray | bytes, tid: int, ext: bool) -> list[int]:
    base = _tile_base(tid, ext)
    pix: list[int] = []
    for bi in range(128):
        b = mem[(base + bi) & 0xFFFF]
        pix.append(b & 0x0F)
        pix.append((b >> 4) & 0x0F)
    return pix


def _palette_banks(sim: Any) -> list[list[tuple[int, int, int]]]:
    """Return list of banks; each bank is 16 RGB triples."""
    mem = sim.mem
    if _is_ext_gfx(sim):
        banks: list[list[tuple[int, int, int]]] = []
        for bank in range(4):
            entries: list[tuple[int, int, int]] = []
            for idx in range(16):
                off = PALETTE_ADDR + (bank * 16 + idx) * 2
                w = mem[off & 0xFFFF] | (mem[(off + 1) & 0xFFFF] << 8)
                r = ((w >> 11) & 0x1F) * 255 // 31
                g = ((w >> 5) & 0x3F) * 255 // 63
                b = (w & 0x1F) * 255 // 31
                entries.append((r, g, b))
            banks.append(entries)
        return banks
    # su26 RGB332
    try:
        from sim.video import rgb332_to_rgb  # type: ignore
    except ImportError:
        def rgb332_to_rgb(c: int) -> tuple[int, int, int]:
            c &= 0xFF
            r = (c >> 5) & 7
            g = (c >> 2) & 7
            b = c & 3
            return (
                ((r << 5) | (r << 2) | (r >> 1)) & 0xFF,
                ((g << 5) | (g << 2) | (g >> 1)) & 0xFF,
                ((b << 6) | (b << 4) | (b << 2) | b) & 0xFF,
            )

    return [[rgb332_to_rgb(mem[PALETTE_ADDR + i]) for i in range(16)]]


def render_tiles_atlas(
    sim: Any, *, scale: int = 3, bank: int = 0, gap: int = 1
) -> tuple[bytes, int, int]:
    """Atlas of all tiles (nt × 16×16), labeled-free RGB for PNG."""
    n = _ntiles(sim)
    cols = 8
    rows = (n + cols - 1) // cols
    cell = TILE_PX * scale
    stride = cell + gap
    w = cols * stride - gap
    h = rows * stride - gap
    out = bytearray(w * h * 3)
    # dark checker bg
    for y in range(h):
        for x in range(w):
            c = 0x18 if ((x // 4) ^ (y // 4)) & 1 else 0x22
            o = (y * w + x) * 3
            out[o] = out[o + 1] = out[o + 2] = c

    banks = _palette_banks(sim)
    bank = max(0, min(bank, len(banks) - 1))
    pal = banks[bank]
    ext = _is_ext_gfx(sim)
    mem = sim.mem

    for tid in range(n):
        r0, c0 = divmod(tid, cols)
        x0, y0 = c0 * stride, r0 * stride
        pix = _expand_tile_indices(mem, tid, ext)
        for ty in range(TILE_PX):
            for tx in range(TILE_PX):
                ci = pix[ty * TILE_PX + tx] & 0x0F
                r, g, b = pal[ci]
                for dy in range(scale):
                    for dx in range(scale):
                        xx, yy = x0 + tx * scale + dx, y0 + ty * scale + dy
                        o = (yy * w + xx) * 3
                        out[o] = r
                        out[o + 1] = g
                        out[o + 2] = b
    return bytes(out), w, h


def render_tilemap_view(sim: Any, *, scale: int = 1) -> tuple[bytes, int, int]:
    """Full 20×15 map (no scroll/sprites), using ATTR banks when present."""
    ext = _is_ext_gfx(sim)
    n = _ntiles(sim)
    banks = _palette_banks(sim)
    mem = sim.mem
    tiles = [_expand_tile_indices(mem, t, ext) for t in range(n)]
    w, h = MAP_COLS * TILE_PX, MAP_ROWS * TILE_PX
    out = bytearray(w * h * 3)
    for row in range(MAP_ROWS):
        for col in range(MAP_COLS):
            cell = row * MAP_COLS + col
            tid = mem[(TILEMAP_ADDR + cell) & 0xFFFF] & (0x1F if ext else 0x0F)
            if tid >= n:
                tid = 0
            if ext:
                attr = mem[(ATTRMAP_ADDR + cell) & 0xFFFF]
                bank = attr & 3
                flipx = bool(attr & 4)
                flipy = bool(attr & 8)
            else:
                bank, flipx, flipy = 0, False, False
            bank = max(0, min(bank, len(banks) - 1))
            pal = banks[bank]
            tile = tiles[tid]
            x0, y0 = col * TILE_PX, row * TILE_PX
            for ty in range(TILE_PX):
                for tx in range(TILE_PX):
                    sx = 15 - tx if flipx else tx
                    sy = 15 - ty if flipy else ty
                    ci = tile[sy * TILE_PX + sx] & 0x0F
                    r, g, b = pal[ci]
                    o = ((y0 + ty) * w + (x0 + tx)) * 3
                    out[o] = r
                    out[o + 1] = g
                    out[o + 2] = b
    if scale > 1:
        return _scale_rgb(bytes(out), w, h, scale)
    return bytes(out), w, h


def render_palette_view(sim: Any, *, cell: int = 18, gap: int = 2) -> tuple[bytes, int, int]:
    banks = _palette_banks(sim)
    nb = len(banks)
    cols, rows = 16, nb
    w = cols * (cell + gap) - gap
    h = rows * (cell + gap) - gap
    out = bytearray(w * h * 3)
    for y in range(h):
        for x in range(w):
            o = (y * w + x) * 3
            out[o] = out[o + 1] = out[o + 2] = 0x14
    for bi, pal in enumerate(banks):
        for ci, (r, g, b) in enumerate(pal):
            x0 = ci * (cell + gap)
            y0 = bi * (cell + gap)
            for dy in range(cell):
                for dx in range(cell):
                    o = ((y0 + dy) * w + (x0 + dx)) * 3
                    out[o] = r
                    out[o + 1] = g
                    out[o + 2] = b
    return bytes(out), w, h


def tilemap_meta(sim: Any) -> dict[str, Any]:
    """JSON-friendly map of tile ids + attr for the tilemap hover UI."""
    ext = _is_ext_gfx(sim)
    mem = sim.mem
    cells = []
    for row in range(MAP_ROWS):
        for col in range(MAP_COLS):
            i = row * MAP_COLS + col
            tid = mem[(TILEMAP_ADDR + i) & 0xFFFF] & (0x1F if ext else 0x0F)
            attr = mem[(ATTRMAP_ADDR + i) & 0xFFFF] if ext else 0
            cells.append(
                {
                    "r": row,
                    "c": col,
                    "tid": tid,
                    "bank": attr & 3,
                    "flipx": bool(attr & 4),
                    "flipy": bool(attr & 8),
                    "prio": bool(attr & 16),
                }
            )
    return {
        "cols": MAP_COLS,
        "rows": MAP_ROWS,
        "ntiles": _ntiles(sim),
        "ext": ext,
        "cells": cells,
    }


class DebuggerSession:
    def __init__(self, sim: Any, binary_path: str, scale: int = 2, title: str = "ZX16"):
        self.sim = sim
        self.binary_path = binary_path
        self.scale = scale
        self.title = title
        self.lock = threading.RLock()
        self.running = False
        self.breakpoints: set[int] = set()
        self.run_until_pc: int | None = None  # step-over / run-to-cursor
        self.temp_breaks: set[int] = set()
        self.status = "paused"
        self.last_error = ""
        self.frame_bytes = b""
        self.frame_id = 0
        self.frame_wh = (320 * scale, 240 * scale)
        self._worker: threading.Thread | None = None
        self._stop_worker = False
        self.mem_view_addr = 0x0020
        self.ips_budget = 200_000  # instr per run-slice (keep GUI responsive)
        self._png_cache: bytes | None = None
        self._png_frame_id = -1
        # GFX debug views
        self.tile_bank = 0
        self._tiles_png: bytes | None = None
        self._tiles_frame_id = -1
        self._tilemap_png: bytes | None = None
        self._tilemap_frame_id = -1
        self._palette_png: bytes | None = None
        self._palette_frame_id = -1
        # ensure keyboard fields exist
        if not hasattr(sim, "key_code"):
            sim.key_code = 0
        if not hasattr(sim, "key_pressed"):
            sim.key_pressed = 0
        if not hasattr(sim, "console"):
            sim.console = []
        if not hasattr(sim, "video_dirty"):
            sim.video_dirty = True
        self._refresh_video(force=True)

    def _refresh_video(self, force: bool = False) -> None:
        dirty = getattr(self.sim, "video_dirty", True)
        if not force and not dirty:
            return
        try:
            rgb = _sim_rgb(self.sim)
        except Exception as e:
            self.last_error = f"render: {e}"
            return
        # GUI uses scale=1 for speed unless caller asked for more
        sc = self.scale
        scaled, w, h = _scale_rgb(rgb, 320, 240, sc)
        self.frame_bytes = scaled
        self.frame_wh = (w, h)
        self.frame_id += 1
        self._png_cache = None  # invalidate PNG
        self.sim.video_dirty = False

    def get_png(self) -> bytes:
        """Cached PNG of current frame_bytes."""
        if self._png_cache is not None and self._png_frame_id == self.frame_id:
            return self._png_cache
        w, h = self.frame_wh
        self._png_cache = rgb_to_png(self.frame_bytes, w, h)
        self._png_frame_id = self.frame_id
        return self._png_cache

    def get_tiles_png(self) -> bytes:
        if self._tiles_png is not None and self._tiles_frame_id == self.frame_id:
            return self._tiles_png
        rgb, w, h = render_tiles_atlas(self.sim, scale=3, bank=self.tile_bank)
        self._tiles_png = rgb_to_png(rgb, w, h)
        self._tiles_frame_id = self.frame_id
        return self._tiles_png

    def get_tilemap_png(self) -> bytes:
        if self._tilemap_png is not None and self._tilemap_frame_id == self.frame_id:
            return self._tilemap_png
        rgb, w, h = render_tilemap_view(self.sim, scale=1)
        self._tilemap_png = rgb_to_png(rgb, w, h)
        self._tilemap_frame_id = self.frame_id
        return self._tilemap_png

    def get_palette_png(self) -> bytes:
        if self._palette_png is not None and self._palette_frame_id == self.frame_id:
            return self._palette_png
        rgb, w, h = render_palette_view(self.sim)
        self._palette_png = rgb_to_png(rgb, w, h)
        self._palette_frame_id = self.frame_id
        return self._palette_png

    def snapshot(self) -> dict[str, Any]:
        with self.lock:
            self._refresh_video()
            pc = self.sim.pc
            regs = {
                REG_NAMES[i]: self.sim.reg[i] & MASK for i in range(8)
            }
            regs["pc"] = pc & MASK
            regs["sp"] = self.sim.reg[2] & MASK
            # disassembly window: ±8 instructions (2-byte)
            dis: list[dict[str, Any]] = []
            for off in range(-16, 18, 2):
                addr = (pc + off) & MASK
                try:
                    w = _sim_lw(self.sim, addr)
                    text = _disassemble(w, addr)
                except Exception:
                    w, text = 0, "???"
                dis.append(
                    {
                        "addr": addr,
                        "word": w,
                        "text": text,
                        "pc": addr == pc,
                        "bp": addr in self.breakpoints,
                    }
                )
            # memory window 256 bytes
            base = self.mem_view_addr & MASK
            mem_rows = []
            for row in range(16):
                a = (base + row * 16) & MASK
                bs = [_sim_read_byte(self.sim, (a + i) & MASK) for i in range(16)]
                mem_rows.append({"addr": a, "bytes": bs})
            console = "".join(getattr(self.sim, "console", []) or [])
            machine = getattr(self.sim, "name", self.title)
            gfx = {
                "ext": _is_ext_gfx(self.sim),
                "ntiles": _ntiles(self.sim),
                "nbanks": len(_palette_banks(self.sim)),
                "tile_bank": self.tile_bank,
                "map_cols": MAP_COLS,
                "map_rows": MAP_ROWS,
            }
            # light map meta for hover (ids only — compact)
            try:
                gfx["tilemap"] = tilemap_meta(self.sim)
            except Exception as e:
                gfx["tilemap_error"] = str(e)
            # scroll / ctrl if present
            if hasattr(self.sim, "gfx_scroll_x"):
                gfx["scroll_x"] = int(self.sim.gfx_scroll_x) & MASK
                gfx["scroll_y"] = int(self.sim.gfx_scroll_y) & MASK
                gfx["ctrl"] = int(getattr(self.sim, "gfx_ctrl", 0)) & MASK
                gfx["frame"] = int(getattr(self.sim, "gfx_frame", 0)) & MASK
            return {
                "status": "halted"
                if self.sim.halted
                else ("running" if self.running else "paused"),
                "cycles": self.sim.cycles,
                "regs": regs,
                "disasm": dis,
                "mem": mem_rows,
                "mem_base": base,
                "breakpoints": sorted(self.breakpoints),
                "console": console[-8000:],
                "frame_id": self.frame_id,
                "error": self.last_error,
                "binary": self.binary_path,
                "machine": machine,
                "gfx": gfx,
            }

    def _is_call(self, pc: int) -> bool:
        w = _sim_lw(self.sim, pc)
        op = w & 7
        if op == 5 and ((w >> 15) & 1):  # JAL
            return True
        if op == 0 and ((w >> 12) & 0xF) == 0xC:  # JALR
            return True
        return False

    def step_one(self) -> None:
        with self.lock:
            if self.sim.halted:
                self.status = "halted"
                return
            try:
                self.sim.step()
                self._refresh_video()
            except Exception as e:
                self.last_error = str(e)
                self.running = False
                self.status = "error"
                return
            if self.sim.halted:
                self.running = False
                self.status = "halted"

    def step_over(self) -> None:
        with self.lock:
            if self.sim.halted:
                return
            if self._is_call(self.sim.pc):
                ret = (self.sim.pc + 2) & MASK
                self.run_until_pc = ret
                self.temp_breaks.add(ret)
                self.running = True
                self.status = "running"
                self._ensure_worker()
            else:
                self.step_one()

    def run(self) -> None:
        with self.lock:
            if self.sim.halted:
                return
            self.running = True
            self.status = "running"
            self.run_until_pc = None
            self._ensure_worker()

    def pause(self) -> None:
        with self.lock:
            self.running = False
            if not self.sim.halted:
                self.status = "paused"

    def reset(self) -> None:
        with self.lock:
            self.running = False
            self.run_until_pc = None
            self.temp_breaks.clear()
            self.last_error = ""
            try:
                self.sim.load_bin_file(self.binary_path)
            except Exception as e:
                self.last_error = f"reload failed: {e}"
            self.status = "paused"
            self._refresh_video(force=True)

    def toggle_break(self, addr: int) -> None:
        with self.lock:
            addr &= MASK
            if addr in self.breakpoints:
                self.breakpoints.discard(addr)
            else:
                self.breakpoints.add(addr)

    def run_to(self, addr: int) -> None:
        with self.lock:
            addr &= MASK
            self.temp_breaks.add(addr)
            self.run_until_pc = addr
            self.running = True
            self.status = "running"
            self._ensure_worker()

    def set_reg(self, name: str, value: int) -> None:
        with self.lock:
            value &= MASK
            name = name.lower()
            if name == "pc":
                self.sim.pc = value
            elif name in REG_NAMES:
                self.sim.reg[REG_NAMES.index(name)] = value
            elif name.startswith("x") and name[1:].isdigit():
                self.sim.reg[int(name[1:])] = value

    def set_mem(self, addr: int, value: int, size: int = 1) -> None:
        with self.lock:
            addr &= MASK
            if size == 2:
                _sim_sw(self.sim, addr, value & MASK)
            else:
                _sim_write_byte(self.sim, addr, value & 0xFF)
            self._refresh_video(force=True)

    def _ensure_worker(self) -> None:
        if self._worker and self._worker.is_alive():
            return
        self._stop_worker = False
        self._worker = threading.Thread(target=self._run_loop, daemon=True)
        self._worker.start()

    def _run_loop(self) -> None:
        while not self._stop_worker:
            with self.lock:
                if not self.running or self.sim.halted:
                    if self.sim.halted:
                        self.status = "halted"
                        self.running = False
                    break
                budget = self.ips_budget
            for _ in range(budget):
                with self.lock:
                    if not self.running or self.sim.halted:
                        break
                    pc = self.sim.pc
                    # hit breakpoint *before* executing
                    if pc in self.breakpoints or pc in self.temp_breaks:
                        if pc in self.temp_breaks:
                            self.temp_breaks.discard(pc)
                        if self.run_until_pc is not None and pc == self.run_until_pc:
                            self.run_until_pc = None
                        self.running = False
                        self.status = "paused"
                        self._refresh_video()
                        return
                    try:
                        self.sim.step()
                    except Exception as e:
                        self.last_error = str(e)
                        self.running = False
                        self.status = "error"
                        return
                    if self.sim.halted:
                        self.running = False
                        self.status = "halted"
                        self._refresh_video(force=True)
                        return
            # One video refresh per run-slice (not per few hundred cycles)
            with self.lock:
                if self.running:
                    self._refresh_video(force=True)
            time.sleep(0.01)

    def stop(self) -> None:
        self._stop_worker = True
        self.running = False


HTML_PAGE = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1"/>
<title>ZX16 Debugger</title>
<style>
  :root {
    --bg: #0c0e12; --panel: #161a22; --panel2: #1c2230; --border: #2a3140;
    --text: #e8ecf4; --muted: #8b93a7; --accent: #6cb6ff;
    --pc: #243d1c; --bp: #5a2020; --ok: #3dd68c; --warn: #f5a524; --err: #f07178;
    --header-h: 52px;
  }
  * { box-sizing: border-box; }
  html, body { height: 100%; }
  body {
    margin: 0; font-family: ui-sans-serif, system-ui, -apple-system, sans-serif;
    background: var(--bg); color: var(--text); font-size: 13px;
    display: flex; flex-direction: column; overflow: hidden;
  }
  header {
    flex: 0 0 auto;
    display: flex; align-items: center; gap: 8px; flex-wrap: wrap;
    min-height: var(--header-h);
    padding: 8px 12px; background: var(--panel);
    border-bottom: 1px solid var(--border);
  }
  header h1 { font-size: 14px; margin: 0 8px 0 0; font-weight: 650; letter-spacing: .02em; }
  .btn {
    background: #2a3344; color: var(--text); border: 1px solid var(--border);
    border-radius: 6px; padding: 5px 11px; cursor: pointer; font-weight: 500;
    font-size: 12px; line-height: 1.2;
  }
  .btn:hover { background: #343e52; }
  .btn.primary { background: #2456a8; border-color: #3a6fc0; }
  .btn.danger { background: #6b2430; border-color: #8a3040; }
  .btn.active { background: #2a4a6a; border-color: var(--accent); color: #fff; }
  .status { margin-left: auto; color: var(--muted); font-size: 12px; white-space: nowrap; }
  .status b { color: var(--ok); }
  .status.running b { color: var(--warn); }
  .status.halted b { color: var(--err); }
  main {
    flex: 1 1 auto;
    min-height: 0;
    display: grid;
    /* Right column (memory) is wide enough for 16-byte hex dump rows */
    grid-template-columns: minmax(300px, 360px) minmax(220px, 1fr) minmax(400px, 480px);
    grid-template-rows: minmax(0, 1fr) minmax(0, 1fr);
    gap: 8px;
    padding: 8px;
  }
  .panel {
    background: var(--panel); border: 1px solid var(--border); border-radius: 8px;
    padding: 8px 10px; overflow: hidden; min-height: 0;
    display: flex; flex-direction: column;
  }
  .panel h2 {
    flex: 0 0 auto;
    margin: 0 0 6px; font-size: 11px; text-transform: uppercase;
    letter-spacing: .07em; color: var(--muted); font-weight: 650;
    display: flex; align-items: center; gap: 8px; justify-content: space-between;
  }
  .panel h2 .sub { font-size: 10px; text-transform: none; letter-spacing: 0; font-weight: 500; color: #6a7388; }
  .panel-body { flex: 1 1 auto; min-height: 0; overflow: auto; }

  /* Column 1: display + gfx viewers */
  #col-left {
    grid-column: 1; grid-row: 1 / -1;
    display: flex; flex-direction: column; gap: 8px; min-height: 0;
  }
  #screen-panel { flex: 0 0 auto; }
  #screen {
    image-rendering: pixelated; image-rendering: crisp-edges;
    width: 100%; max-height: 280px; object-fit: contain;
    background: #000; border: 1px solid var(--border); border-radius: 4px;
    display: block;
  }
  #gfx-panel { flex: 1 1 auto; min-height: 0; }
  .tabs {
    display: flex; gap: 4px; margin-bottom: 6px; flex-wrap: wrap;
  }
  .tab {
    background: var(--panel2); border: 1px solid var(--border); color: var(--muted);
    border-radius: 5px; padding: 4px 10px; cursor: pointer; font-size: 11px; font-weight: 600;
  }
  .tab:hover { color: var(--text); }
  .tab.on { background: #2a4060; border-color: var(--accent); color: var(--text); }
  .tab-pane { display: none; flex: 1 1 auto; min-height: 0; overflow: auto; }
  .tab-pane.on { display: block; }
  .view-img {
    image-rendering: pixelated; image-rendering: crisp-edges;
    background: #0a0c10; border: 1px solid var(--border); border-radius: 4px;
    max-width: 100%; display: block; cursor: crosshair;
  }
  #tilemap-wrap { position: relative; display: inline-block; max-width: 100%; }
  #tilemap-overlay {
    position: absolute; inset: 0; pointer-events: none;
  }
  #tilemap-hl {
    position: absolute; border: 2px solid #ffcc33; box-sizing: border-box;
    display: none; pointer-events: none;
  }
  .meta-line {
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 11px; color: var(--muted); margin-top: 6px; min-height: 1.4em;
  }
  .meta-line b { color: var(--accent); font-weight: 600; }

  /* Column 2: regs + disasm */
  #regs { grid-column: 2; grid-row: 1; }
  #disasm { grid-column: 2; grid-row: 2; }
  /* Column 3: mem + console */
  #mem { grid-column: 3; grid-row: 1; }
  #console { grid-column: 3; grid-row: 2; }
  #mem-table {
    width: max-content; min-width: 100%;
    font-size: 12px; white-space: nowrap;
  }
  #mem-table td:first-child {
    color: var(--muted); padding-right: 10px; user-select: none;
  }
  #mem-table td:last-child { letter-spacing: 0.02em; }

  table { width: 100%; border-collapse: collapse; font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; }
  td, th { padding: 2px 5px; text-align: left; }
  th { color: var(--muted); font-weight: 600; font-size: 10px; text-transform: uppercase; letter-spacing: .04em; }
  tr.pc { background: var(--pc); }
  tr.bp { background: var(--bp); }
  tr.pc.bp { background: #4a4030; }
  .mono { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }
  input[type=text], select {
    background: #0c0e13; color: var(--text); border: 1px solid var(--border);
    border-radius: 4px; padding: 4px 6px; font-family: ui-monospace, monospace;
    font-size: 12px; width: 5.5em;
  }
  select { width: auto; min-width: 4em; }
  .row-tools { display:flex; gap:6px; flex-wrap:wrap; margin-bottom:6px; align-items:center; flex: 0 0 auto; }
  #console-out {
    white-space: pre-wrap; font-family: ui-monospace, monospace; font-size: 12px;
    background: #0c0e13; border-radius: 4px; padding: 8px; min-height: 60px;
    height: 100%; overflow: auto;
  }
  .hint { color: var(--muted); font-size: 11px; margin: 4px 0 0; line-height: 1.35; }
  button.bp-dot {
    width: 12px; height: 12px; border-radius: 50%; border: 1px solid #666;
    background: transparent; padding: 0; cursor: pointer; vertical-align: middle;
  }
  button.bp-dot.on { background: #e05555; border-color: #e05555; }
  kbd {
    background:#2a3344; padding:1px 5px; border-radius:3px; border:1px solid var(--border);
    font-size: 10px;
  }
  .reg-grid {
    display: grid; grid-template-columns: repeat(3, 1fr); gap: 4px 8px;
    font-family: ui-monospace, monospace; font-size: 12px;
  }
  .reg-cell {
    background: var(--panel2); border-radius: 4px; padding: 4px 6px;
    border: 1px solid transparent;
  }
  .reg-cell .n { color: var(--muted); font-size: 10px; text-transform: uppercase; }
  .reg-cell .v { color: var(--text); }

  @media (max-width: 1100px) {
    main {
      grid-template-columns: 1fr 1fr;
      grid-template-rows: auto auto auto auto;
      overflow: auto;
    }
    #col-left { grid-column: 1 / -1; grid-row: 1; max-height: 50vh; }
    #regs { grid-column: 1; grid-row: 2; }
    #disasm { grid-column: 2; grid-row: 2; }
    #mem { grid-column: 1; grid-row: 3; }
    #console { grid-column: 2; grid-row: 3; }
    body { overflow: auto; }
  }
</style>
</head>
<body>
<header>
  <h1 id="title">ZX16 Debugger</h1>
  <button class="btn primary" onclick="cmd('run')">Run</button>
  <button class="btn" onclick="cmd('pause')">Pause</button>
  <button class="btn" onclick="cmd('step')">Step</button>
  <button class="btn" onclick="cmd('step_over')">Step Over</button>
  <button class="btn danger" onclick="cmd('reset')">Reset</button>
  <span class="mono" style="margin-left:4px;color:var(--muted)">Run to</span>
  <input id="runto" type="text" placeholder="0x0030" />
  <button class="btn" onclick="runTo()">Go</button>
  <span id="status" class="status">status: <b>—</b> · cycles <span id="cycles">0</span></span>
</header>
<main>
  <div id="col-left">
    <section class="panel" id="screen-panel">
      <h2>Display <span class="sub" id="binpath">320×240</span></h2>
      <img id="screen" src="/frame.png" alt="framebuffer" tabindex="0"/>
      <p class="hint">Keys → ecall 0x030: <kbd>W</kbd><kbd>A</kbd><kbd>S</kbd><kbd>D</kbd> / arrows · click screen to focus</p>
      <p class="meta-line" id="gfx-status"></p>
    </section>

    <section class="panel" id="gfx-panel">
      <h2>Graphics <span class="sub" id="gfx-cap">tiles · tilemap · palette</span></h2>
      <div class="tabs">
        <button class="tab on" data-tab="tiles" onclick="showTab('tiles')">Tiles</button>
        <button class="tab" data-tab="tilemap" onclick="showTab('tilemap')">Tilemap</button>
        <button class="tab" data-tab="palette" onclick="showTab('palette')">Palette</button>
      </div>

      <div id="pane-tiles" class="tab-pane on">
        <div class="row-tools">
          <span class="mono">bank</span>
          <select id="tile-bank" onchange="setTileBank()">
            <option value="0">0</option>
            <option value="1">1</option>
            <option value="2">2</option>
            <option value="3">3</option>
          </select>
          <span class="hint" style="margin:0">Preview palette bank (su26-ext)</span>
        </div>
        <img id="tiles-img" class="view-img" src="/tiles.png" alt="tile atlas"
             onclick="onTileClick(event)" title="Click a tile for id"/>
        <p class="meta-line" id="tile-info">Click a tile · 8 per row · scale×3</p>
      </div>

      <div id="pane-tilemap" class="tab-pane">
        <div id="tilemap-wrap">
          <img id="tilemap-img" class="view-img" src="/tilemap.png" alt="tilemap"
               width="320" height="240"
               onmousemove="onMapHover(event)" onmouseleave="onMapLeave()"
               onclick="onMapClick(event)"/>
          <div id="tilemap-overlay"><div id="tilemap-hl"></div></div>
        </div>
        <p class="meta-line" id="map-info">Hover a cell · 20×15 map (no scroll/sprites)</p>
      </div>

      <div id="pane-palette" class="tab-pane">
        <img id="palette-img" class="view-img" src="/palette.png" alt="palette"/>
        <p class="meta-line">Rows = banks · columns = indices 0–15 (RGB565 on su26-ext)</p>
      </div>
    </section>
  </div>

  <section class="panel" id="regs">
    <h2>Registers</h2>
    <div class="row-tools">
      <span class="mono">set</span>
      <input id="reg-name" type="text" placeholder="a0" style="width:3.5em"/>
      <input id="reg-val" type="text" placeholder="0x000f"/>
      <button class="btn" onclick="setReg()">Write</button>
    </div>
    <div class="panel-body">
      <div id="reg-grid" class="reg-grid"></div>
    </div>
  </section>

  <section class="panel" id="disasm">
    <h2>Disassembly <span class="sub">● breakpoint · double-click run-to</span></h2>
    <div class="panel-body">
      <table id="dis-table" class="mono"></table>
    </div>
  </section>

  <section class="panel" id="mem">
    <h2>Memory</h2>
    <div class="row-tools">
      <span class="mono">addr</span>
      <input id="mem-addr" type="text" placeholder="0x0020"/>
      <button class="btn" onclick="gotoMem()">Jump</button>
      <button class="btn" onclick="gotoMemPreset(0xF000)">map</button>
      <button class="btn" onclick="gotoMemPreset(0xF200)">tiles</button>
      <button class="btn" onclick="gotoMemPreset(0xFA00)">pal</button>
      <button class="btn" onclick="gotoMemPreset(0xE100)">attr</button>
    </div>
    <div class="row-tools">
      <span class="mono">poke</span>
      <input id="poke-addr" type="text" placeholder="addr" style="width:4.5em"/>
      <input id="poke-val" type="text" placeholder="byte" style="width:3.5em"/>
      <button class="btn" onclick="pokeMem()">Write</button>
    </div>
    <div class="panel-body">
      <table id="mem-table" class="mono"></table>
    </div>
  </section>

  <section class="panel" id="console">
    <h2>Console</h2>
    <div class="panel-body">
      <div id="console-out"></div>
    </div>
  </section>
</main>
<script>
let lastFrame = -1;
let lastGfx = null;
let tileMapCells = null;

function hex4(n){ return (n>>>0).toString(16).padStart(4,'0'); }
function hex2(n){ return (n>>>0).toString(16).padStart(2,'0'); }
function parseNum(s){
  s = (s||'').trim();
  if(!s) return null;
  return parseInt(s, 0);
}
async function api(path, opts){
  const r = await fetch(path, opts);
  return r.json();
}
async function cmd(c){
  await api('/api/control', {method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({cmd:c})});
  await refresh();
}
async function runTo(){
  const a = parseNum(document.getElementById('runto').value);
  if(a===null) return;
  await api('/api/control', {method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({cmd:'run_to', addr:a})});
  await refresh();
}
async function setReg(){
  const name = document.getElementById('reg-name').value;
  const value = parseNum(document.getElementById('reg-val').value);
  if(!name || value===null) return;
  await api('/api/regs', {method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({name, value})});
  await refresh();
}
async function gotoMem(){
  const a = parseNum(document.getElementById('mem-addr').value);
  if(a===null) return;
  await api('/api/memview', {method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({addr:a})});
  await refresh();
}
async function gotoMemPreset(a){
  document.getElementById('mem-addr').value = '0x'+hex4(a);
  await api('/api/memview', {method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({addr:a})});
  await refresh();
}
async function pokeMem(){
  const addr = parseNum(document.getElementById('poke-addr').value);
  const value = parseNum(document.getElementById('poke-val').value);
  if(addr===null || value===null) return;
  await api('/api/mem', {method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({addr, value, size:1})});
  await refresh();
}
async function toggleBp(addr){
  await api('/api/break', {method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({addr})});
  await refresh();
}
async function setTileBank(){
  const b = parseInt(document.getElementById('tile-bank').value, 10) || 0;
  await api('/api/tilebank', {method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({bank:b})});
  // force tile image refresh
  lastFrame = -1;
  await refresh();
}
function showTab(name){
  document.querySelectorAll('.tab').forEach(t => t.classList.toggle('on', t.dataset.tab===name));
  document.querySelectorAll('.tab-pane').forEach(p => p.classList.toggle('on', p.id==='pane-'+name));
}
function onTileClick(ev){
  const img = ev.target;
  const ntiles = (lastGfx && lastGfx.ntiles) || 16;
  const cols = 8;
  const scale = 3, gap = 1, cell = 16*scale;
  const stride = cell + gap;
  const rect = img.getBoundingClientRect();
  const x = (ev.clientX - rect.left) * (img.naturalWidth / rect.width);
  const y = (ev.clientY - rect.top) * (img.naturalHeight / rect.height);
  const c = Math.floor(x / stride);
  const r = Math.floor(y / stride);
  if(c < 0 || r < 0 || c >= cols) return;
  const tid = r * cols + c;
  if(tid >= ntiles) return;
  const lo = tid < 16;
  const base = lo ? (0xF200 + tid*128) : (0xE800 + (tid-16)*128);
  document.getElementById('tile-info').innerHTML =
    `tile <b>${tid}</b> · data <b>0x${hex4(base)}</b> · bank preview ${document.getElementById('tile-bank').value}`;
  document.getElementById('mem-addr').value = '0x'+hex4(base);
}
function mapCellFromEvent(ev){
  const img = document.getElementById('tilemap-img');
  const rect = img.getBoundingClientRect();
  const x = (ev.clientX - rect.left) * (320 / rect.width);
  const y = (ev.clientY - rect.top) * (240 / rect.height);
  const c = Math.floor(x / 16);
  const r = Math.floor(y / 16);
  if(c < 0 || r < 0 || c >= 20 || r >= 15) return null;
  return {c, r, x, y, rect};
}
function onMapHover(ev){
  const cell = mapCellFromEvent(ev);
  const hl = document.getElementById('tilemap-hl');
  if(!cell){ hl.style.display='none'; return; }
  const img = document.getElementById('tilemap-img');
  const rect = img.getBoundingClientRect();
  const scaleX = rect.width / 320, scaleY = rect.height / 240;
  hl.style.display = 'block';
  hl.style.left = (cell.c * 16 * scaleX) + 'px';
  hl.style.top = (cell.r * 16 * scaleY) + 'px';
  hl.style.width = (16 * scaleX) + 'px';
  hl.style.height = (16 * scaleY) + 'px';
  let info = `cell <b>(${cell.c},${cell.r})</b>`;
  if(tileMapCells){
    const i = cell.r * 20 + cell.c;
    const m = tileMapCells[i];
    if(m){
      info += ` · tile <b>${m.tid}</b> · bank <b>${m.bank}</b>`;
      if(m.flipx) info += ' · flipX';
      if(m.flipy) info += ' · flipY';
      if(m.prio) info += ' · prio';
      info += ` · map 0x${hex4(0xF000 + i)}`;
    }
  }
  document.getElementById('map-info').innerHTML = info;
}
function onMapLeave(){
  document.getElementById('tilemap-hl').style.display = 'none';
}
function onMapClick(ev){
  const cell = mapCellFromEvent(ev);
  if(!cell) return;
  const addr = 0xF000 + cell.r * 20 + cell.c;
  document.getElementById('mem-addr').value = '0x'+hex4(addr);
  gotoMemPreset(addr);
}
function render(s){
  const st = document.getElementById('status');
  st.className = 'status ' + s.status;
  st.innerHTML = 'status: <b>'+s.status+'</b> · cycles <span id="cycles">'+s.cycles+'</span>';
  const bp = (s.machine ? '['+s.machine+'] ' : '') + (s.binary || '');
  document.getElementById('binpath').textContent = bp || '320×240';
  if(s.machine) document.getElementById('title').textContent = 'ZX16 · '+s.machine;

  // regs as compact grid
  const order = ['pc','sp','t0','ra','s0','s1','t1','a0','a1'];
  let rg = '';
  for(const n of order){
    const v = s.regs[n];
    if(v===undefined) continue;
    rg += `<div class="reg-cell"><div class="n">${n}</div><div class="v">${hex4(v)}</div></div>`;
  }
  document.getElementById('reg-grid').innerHTML = rg;

  // disasm
  let dt = '<tr><th></th><th>addr</th><th>word</th><th>instruction</th></tr>';
  for(const row of s.disasm){
    const cls = (row.pc?'pc ':'')+(row.bp?'bp':'');
    dt += `<tr class="${cls}" ondblclick="document.getElementById('runto').value='0x${hex4(row.addr)}'; runTo()">
      <td><button class="bp-dot ${row.bp?'on':''}" onclick="event.stopPropagation();toggleBp(${row.addr})"></button></td>
      <td>${hex4(row.addr)}</td><td>${hex4(row.word)}</td><td>${row.text}</td></tr>`;
  }
  document.getElementById('dis-table').innerHTML = dt;

  // mem
  let mt = '';
  for(const row of s.mem){
    const hex = row.bytes.map(hex2).join(' ');
    mt += `<tr><td>${hex4(row.addr)}</td><td>${hex}</td></tr>`;
  }
  document.getElementById('mem-table').innerHTML = mt;
  document.getElementById('console-out').textContent = s.console || '';

  // gfx
  const g = s.gfx || {};
  lastGfx = g;
  if(g.tilemap && g.tilemap.cells) tileMapCells = g.tilemap.cells;
  let gs = `${g.ntiles||16} tiles`;
  if(g.ext) gs += ` · ${g.nbanks||4} pal banks · ATTR`;
  if(g.scroll_x!==undefined) gs += ` · scroll (${g.scroll_x},${g.scroll_y}) · frame ${g.frame}`;
  document.getElementById('gfx-status').textContent = gs;
  document.getElementById('gfx-cap').textContent =
    (g.ext ? 'su26-ext · 32 tiles · 4 banks' : 'su26 · 16 tiles');
  const bankSel = document.getElementById('tile-bank');
  if(document.activeElement !== bankSel && g.tile_bank!==undefined){
    bankSel.value = String(g.tile_bank);
  }
  // disable banks 1-3 on non-ext
  for(let i=0;i<bankSel.options.length;i++){
    bankSel.options[i].disabled = (!g.ext && i>0);
  }

  if(s.frame_id !== lastFrame){
    lastFrame = s.frame_id;
    document.getElementById('screen').src = '/frame.png?' + s.frame_id;
    document.getElementById('tiles-img').src = '/tiles.png?' + s.frame_id;
    document.getElementById('tilemap-img').src = '/tilemap.png?' + s.frame_id;
    document.getElementById('palette-img').src = '/palette.png?' + s.frame_id;
  }
  if(s.error) console.warn(s.error);
}
async function refresh(){
  try {
    const s = await api('/api/state');
    render(s);
  } catch(e) { /* server restarting */ }
}
function mapKey(e){
  if(e.key === 'ArrowUp') return 17;
  if(e.key === 'ArrowDown') return 18;
  if(e.key === 'ArrowLeft') return 19;
  if(e.key === 'ArrowRight') return 20;
  if(e.key.length === 1) return e.key.charCodeAt(0);
  return 0;
}
window.addEventListener('keydown', (e) => {
  const code = mapKey(e);
  if(!code) return;
  const t = e.target && e.target.tagName;
  if(t === 'INPUT' || t === 'TEXTAREA' || t === 'SELECT') return;
  e.preventDefault();
  api('/api/key', {method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({code, pressed:1})});
});

setInterval(refresh, 100);
refresh();
</script>
</body>
</html>
"""


def start_gui(
    sim: Any,
    binary_path: str,
    port: int = 8765,
    scale: int = 2,
    open_browser: bool = True,
    title: str = "ZX16",
) -> DebuggerSession:
    session = DebuggerSession(sim, binary_path, scale=scale, title=title)

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            pass

        def _json(self, obj: Any, code: int = 200) -> None:
            body = json.dumps(obj).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def _read_json(self) -> dict:
            n = int(self.headers.get("Content-Length", "0") or 0)
            if n <= 0:
                return {}
            return json.loads(self.rfile.read(n).decode("utf-8"))

        def _send_png(self, data: bytes) -> None:
            self.send_response(200)
            self.send_header("Content-Type", "image/png")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            path = urlparse(self.path).path
            if path in ("/", "/index.html"):
                body = HTML_PAGE.encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            elif path.startswith("/frame"):
                with session.lock:
                    session._refresh_video(force=False)
                    if not session.frame_bytes:
                        session._refresh_video(force=True)
                    try:
                        data = session.get_png()
                    except Exception:
                        w, h = session.frame_wh
                        data = (
                            f"P6\n{w} {h}\n255\n".encode("ascii")
                            + session.frame_bytes
                        )
                        self.send_response(200)
                        self.send_header(
                            "Content-Type", "image/x-portable-pixmap"
                        )
                        self.send_header("Cache-Control", "no-store")
                        self.send_header("Content-Length", str(len(data)))
                        self.end_headers()
                        self.wfile.write(data)
                        return
                self._send_png(data)
            elif path.startswith("/tiles"):
                with session.lock:
                    session._refresh_video(force=False)
                    try:
                        data = session.get_tiles_png()
                    except Exception as e:
                        self._json({"error": str(e)}, 500)
                        return
                self._send_png(data)
            elif path.startswith("/tilemap"):
                with session.lock:
                    session._refresh_video(force=False)
                    try:
                        data = session.get_tilemap_png()
                    except Exception as e:
                        self._json({"error": str(e)}, 500)
                        return
                self._send_png(data)
            elif path.startswith("/palette"):
                with session.lock:
                    try:
                        data = session.get_palette_png()
                    except Exception as e:
                        self._json({"error": str(e)}, 500)
                        return
                self._send_png(data)
            elif path == "/api/state":
                self._json(session.snapshot())
            else:
                self.send_error(404)

        def do_POST(self):
            path = urlparse(self.path).path
            body = self._read_json()
            if path == "/api/control":
                c = body.get("cmd", "")
                if c == "run":
                    session.run()
                elif c == "pause":
                    session.pause()
                elif c == "step":
                    session.pause()
                    session.step_one()
                elif c == "step_over":
                    session.pause()
                    session.step_over()
                elif c == "reset":
                    session.reset()
                elif c == "run_to":
                    session.run_to(int(body.get("addr", 0)))
                self._json({"ok": True})
            elif path == "/api/break":
                session.toggle_break(int(body.get("addr", 0)))
                self._json({"ok": True, "bps": sorted(session.breakpoints)})
            elif path == "/api/regs":
                session.set_reg(str(body.get("name", "")), int(body.get("value", 0)))
                self._json({"ok": True})
            elif path == "/api/mem":
                session.set_mem(
                    int(body.get("addr", 0)),
                    int(body.get("value", 0)),
                    int(body.get("size", 1)),
                )
                self._json({"ok": True})
            elif path == "/api/memview":
                with session.lock:
                    session.mem_view_addr = int(body.get("addr", 0x20)) & MASK
                self._json({"ok": True})
            elif path == "/api/key":
                code = int(body.get("code", 0)) & MASK
                pressed = 1 if body.get("pressed", 1) else 0
                with session.lock:
                    session.sim.key_code = code
                    session.sim.key_pressed = pressed
                self._json({"ok": True})
            elif path == "/api/tilebank":
                with session.lock:
                    session.tile_bank = int(body.get("bank", 0)) & 3
                    # invalidate tile atlas cache
                    session._tiles_frame_id = -1
                    session._tiles_png = None
                self._json({"ok": True, "bank": session.tile_bank})
            else:
                self.send_error(404)

    httpd = ThreadingHTTPServer(("127.0.0.1", port), Handler)
    session._httpd = httpd  # type: ignore
    t = threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    url = f"http://127.0.0.1:{port}/"
    print(f"[gui] debugger at {url}", flush=True)
    if open_browser:
        try:
            webbrowser.open(url)
        except Exception:
            pass
    return session


def run_gui_until_exit(session: DebuggerSession) -> None:
    print("[gui] Ctrl+C to quit", flush=True)
    try:
        while True:
            time.sleep(0.5)
    except KeyboardInterrupt:
        print("\n[gui] shutting down", flush=True)
        session.stop()
        httpd = getattr(session, "_httpd", None)
        if httpd:
            httpd.shutdown()
