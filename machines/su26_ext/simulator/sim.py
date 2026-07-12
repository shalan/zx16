"""su26-ext simulator: su26 + UART + timer + enhanced 2D GFX."""

from __future__ import annotations

import sys
import time
from pathlib import Path

_ROOT = Path(__file__).resolve().parents[3]
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from machines.common.isa_core import MASK
from machines.su26.simulator.sim import Su26Sim
from machines.su26_ext.simulator.gfx import render_frame_ext

# UART
UART_BASE = 0xC000
UART_BRR = UART_BASE + 0x100
# Timer
TMR_BASE = 0xD000
TMR_ARR = TMR_BASE + 0x108
# GFX
GFX_BASE = 0xE000
GFX_CTRL = GFX_BASE + 0x00
GFX_STATUS = GFX_BASE + 0x04
GFX_FRAME = GFX_BASE + 0x08
GFX_SCROLL_X = GFX_BASE + 0x0C
GFX_SCROLL_Y = GFX_BASE + 0x10
GFX_BG_COLOR = GFX_BASE + 0x14
GFX_FRAME_DIV = GFX_BASE + 0x18
OAM_BASE = 0xE040
ATTR_BASE = 0xE100
TILE_HI = 0xE800
PALETTE_END = 0xFA80  # FA00-FA7F palette


