"""
Shared ZX16 ISA interpreter (Green Card aligned).

Machine profiles supply:
  - reset PC/SP
  - memory read/write hooks (MMIO)
  - ecall(svc) handler
"""

from __future__ import annotations

from typing import Callable

MASK = 0xFFFF
REG_NAMES = ["t0", "ra", "sp", "s0", "s1", "t1", "a0", "a1"]


def s16(v: int) -> int:
    v &= MASK
    return v - 0x10000 if v >= 0x8000 else v


class IsaCore:
    def __init__(self):
        self.mem = bytearray(0x10000)
        self.reg = [0] * 8
        self.pc = 0
        self.halted = False
        self.cycles = 0
        self.max_cycles = 50_000_000
        self.trace = False
        # hooks set by machine
        self.read_byte: Callable[[int], int] = self._mem_rb
        self.write_byte: Callable[[int, int], None] = self._mem_wb
        self.ecall_handler: Callable[[int], None] = lambda svc: None

    def _mem_rb(self, a: int) -> int:
        return self.mem[a & MASK]

    def _mem_wb(self, a: int, v: int) -> None:
        self.mem[a & MASK] = v & 0xFF

    def lw(self, a: int) -> int:
        a &= MASK
        return self.read_byte(a) | (self.read_byte((a + 1) & MASK) << 8)

    def sw(self, a: int, v: int) -> None:
        a &= MASK
        self.write_byte(a, v & 0xFF)
        self.write_byte((a + 1) & MASK, (v >> 8) & 0xFF)

    def load(self, data: bytes, addr: int = 0) -> None:
        self.mem[addr : addr + len(data)] = data

    def step(self) -> None:
        from .disasm import disassemble

        w = self.lw(self.pc)
        op, f3, rd = w & 7, (w >> 3) & 7, (w >> 6) & 7
        nextpc = (self.pc + 2) & MASK
        if self.trace:
            print(f"{self.pc:04x}: {disassemble(w, self.pc)}")

        if op == 0:
            funct4, rs2 = (w >> 12) & 0xF, (w >> 9) & 7
            a, b = self.reg[rd], self.reg[rs2]
            if funct4 == 0:
                self.reg[rd] = (a + b) & MASK
            elif funct4 == 1:
                self.reg[rd] = (a - b) & MASK
            elif funct4 == 2:
                self.reg[rd] = 1 if s16(a) < s16(b) else 0
            elif funct4 == 3:
                self.reg[rd] = 1 if (a & MASK) < (b & MASK) else 0
            elif funct4 == 4:
                self.reg[rd] = (a << (b & 0xF)) & MASK
            elif funct4 == 5:
                self.reg[rd] = (a & MASK) >> (b & 0xF)
            elif funct4 == 6:
                self.reg[rd] = (s16(a) >> (b & 0xF)) & MASK
            elif funct4 == 7:
                self.reg[rd] = (a | b) & MASK
            elif funct4 == 8:
                self.reg[rd] = (a & b) & MASK
            elif funct4 == 9:
                self.reg[rd] = (a ^ b) & MASK
            elif funct4 == 0xA:
                self.reg[rd] = b
            elif funct4 == 0xB:
                nextpc = self.reg[rd]
            elif funct4 == 0xC:
                tmp = self.reg[rs2]
                self.reg[rd] = nextpc
                nextpc = tmp
            else:
                raise RuntimeError(f"bad R funct4 {funct4:x} @ {self.pc:04x}")

        elif op == 1:
            imm7 = (w >> 9) & 0x7F
            simm = imm7 - 0x80 if imm7 >= 0x40 else imm7
            a = self.reg[rd]
            if f3 == 0:
                self.reg[rd] = (a + simm) & MASK
            elif f3 == 1:
                self.reg[rd] = 1 if s16(a) < simm else 0
            elif f3 == 2:
                self.reg[rd] = 1 if (a & MASK) < (simm & MASK) else 0
            elif f3 == 3:
                styp, amt = (imm7 >> 4) & 7, imm7 & 0xF
                if styp == 1:
                    self.reg[rd] = (a << amt) & MASK
                elif styp == 2:
                    self.reg[rd] = (a & MASK) >> amt
                elif styp == 4:
                    self.reg[rd] = (s16(a) >> amt) & MASK
                else:
                    raise RuntimeError(f"bad shift {styp}")
            elif f3 == 4:
                self.reg[rd] = (a | (imm7 & 0x7F)) & MASK
            elif f3 == 5:
                self.reg[rd] = (a & (simm & MASK)) & MASK
            elif f3 == 6:
                self.reg[rd] = (a ^ (simm & MASK)) & MASK
            elif f3 == 7:
                self.reg[rd] = simm & MASK

        elif op == 2:
            imm_hi, rs2 = (w >> 12) & 0xF, (w >> 9) & 7
            off = imm_hi << 1
            if off >= 0x10:
                off -= 0x20
            a, b = self.reg[rd], self.reg[rs2]
            take = {
                0: a == b, 1: a != b, 2: a == 0, 3: a != 0,
                4: s16(a) < s16(b), 5: s16(a) >= s16(b),
                6: (a & MASK) < (b & MASK), 7: (a & MASK) >= (b & MASK),
            }.get(f3, False)
            if take:
                nextpc = (nextpc + off) & MASK

        elif op == 3:
            imm4, rs2 = (w >> 12) & 0xF, (w >> 9) & 7
            off = imm4 - 0x10 if imm4 >= 0x8 else imm4
            addr = (self.reg[rd] + off) & MASK
            if f3 == 0:
                self.write_byte(addr, self.reg[rs2])
            elif f3 == 1:
                self.sw(addr, self.reg[rs2])

        elif op == 4:
            imm4, rs2 = (w >> 12) & 0xF, (w >> 9) & 7
            off = imm4 - 0x10 if imm4 >= 0x8 else imm4
            addr = (self.reg[rs2] + off) & MASK
            if f3 == 0:
                v = self.read_byte(addr)
                self.reg[rd] = (v - 0x100 if v >= 0x80 else v) & MASK
            elif f3 == 1:
                self.reg[rd] = self.lw(addr)
            elif f3 == 4:
                self.reg[rd] = self.read_byte(addr)

        elif op == 5:
            link = (w >> 15) & 1
            imm_hi, imm_lo = (w >> 9) & 0x3F, (w >> 3) & 7
            off = (imm_hi << 4) | (imm_lo << 1)
            if off >= 0x200:
                off -= 0x400
            if link:
                self.reg[rd] = nextpc
            nextpc = (nextpc + off) & MASK

        elif op == 6:
            flag = (w >> 15) & 1
            v9 = (((w >> 9) & 0x3F) << 3) | ((w >> 3) & 7)
            val = (v9 << 7) & MASK
            self.reg[rd] = val if flag == 0 else (self.pc + val) & MASK

        elif op == 7:
            if f3 == 0:
                self.ecall_handler((w >> 6) & 0x3FF)
            # other SYS: ignored at machine discretion

        self.pc = nextpc
        self.cycles += 1

    def run(self, max_cycles: int | None = None) -> None:
        limit = self.max_cycles if max_cycles is None else max_cycles
        while not self.halted:
            self.step()
            if self.cycles > limit:
                raise RuntimeError("cycle limit exceeded")
