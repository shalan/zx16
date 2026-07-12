# su26-ext Enhanced 2D Graphics Architecture

**Machine:** `su26-ext`  
**Status:** Implemented in simulator + `machine.yaml`  
**Base:** Su26 tilemap (handout-compatible defaults)

---

## 1. Goals

| Goal | Approach |
|------|----------|
| Better art than 16 tiles / 16 colors | **32 tiles**, **palette banks** (32–64 colors) |
| Keep RAM/gates low | Stay **4 bpp indexed** (not 8 bpp / not full FB) |
| Smooth games | **Vblank + frame counter** (GFXCTRL) |
| Moving objects | **8 sprites** (OAM) |
| su26 software | Works if ATTR=0, bank=0, sprites off, scroll=0, tiles 0–15 only |

---

## 2. Configuration summary

| Parameter | Value |
|-----------|--------|
| Resolution | 320×240 |
| Tile size | 16×16 |
| Map | 20×15 cells (300 bytes) |
| Tiles | **32** × 4 bpp = **4 KB** total |
| Map entry | tile index 0–31 (6 bits used; byte store) |
| Attr entry | bank / flip / priority (1 byte/cell) |
| Palette | **4 banks × 16 entries × RGB565** = **128 B** |
| Colors on screen | up to **64** (4×16) |
| Sprites | **8**, 16×16, same tile set |
| Pixel packing | even column = low nibble, odd = high nibble |

**VRAM class total:** ~4 KB tiles + 300 map + 300 attr + 128 pal + 64 OAM + ctrl ≈ **~5 KB**.

---

## 3. Memory map

```
0xE000–0xE03F   GFXCTRL (MMIO regs)
0xE040–0xE07F   OAM (8 sprites × 8 bytes)
0xE100–0xE22B   ATTR map (300 bytes; pad to 0xE2FF)
0xE800–0xEFFF   TILEDATA bank H: tiles 16–31 (2048 B)
0xF000–0xF12B   TILEMAP (300 B)          — su26
0xF200–0xF9FF   TILEDATA bank L: tiles 0–15 (2048 B) — su26 extended use
0xFA00–0xFA7F   PALETTE RGB565, 4 banks × 16 (128 B)
0xFA80–0xFFFF   reserved / inert (su26-ext)
```

### 3.1 GFXCTRL (`0xE000`)

| Offset | Name | Bits / meaning |
|--------|------|----------------|
| +0x00 | CTRL | [0] enable display [1] blank [2] sprites enable |
| +0x04 | STATUS | [0] vblank (R; write 1 clears) |
| +0x08 | FRAME | 16-bit frame counter (R) |
| +0x0C | SCROLL_X | pixel scroll 0–319 |
| +0x10 | SCROLL_Y | pixel scroll 0–239 |
| +0x14 | BG_COLOR | RGB565 underlay when transparent |
| +0x18 | FRAME_DIV | sim: CPU steps per frame (default 8000) |

### 3.2 ATTR map (`0xE100 + row*20 + col`)

| Bits | Field |
|------|--------|
| 1:0 | palette bank 0–3 |
| 2 | flip X |
| 3 | flip Y |
| 4 | BG priority over sprites (1 = BG wins) |
| 7:5 | reserved 0 |

### 3.3 OAM sprite `i` at `0xE040 + i*8`

| Offset | Field |
|--------|--------|
| +0 | X (pixels, 0–255; 0–319 used) |
| +1 | Y |
| +2 | tile index 0–31 |
| +3 | attr: [0] enable [1] flipX [2] flipY [4:3] bank [5] priority (1=above BG) |
| +4..7 | reserved 0 |

### 3.4 Tile data

- Tile `t` in 0..15: `0xF200 + t*128`  
- Tile `t` in 16..31: `0xE800 + (t-16)*128`  
- 128 bytes/tile, 4 bpp row-major, 2 pixels/byte  

### 3.5 Palette RGB565 LE

Bank `b`, index `c`: address `0xFA00 + (b*16 + c)*2`  
Low byte first. Format: `RRRRR GGGGGG BBBBB` (5-6-5).

su26 RGB332 programs writing single bytes at `0xFA00` still affect low bytes of bank 0; for best results use RGB565 stores on su26-ext.

---

## 4. Compositor (HW / sim)

Per output pixel `(px, py)`:

1. `mx = (px + SCROLL_X) % 320`, `my = (py + SCROLL_Y) % 240`  
2. Map cell `(mx/16, my/16)`; fetch tile index + attr  
3. Local `(tx,ty)`; apply flip from attr  
4. Fetch 4 bpp color index; look up `palette[bank][index]`  
5. For each enabled sprite containing `(px,py)`, same tile path; color 0 = transparent  
6. Priority: sprite above BG unless BG attr priority set / sprite prio clear  
7. If blank or disabled: `BG_COLOR`

---

## 5. Extra ecalls (su26-ext)

| svc | Name | Behavior |
|-----|------|----------|
| `0x070` | gfx_wait_vblank | Spin until STATUS.vblank; then clear |
| `0x071` | gfx_get_frame | `a0 = FRAME` |
| `0x072` | gfx_set_scroll | `a0=SCROLL_X`, `a1=SCROLL_Y` |

---

## 6. Hardware implications (summary)

| Resource | Impact |
|----------|--------|
| Tile BRAM | **2 KB → 4 KB** (split windows L/H) |
| Attr RAM | **+300 B** |
| Palette | **+112 B** order (16→128) |
| OAM | **+64 B** |
| Logic | Scroll adders, flip, bank mux, **8-sprite** eval, vblank FSM |
| su26 compat | Defaults zero → legacy look |

See also discussion in project notes: prefer banking over 8 bpp for this SoC class.

---

## 7. Software

| File | Role |
|------|------|
| `cc/lib/gfx.h` | register defines |
| `cc/examples/gfx_scroll.c` | scroll + vblank demo |
| `examples/max_colors.s` | **all 64 colors** (4 banks × 16) as horizontal bands |
| `examples/all_tiles.s` | **all 32 tiles** from SMB NES tileset (asset 52571) |
| `examples/scroll_live.s` | live scroll + sprite for `--gui` |
| Simulator | `machines/su26_ext/simulator/gfx.py` + `sim.py` |
| `tools/import_smb_tiles.py` | rip 16×16 tiles from Spriters Resource sheet → VRAM |
| `tools/build_all_tiles.py` | build `bins/all_tiles.bin` + preview |

### All tiles demo (SMB)

Art source: [Spriters Resource — Super Mario Bros. NES Tileset (52571)](https://www.spriters-resource.com/nes/supermariobros/asset/52571/)

```bash
# sheet at assets/smb/52571.png (see assets/smb/SOURCE.txt)
python3 tools/build_all_tiles.py
python3 -m machines.zx16sim --machine su26-ext bins/all_tiles.bin --gui
```

Uses all 32 tile slots, 4 palette banks, ATTR map, tiles LO+HI.

### Max colors demo

```bash
python3 tools/zx16asm.py machines/su26_ext/examples/max_colors.s -o bins/max_colors.bin -f bin
python3 -m machines.zx16sim --machine su26-ext bins/max_colors.bin --gui
# or preview: zx16_video/max_colors/frame.png
```

BG layer: palette index **0 is opaque** (`palette[bank][0]`). Sprites still use 0 as transparent.

---

## 8. Revision

| Ver | Notes |
|-----|--------|
| 1.0 | Initial su26-ext gfx: 32 tiles, banks, attr, sprites, GFXCTRL |
