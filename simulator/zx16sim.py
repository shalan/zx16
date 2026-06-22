#!/usr/bin/env python3
"""Minimal ZX16 ISA simulator — enough to execute compiler output and validate it.

Implements the ZX16 instruction set per the corrected spec:
  - 8 GP registers x0..x7, 16-bit, two's complement
  - PC, byte-addressable 64KB little-endian memory
  - SP (x2) reset to 0xF000
  - ECALL services for basic I/O so test programs can print / read / halt

This is a validation tool for the ZC compiler, not a teaching artifact.
"""
import sys

MASK = 0xFFFF

def s16(v):
    v &= MASK
    return v - 0x10000 if v >= 0x8000 else v

class ZX16:
    def __init__(self, mem_size=0x10000):
        self.mem = bytearray(mem_size)
        self.reg = [0]*8
        self.pc = 0x0020          # programs start at 0x0020 by convention
        self.reg[2] = 0xF000      # sp
        self.halted = False
        self.out = []             # captured stdout (ints/chars)
        self.cycles = 0
        # --- interrupts / traps (see docs/INTERRUPTS.md) ---
        self.ie = False           # global interrupt enable
        self.epc = 0              # return PC saved on trap; restored by RETI
        self.irq_pending = False  # a hardware interrupt is requested
        self.irq_vec = 0          # its vector address (vector_num * 2)
        self.step_req = False     # STEP requested (armed by the next RETI)
        self.step_armed = False   # step active: trap to vector 1 after one instruction
        self.max_cycles = 5_000_000
        # --- MMIO device model (0xF000..0xFFFF) ---
        self.mmio_base = 0xF000
        self.mmio_writes = []     # log of (addr, value, size) writes to MMIO
        self.mmio_regs = {}       # addr -> current value (byte granularity)
        # scripted reads: addr -> list of values returned on successive reads
        self.mmio_read_script = {}

    def load(self, data, addr=0x0020):
        self.mem[addr:addr+len(data)] = data

    def is_mmio(self, a):
        return a >= self.mmio_base

    def _read_byte(self, a):
        if self.is_mmio(a):
            if a in self.mmio_read_script and self.mmio_read_script[a]:
                return self.mmio_read_script[a].pop(0) & 0xFF
            return self.mmio_regs.get(a, 0) & 0xFF
        return self.mem[a]

    def _write_byte(self, a, v):
        v &= 0xFF
        if self.is_mmio(a):
            self.mmio_regs[a] = v
            self.mmio_writes.append((a, v, 1))
        else:
            self.mem[a] = v

    def lw(self, a):
        return self._read_byte(a) | (self._read_byte((a+1)&MASK) << 8)
    def sw(self, a, v):
        if self.is_mmio(a):
            self.mmio_regs[a] = v & 0xFF
            self.mmio_regs[(a+1)&MASK] = (v>>8) & 0xFF
            self.mmio_writes.append((a, v & MASK, 2))
        else:
            self.mem[a] = v & 0xFF
            self.mem[(a+1)&MASK] = (v >> 8) & 0xFF
    def lb(self, a):
        return self._read_byte(a)

    def raise_irq(self, vector_num):
        """Request a hardware interrupt that vectors to entry `vector_num` (address
        vector_num*2). Taken at the next instruction boundary while IE=1."""
        self.irq_pending = True
        self.irq_vec = (vector_num * 2) & MASK

    def step(self):
        armed = self.step_armed   # the instruction this cycle is the one being stepped
        # take a pending hardware interrupt at the instruction boundary (not mid-step)
        if self.ie and self.irq_pending and not armed:
            self.epc = self.pc
            self.ie = False
            self.irq_pending = False
            self.pc = self.irq_vec
        w = self.lw(self.pc)
        op = w & 0x7
        f3 = (w >> 3) & 0x7
        rd = (w >> 6) & 0x7        # rd/rs1
        nextpc = (self.pc + 2) & MASK

        if op == 0:  # R-type
            funct4 = (w >> 12) & 0xF
            rs2 = (w >> 9) & 0x7
            a = self.reg[rd]; b = self.reg[rs2]
            if   funct4 == 0x0: self.reg[rd] = (a + b) & MASK            # ADD
            elif funct4 == 0x1: self.reg[rd] = (a - b) & MASK            # SUB
            elif funct4 == 0x2: self.reg[rd] = 1 if s16(a) < s16(b) else 0   # SLT
            elif funct4 == 0x3: self.reg[rd] = 1 if (a & MASK) < (b & MASK) else 0  # SLTU
            elif funct4 == 0x4: self.reg[rd] = (a << (b & 0xF)) & MASK   # SLL
            elif funct4 == 0x5: self.reg[rd] = (a & MASK) >> (b & 0xF)   # SRL
            elif funct4 == 0x6: self.reg[rd] = (s16(a) >> (b & 0xF)) & MASK  # SRA
            elif funct4 == 0x7: self.reg[rd] = (a | b) & MASK            # OR
            elif funct4 == 0x8: self.reg[rd] = (a & b) & MASK            # AND
            elif funct4 == 0x9: self.reg[rd] = (a ^ b) & MASK            # XOR
            elif funct4 == 0xA: self.reg[rd] = b                         # MV
            elif funct4 == 0xB: nextpc = self.reg[rd]                    # JR  PC<-rd
            elif funct4 == 0xC:                                          # JALR
                tmp = self.reg[rs2]; self.reg[rd] = nextpc; nextpc = tmp
            else: raise Exception(f"bad R funct4 {funct4:x} @ {self.pc:04x}")

        elif op == 1:  # I-type
            imm7 = (w >> 9) & 0x7F
            simm = imm7 - 0x80 if imm7 >= 0x40 else imm7
            a = self.reg[rd]
            if   f3 == 0x0: self.reg[rd] = (a + simm) & MASK            # ADDI
            elif f3 == 0x1: self.reg[rd] = 1 if s16(a) < simm else 0    # SLTI
            elif f3 == 0x2: self.reg[rd] = 1 if (a & MASK) < (simm & MASK) else 0  # SLTUI
            elif f3 == 0x3:                                            # shifts
                styp = (imm7 >> 4) & 0x7; amt = imm7 & 0xF
                if   styp == 0x1: self.reg[rd] = (a << amt) & MASK     # SLLI
                elif styp == 0x2: self.reg[rd] = (a & MASK) >> amt     # SRLI
                elif styp == 0x4: self.reg[rd] = (s16(a) >> amt) & MASK # SRAI
                else: raise Exception(f"bad shift type {styp}")
            elif f3 == 0x4: self.reg[rd] = (a | (imm7 & 0x7F)) & MASK  # ORI (mask low7)
            elif f3 == 0x5: self.reg[rd] = (a & (simm & MASK)) & MASK  # ANDI (signext)
            elif f3 == 0x6: self.reg[rd] = (a ^ (simm & MASK)) & MASK  # XORI (signext)
            elif f3 == 0x7: self.reg[rd] = simm & MASK                 # LI
            else: raise Exception(f"bad I f3 {f3}")

        elif op == 2:  # B-type
            imm_hi = (w >> 12) & 0xF
            rs2 = (w >> 9) & 0x7
            off5 = (imm_hi << 1)
            if off5 >= 0x10: off5 -= 0x20      # 5-bit signed, imm[0]=0
            a = self.reg[rd]; b = self.reg[rs2]
            take = False
            if   f3 == 0x0: take = (a == b)
            elif f3 == 0x1: take = (a != b)
            elif f3 == 0x2: take = (a == 0)
            elif f3 == 0x3: take = (a != 0)
            elif f3 == 0x4: take = (s16(a) <  s16(b))
            elif f3 == 0x5: take = (s16(a) >= s16(b))
            elif f3 == 0x6: take = ((a&MASK) <  (b&MASK))
            elif f3 == 0x7: take = ((a&MASK) >= (b&MASK))
            if take: nextpc = (nextpc + off5) & MASK

        elif op == 3:  # S-type  store
            imm4 = (w >> 12) & 0xF
            rs2 = (w >> 9) & 0x7
            off = imm4 - 0x10 if imm4 >= 0x8 else imm4
            addr = (self.reg[rd] + off) & MASK
            if   f3 == 0x0: self._write_byte(addr, self.reg[rs2])       # SB
            elif f3 == 0x1: self.sw(addr, self.reg[rs2])               # SW
            else: raise Exception("bad S f3")

        elif op == 4:  # L-type  load
            imm4 = (w >> 12) & 0xF
            rs2 = (w >> 9) & 0x7        # base
            off = imm4 - 0x10 if imm4 >= 0x8 else imm4
            addr = (self.reg[rs2] + off) & MASK
            if   f3 == 0x0:                                            # LB signed
                v = self._read_byte(addr); self.reg[rd] = (v - 0x100 if v >= 0x80 else v) & MASK
            elif f3 == 0x1: self.reg[rd] = self.lw(addr)               # LW
            elif f3 == 0x4: self.reg[rd] = self._read_byte(addr)      # LBU
            else: raise Exception("bad L f3")

        elif op == 5:  # J-type, PC-relative to PC+2
            link = (w >> 15) & 0x1
            imm_hi = (w >> 9) & 0x3F     # imm[9:4]
            imm_lo = (w >> 3) & 0x7      # imm[3:1]
            off = (imm_hi << 4) | (imm_lo << 1)   # imm[9:1] with imm[0]=0
            if off >= 0x200: off -= 0x400          # 10-bit signed (sign bit = bit 9)
            if link: self.reg[rd] = nextpc
            nextpc = (nextpc + off) & MASK

        elif op == 6:  # U-type
            flag = (w >> 15) & 0x1
            imm_hi = (w >> 9) & 0x3F
            imm_lo = (w >> 3) & 0x7
            v9 = (imm_hi << 3) | imm_lo
            val = (v9 << 7) & MASK
            if flag == 0: self.reg[rd] = val                 # LUI
            else: self.reg[rd] = (self.pc + val) & MASK       # AUIPC

        elif op == 7:  # SYS: ECALL / EBREAK / RETI / EI / DI / MFEPC / MTEPC  (f3=[5:3])
            if   f3 == 0x0: self.ecall((w >> 6) & 0x3FF)                          # ECALL
            elif f3 == 0x1: self.epc = self.pc; self.ie = False; nextpc = 0x0002  # EBREAK -> vec 1
            elif f3 == 0x2:                                                       # RETI
                nextpc = self.epc; self.ie = True
                if self.step_req: self.step_armed = True; self.step_req = False
            elif f3 == 0x3: self.ie = True                                        # EI
            elif f3 == 0x4: self.ie = False                                       # DI
            elif f3 == 0x5: self.reg[rd] = self.epc                               # MFEPC rd
            elif f3 == 0x6: self.epc = self.reg[rd]                               # MTEPC rd
            elif f3 == 0x7: self.step_req = True                                  # STEP (armed by RETI)

        self.pc = nextpc
        if armed and not self.halted:        # single-step: trap to vector 1 after one instruction
            self.step_armed = False
            self.epc = self.pc
            self.ie = False
            self.pc = 0x0002
        self.cycles += 1

    def ecall(self, svc):
        # Minimal service set for validation:
        #  0x000 print int in a0 (x6)
        #  0x001 print char in a0
        #  0x3FF halt
        if svc == 0x3FF:
            self.halted = True
        elif svc == 0x000:
            self.out.append(('int', s16(self.reg[6])))
        elif svc == 0x001:
            self.out.append(('char', self.reg[6] & 0xFF))
        else:
            # unknown service: ignore
            pass

    def run(self):
        while not self.halted:
            self.step()
            if self.cycles > self.max_cycles:
                raise Exception("cycle limit exceeded (infinite loop?)")
        return self.out


