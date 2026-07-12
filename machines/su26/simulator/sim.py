"""Su26 machine simulator — handout ecalls + VRAM + PRNG."""

from __future__ import annotations

import sys
from pathlib import Path

# allow `python3 -m machines.zx16sim` from repo root
_ROOT = Path(__file__).resolve().parents[3]
if str(_ROOT) not in sys.path:
    sys.path.insert(0, str(_ROOT))

from machines.common.isa_core import MASK, IsaCore, REG_NAMES, s16

PRNG_DEFAULT = 0xACE1
RESET_PC = 0x0020
RESET_SP = 0xEFFE
TILE_MAP = 0xF000
TILE_DATA = 0xF200
PALETTE = 0xFA00
RESERVED = 0xFA10


class Su26Sim(IsaCore):
    """ZX16 ISS configured as the Su26 course machine."""

    name = "su26"

    def __init__(self):
        super().__init__()
        self.console: list[str] = []
        self.out: list = []
        self.audio_volume = 128
        self.key_code = 0
        self.key_pressed = 0
        self.prng_state = PRNG_DEFAULT
        self.video_dirty = True
        self.read_byte = self._rb
        self.write_byte = self._wb
        self.ecall_handler = self.ecall
        self.reset()

    def reset(self) -> None:
        self.reg = [0] * 8
        self.pc = RESET_PC
        self.reg[2] = RESET_SP
        self.halted = False
        self.cycles = 0
        self.prng_state = PRNG_DEFAULT
        self.console.clear()
        self.out.clear()

    def load_bin_file(self, path: str) -> None:
        data = Path(path).read_bytes()
        if len(data) == 0x10000:
            self.load(data, 0)
        else:
            self.load(data, RESET_PC)
        self.reset()

    def _rb(self, a: int) -> int:
        a &= MASK
        if a >= RESERVED:
            return 0
        return self.mem[a]

    def _wb(self, a: int, v: int) -> None:
        a &= MASK
        v &= 0xFF
        if a >= RESERVED:
            return
        self.mem[a] = v
        if TILE_MAP <= a < PALETTE + 16:
            self.video_dirty = True

    def _emit(self, text: str, end: str = "\n") -> None:
        self.console.append(f"{text}{end}")
        print(text, end=end, flush=True)

    def prng_next(self) -> int:
        s = self.prng_state & MASK
        s ^= (s << 7) & MASK
        s ^= (s >> 9) & MASK
        s ^= (s << 8) & MASK
        s &= MASK
        self.prng_state = s if s else PRNG_DEFAULT
        return self.prng_state

    def ecall(self, svc: int) -> None:
        a0, a1 = self.reg[6], self.reg[7]
        if svc == 0x3FF:
            self.halted = True
        elif svc == 0x000:
            v = s16(a0)
            self._emit(str(v))
            self.out.append(("int", v))
        elif svc == 0x001:
            self._emit(chr(a0 & 0xFF), end="")
            self.out.append(("char", a0 & 0xFF))
        elif svc == 0x010:
            buf, maxlen = a0, a1 & MASK
            try:
                s = input()
            except EOFError:
                s = ""
            n = min(len(s), max(0, maxlen - 1))
            for i in range(n):
                self._wb((buf + i) & MASK, ord(s[i]))
            if maxlen:
                self._wb((buf + n) & MASK, 0)
            self.reg[6] = n
        elif svc == 0x011:
            try:
                s = input().strip()
                self.reg[6] = int(s, 0) & MASK if s else 0
            except (EOFError, ValueError):
                self.reg[6] = 0
        elif svc == 0x012:
            addr, chars = a0, []
            for _ in range(4096):
                c = self._rb(addr)
                if not c:
                    break
                chars.append(chr(c))
                addr = (addr + 1) & MASK
            text = "".join(chars)
            self._emit(text, end="" if text.endswith("\n") else "\n")
            self.out.append(("str", text))
        elif svc == 0x020:
            self.out.append(("tone", a0, a1, self.audio_volume))
            # optional host beep — silent by default in machine pack
        elif svc == 0x021:
            self.audio_volume = max(0, min(255, a0 & MASK))
        elif svc == 0x022:
            self.out.append(("audio_stop",))
        elif svc == 0x030:
            self.reg[6] = self.key_code & MASK
            self.reg[7] = 1 if self.key_pressed else 0
            self.key_pressed = 0
        elif svc == 0x031:
            self.prng_state = (a0 & MASK) or PRNG_DEFAULT
        elif svc == 0x032:
            self.reg[6] = self.prng_next()
        elif svc == 0x040:
            parts = [f"pc={self.pc:04x}"] + [
                f"{REG_NAMES[i]}={self.reg[i]:04x}" for i in range(8)
            ]
            self._emit(" ".join(parts))
        elif svc == 0x041:
            addr, n = a0 & MASK, a1 & MASK
            bs = [self._rb((addr + i) & MASK) for i in range(n)]
            for i in range(0, n, 16):
                chunk = " ".join(f"{b:02x}" for b in bs[i : i + 16])
                self._emit(f"{(addr + i) & MASK:04x}: {chunk}")
        else:
            self.out.append(("ecall_unknown", svc))
