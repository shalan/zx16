"""ZX16 instruction disassembler."""

REG = ["t0", "ra", "sp", "s0", "s1", "t1", "a0", "a1"]


def _reg(i: int) -> str:
    return REG[i & 7]


def disassemble(w: int, pc: int = 0) -> str:
    op, f3, rd = w & 7, (w >> 3) & 7, (w >> 6) & 7
    if op == 0:
        funct4, rs2 = (w >> 12) & 0xF, (w >> 9) & 7
        names = {
            0: "add", 1: "sub", 2: "slt", 3: "sltu", 4: "sll", 5: "srl", 6: "sra",
            7: "or", 8: "and", 9: "xor", 0xA: "mv", 0xB: "jr", 0xC: "jalr",
        }
        r = names.get(funct4)
        if not r:
            return f".word 0x{w:04x}"
        if r == "jr":
            return f"jr {_reg(rd)}"
        if r == "jalr":
            return f"jalr {_reg(rd)}, {_reg(rs2)}"
        if r == "mv":
            return f"mv {_reg(rd)}, {_reg(rs2)}"
        return f"{r} {_reg(rd)}, {_reg(rs2)}"
    if op == 1:
        imm7 = (w >> 9) & 0x7F
        simm = imm7 - 0x80 if imm7 >= 0x40 else imm7
        if f3 == 3:
            styp, amt = (imm7 >> 4) & 7, imm7 & 0xF
            name = {1: "slli", 2: "srli", 4: "srai"}.get(styp, "shift?")
            return f"{name} {_reg(rd)}, {amt}"
        name = {0: "addi", 1: "slti", 2: "sltui", 4: "ori", 5: "andi", 6: "xori", 7: "li"}.get(f3)
        if not name:
            return f".word 0x{w:04x}"
        if name == "li":
            return f"li {_reg(rd)}, {simm}"
        if name == "ori":
            return f"ori {_reg(rd)}, {imm7 & 0x7F}"
        return f"{name} {_reg(rd)}, {simm}"
    if op == 2:
        imm_hi, rs2 = (w >> 12) & 0xF, (w >> 9) & 7
        off = imm_hi << 1
        if off >= 0x10:
            off -= 0x20
        tgt = (pc + 2 + off) & 0xFFFF
        name = {0: "beq", 1: "bne", 2: "bz", 3: "bnz", 4: "blt", 5: "bge", 6: "bltu", 7: "bgeu"}.get(f3, "b?")
        if name in ("bz", "bnz"):
            return f"{name} {_reg(rd)}, 0x{tgt:04x}"
        return f"{name} {_reg(rd)}, {_reg(rs2)}, 0x{tgt:04x}"
    if op == 3:
        imm4, rs2 = (w >> 12) & 0xF, (w >> 9) & 7
        off = imm4 - 0x10 if imm4 >= 0x8 else imm4
        return f"{'sb' if f3 == 0 else 'sw'} {_reg(rs2)}, {off}({_reg(rd)})"
    if op == 4:
        imm4, rs2 = (w >> 12) & 0xF, (w >> 9) & 7
        off = imm4 - 0x10 if imm4 >= 0x8 else imm4
        name = {0: "lb", 1: "lw", 4: "lbu"}.get(f3, "l?")
        return f"{name} {_reg(rd)}, {off}({_reg(rs2)})"
    if op == 5:
        link = (w >> 15) & 1
        imm_hi, imm_lo = (w >> 9) & 0x3F, (w >> 3) & 7
        off = (imm_hi << 4) | (imm_lo << 1)
        if off >= 0x200:
            off -= 0x400
        tgt = (pc + 2 + off) & 0xFFFF
        return f"jal {_reg(rd)}, 0x{tgt:04x}" if link else f"j 0x{tgt:04x}"
    if op == 6:
        flag = (w >> 15) & 1
        v9 = (((w >> 9) & 0x3F) << 3) | ((w >> 3) & 7)
        return f"{'auipc' if flag else 'lui'} {_reg(rd)}, {v9}"
    if op == 7:
        svc = (w >> 6) & 0x3FF
        if f3 == 0:
            return f"ecall 0x{svc:03x}"
        return f"sys f3={f3}"
    return f".word 0x{w:04x}"