def assemble_and_run(asm_text, asm_path=None, pre_run=None):
    """Helper: assemble ZX16 source via the repo assembler, then execute.
    pre_run(sim) is called after load, before run() — used to script MMIO reads.
    asm_path defaults to ../assembler/zx16asm.py relative to this file."""
    import subprocess, tempfile, os
    if asm_path is None:
        asm_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                '..', 'assembler', 'zx16asm.py')
    with tempfile.NamedTemporaryFile('w', suffix='.s', delete=False) as f:
        f.write(asm_text); src = f.name
    out_bin = src + '.bin'
    r = subprocess.run([sys.executable, asm_path, src, '-o', out_bin],
                       capture_output=True, text=True)
    if 'successfully' not in r.stdout:
        raise Exception("assembly failed:\n" + r.stdout + r.stderr)
    data = open(out_bin, 'rb').read()
    sim = ZX16()
    # assembler emits a full 64KB image with sections already at absolute addrs
    sim.load(data, 0x0000)
    if pre_run: pre_run(sim)
    return sim.run(), sim


if __name__ == '__main__':
    # self-check against known multiply program (7*6 = 42)
    prog = """
.text
.org 0x0020
main:
    li   x6, 6
    push x6
    li   x6, 7
    push x6
    call __mul
    addi x2, 4
    ecall 0x000
    ecall 0x3FF
__mul:
    lw   x3, 0(x2)
    lw   x4, 2(x2)
    li   x6, 0
mul_loop:
    bz   x3, mul_done
    add  x6, x4
    addi x3, -1
    j    mul_loop
mul_done:
    ret
"""
    out, sim = assemble_and_run(prog)
    print("output:", out)
    assert out == [('int', 42)], out
    print("simulator self-check PASSED (7*6=42)")