class Su26ExtSim(Su26Sim):
    """Su26 + UART + timer + GFXCTRL/sprites/attr/32 tiles."""

    name = "su26-ext"

    def __init__(self):
        self.uart_cr = 0x301
        self.uart_brr = 0
        self.uart_rx: list[int] = []
        self.uart_tx_log: list[int] = []

        self.tmr_cr = 0
        self.tmr_psc = 0
        self.tmr_arr = 0xFFFF
        self.tmr_cnt = 0
        self.tmr_uif = 0
        self._tmr_div = 0

        # GFXCTRL state (also mirrored into mem for CPU load/store simplicity)
        self.gfx_ctrl = 0x0005  # enable + sprites
        self.gfx_status = 0
        self.gfx_frame = 0
        self.gfx_scroll_x = 0
        self.gfx_scroll_y = 0
        self.gfx_bg = 0x0000
        self.gfx_frame_div = 8000
        self._steps_in_frame = 0

        self._t0 = time.time()
        self.last_frame_rgb: bytes | None = None
        super().__init__()
        self.read_byte = self._rb_ext
        self.write_byte = self._wb_ext

    def reset(self) -> None:
        super().reset()
        self.uart_cr = 0x301
        self.uart_rx.clear()
        self.uart_tx_log.clear()
        self.tmr_cr = 0
        self.tmr_psc = 0
        self.tmr_arr = 0xFFFF
        self.tmr_cnt = 0
        self.tmr_uif = 0
        self._tmr_div = 0
        self.gfx_ctrl = 0x0005
        self.gfx_status = 0
        self.gfx_frame = 0
        self.gfx_scroll_x = 0
        self.gfx_scroll_y = 0
        self.gfx_bg = 0
        self.gfx_frame_div = 8000
        self._steps_in_frame = 0
        self._t0 = time.time()
        self.last_frame_rgb = None
        # Do NOT wipe OAM / ATTR / tile RAM here — load_bin_file() calls
        # reset() after loading a full 64 KB image that already contains VRAM.

    def load_bin_file(self, path: str) -> None:
        """Load ROM/RAM image; preserve VRAM when the file is a full 64 KB dump."""
        data = Path(path).read_bytes()
        if len(data) == 0x10000:
            self.load(data, 0)
            # CPU / peripheral soft-reset only (keep mem including ATTR, tiles)
            self.reg = [0] * 8
            self.pc = 0x0020
            self.reg[2] = 0xEFFE
            self.halted = False
            self.cycles = 0
            self.uart_cr = 0x301
            self.uart_rx.clear()
            self.uart_tx_log.clear()
            self.tmr_cr = 0
            self.tmr_psc = 0
            self.tmr_arr = 0xFFFF
            self.tmr_cnt = 0
            self.tmr_uif = 0
            self._tmr_div = 0
            # Mirror GFXCTRL enable from image if present, else default on
            self.gfx_ctrl = self.mem[GFX_CTRL] | (self.mem[GFX_CTRL + 1] << 8)
            if self.gfx_ctrl == 0:
                self.gfx_ctrl = 0x0001
            self.gfx_status = 0
            self.gfx_frame = 0
            self.gfx_scroll_x = self.mem[GFX_SCROLL_X] | (self.mem[GFX_SCROLL_X + 1] << 8)
            self.gfx_scroll_y = self.mem[GFX_SCROLL_Y] | (self.mem[GFX_SCROLL_Y + 1] << 8)
            self.gfx_bg = self.mem[GFX_BG_COLOR] | (self.mem[GFX_BG_COLOR + 1] << 8)
            fd = self.mem[GFX_FRAME_DIV] | (self.mem[GFX_FRAME_DIV + 1] << 8)
            self.gfx_frame_div = fd if fd else 8000
            self._steps_in_frame = 0
            self.video_dirty = True
        else:
            super().load_bin_file(path)

    def step(self) -> None:
        super().step()
        self._timer_tick()
        self._gfx_tick()

    def _timer_tick(self) -> None:
        if (self.tmr_cr & 1) == 0:
            return
        self._tmr_div += 1
        if self._tmr_div <= self.tmr_psc:
            return
        self._tmr_div = 0
        self.tmr_cnt = (self.tmr_cnt + 1) & MASK
        if self.tmr_cnt > self.tmr_arr:
            self.tmr_cnt = 0
            self.tmr_uif = 1

    def _gfx_tick(self) -> None:
        if (self.gfx_ctrl & 1) == 0:
            return
        self._steps_in_frame += 1
        div = max(1, self.gfx_frame_div)
        if self._steps_in_frame >= div:
            self._steps_in_frame = 0
            self.gfx_frame = (self.gfx_frame + 1) & MASK
            self.gfx_status |= 1  # vblank
            self.video_dirty = True

    def render_rgb(self) -> bytes:
        blank = bool(self.gfx_ctrl & 2)
        sprites = bool(self.gfx_ctrl & 4)
        rgb = render_frame_ext(
            self.mem,
            scroll_x=self.gfx_scroll_x,
            scroll_y=self.gfx_scroll_y,
            bg_color565=self.gfx_bg,
            sprites_en=sprites,
            blank=blank or not (self.gfx_ctrl & 1),
        )
        self.last_frame_rgb = rgb
        self.video_dirty = False
        return rgb

    # ---- memory ----
    def _rb_ext(self, a: int) -> int:
        a &= MASK
        if UART_BASE <= a <= UART_BRR + 1:
            return self._uart_read(a)
        if TMR_BASE <= a <= TMR_ARR + 1:
            return self._tmr_read(a)
        if GFX_BASE <= a < OAM_BASE:
            return self._gfx_read(a)
        # ATTR, OAM, TILE_HI, expanded palette: plain mem
        if OAM_BASE <= a < 0xF000:
            return self.mem[a]
        if 0xFA00 <= a < PALETTE_END:
            return self.mem[a]
        # parent: FA10+ was inert — allow FA00-FA7F above; rest use parent
        if a >= PALETTE_END:
            return 0
        return super()._rb(a)

    def _wb_ext(self, a: int, v: int) -> None:
        a &= MASK
        v &= 0xFF
        if UART_BASE <= a <= UART_BRR + 1:
            self._uart_write(a, v)
            return
        if TMR_BASE <= a <= TMR_ARR + 1:
            self._tmr_write(a, v)
            return
        if GFX_BASE <= a < OAM_BASE:
            self._gfx_write(a, v)
            return
        if OAM_BASE <= a < 0xF000:
            self.mem[a] = v
            self.video_dirty = True
            return
        if 0xFA00 <= a < PALETTE_END:
            self.mem[a] = v
            self.video_dirty = True
            return
        if a >= PALETTE_END:
            return
        super()._wb(a, v)

    def _gfx_read(self, a: int) -> int:
        off = a - GFX_BASE
        regs = {
            0x00: self.gfx_ctrl,
            0x04: self.gfx_status,
            0x08: self.gfx_frame,
            0x0C: self.gfx_scroll_x,
            0x10: self.gfx_scroll_y,
            0x14: self.gfx_bg,
            0x18: self.gfx_frame_div,
        }
        for base, val in regs.items():
            if off == base:
                return val & 0xFF
            if off == base + 1:
                return (val >> 8) & 0xFF
        return 0

    def _gfx_write(self, a: int, v: int) -> None:
        off = a - GFX_BASE
        v &= 0xFF

        def pair(lo_off: int, attr: str) -> None:
            cur = getattr(self, attr)
            if off == lo_off:
                setattr(self, attr, (cur & 0xFF00) | v)
            elif off == lo_off + 1:
                setattr(self, attr, (cur & 0x00FF) | (v << 8))

        if off in (0x00, 0x01):
            pair(0x00, "gfx_ctrl")
        elif off == 0x04 and v & 1:
            self.gfx_status &= ~1
        elif off in (0x0C, 0x0D):
            pair(0x0C, "gfx_scroll_x")
            self.gfx_scroll_x %= 320
        elif off in (0x10, 0x11):
            pair(0x10, "gfx_scroll_y")
            self.gfx_scroll_y %= 240
        elif off in (0x14, 0x15):
            pair(0x14, "gfx_bg")
        elif off in (0x18, 0x19):
            pair(0x18, "gfx_frame_div")
            if self.gfx_frame_div == 0:
                self.gfx_frame_div = 1
        self.video_dirty = True

    # ---- UART / timer (unchanged logic) ----
    def _uart_read(self, a: int) -> int:
        off = a - UART_BASE
        if off in (0x004, 0x005):
            sr = 0x01 | (0x02 if self.uart_rx else 0)
            return sr if off == 0x004 else 0
        if off == 0x008 and self.uart_rx:
            return self.uart_rx.pop(0) & 0xFF
        if off in (0x000, 0x001):
            return (self.uart_cr >> (8 * off)) & 0xFF
        if off in (0x100, 0x101):
            return (self.uart_brr >> (8 * (off - 0x100))) & 0xFF
        return 0

    def _uart_write(self, a: int, v: int) -> None:
        off = a - UART_BASE
        if off == 0x008:
            self.uart_tx_log.append(v)
            print(chr(v), end="", flush=True)
            self.console.append(chr(v))
        elif off == 0x000:
            self.uart_cr = (self.uart_cr & 0xFF00) | v
        elif off == 0x001:
            self.uart_cr = (self.uart_cr & 0x00FF) | (v << 8)
        elif off == 0x100:
            self.uart_brr = (self.uart_brr & 0xFF00) | v
        elif off == 0x101:
            self.uart_brr = (self.uart_brr & 0x00FF) | (v << 8)

    def _tmr_read(self, a: int) -> int:
        off = a - TMR_BASE
        regmap = {
            0x000: self.tmr_cr,
            0x024: self.tmr_uif & 1,
            0x100: self.tmr_cnt,
            0x104: self.tmr_psc,
            0x108: self.tmr_arr,
        }
        for base, val in regmap.items():
            if off == base:
                return val & 0xFF
            if off == base + 1:
                return (val >> 8) & 0xFF
        return 0

    def _tmr_write(self, a: int, v: int) -> None:
        off = a - TMR_BASE
        v &= 0xFF

        def set_lo(cur: int) -> int:
            return (cur & 0xFF00) | v

        def set_hi(cur: int) -> int:
            return (cur & 0x00FF) | (v << 8)

        if off == 0x000:
            self.tmr_cr = set_lo(self.tmr_cr)
        elif off == 0x001:
            self.tmr_cr = set_hi(self.tmr_cr)
        elif off == 0x02C and v & 1:
            self.tmr_uif = 0
        elif off == 0x100:
            self.tmr_cnt = set_lo(self.tmr_cnt)
        elif off == 0x101:
            self.tmr_cnt = set_hi(self.tmr_cnt)
        elif off == 0x104:
            self.tmr_psc = set_lo(self.tmr_psc)
        elif off == 0x105:
            self.tmr_psc = set_hi(self.tmr_psc)
        elif off == 0x108:
            self.tmr_arr = set_lo(self.tmr_arr)
        elif off == 0x109:
            self.tmr_arr = set_hi(self.tmr_arr)

    def ecall(self, svc: int) -> None:
        a0, a1 = self.reg[6], self.reg[7]
        if svc == 0x050:
            self.reg[6] = int((time.time() - self._t0) * 1000) & MASK
        elif svc == 0x051:
            self.tmr_arr = a0 & MASK
            self.tmr_cr |= 1
            self.tmr_cnt = 0
            self._tmr_div = 0
        elif svc == 0x052:
            self.tmr_cr |= 1
            guard = 0
            while self.tmr_uif == 0 and guard < 2_000_000:
                self._timer_tick()
                guard += 1
            self.tmr_uif = 0
        elif svc == 0x060:
            ch = a0 & 0xFF
            self.uart_tx_log.append(ch)
            print(chr(ch), end="", flush=True)
            self.console.append(chr(ch))
        elif svc == 0x061:
            if self.uart_rx:
                self.reg[6] = self.uart_rx.pop(0) & 0xFF
            else:
                try:
                    s = input()
                    self.reg[6] = ord(s[0]) & 0xFF if s else 10
                    for c in s[1:]:
                        self.uart_rx.append(ord(c) & 0xFF)
                except EOFError:
                    self.reg[6] = 0
        elif svc == 0x062:
            self.reg[6] = 1 if self.uart_rx else 0
        elif svc == 0x070:  # gfx_wait_vblank
            # Advance frames without hanging the GUI for millions of empty ticks:
            # jump to next frame boundary (still models FRAME/STATUS correctly).
            self._steps_in_frame = 0
            self._gfx_tick()  # with steps already at 0, need full div ticks
            # force one frame edge:
            self._steps_in_frame = max(0, self.gfx_frame_div - 1)
            self._gfx_tick()
            self.gfx_status &= ~1
            self.video_dirty = True
        elif svc == 0x071:  # gfx_get_frame
            self.reg[6] = self.gfx_frame & MASK
        elif svc == 0x072:  # gfx_set_scroll
            self.gfx_scroll_x = a0 % 320
            self.gfx_scroll_y = a1 % 240
            self.video_dirty = True
        else:
            super().ecall(svc)

    def feed_uart_rx(self, data: bytes | str) -> None:
        if isinstance(data, str):
            data = data.encode()
        self.uart_rx.extend(data)
