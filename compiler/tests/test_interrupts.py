#!/usr/bin/env python3
"""ZX16 interrupt/trap mechanism (reference model in zx16sim.py; see docs/INTERRUPTS.md).
Covers: EBREAK -> vector-1 handler -> MFEPC/ADDI/MTEPC (skip the ebreak) -> RETI; a
hardware IRQ -> vector handler -> RETI; and IRQ masking while IE=0.

SYS sub-instructions: EBREAK / RETI / EI / DI / MFEPC / MTEPC (assembler mnemonics).
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "simulator"))
import importlib, zx16sim as Z          # noqa: E402
importlib.reload(Z)

EBREAK = "    ebreak"
RETI   = "    reti"
EI     = "    ei"
MFEPC6 = "    mfepc x6"
MTEPC6 = "    mtepc x6"

npass = ntot = 0
def check(label, cond, got=None):
    global npass, ntot
    ntot += 1; npass += bool(cond)
    print(("PASS " if cond else "FAIL ") + label + ("" if cond else f"   got={got}"))
def ints(out): return [v for k, v in out]

# 1) EBREAK -> handler (print 150) -> advance EPC past the ebreak -> RETI
prog1 = f"""
.text
.org 0x0002
    j ebk_handler
.org 0x0020
main:
    li16 x6, 100
    ecall 0x000
{EBREAK}
    li16 x6, 200
    ecall 0x000
    ecall 0x3FF
ebk_handler:
    li16 x6, 150
    ecall 0x000
{MFEPC6}
    addi x6, 2
{MTEPC6}
{RETI}
"""
out, _ = Z.assemble_and_run(prog1)
check("EBREAK -> vector1 handler -> EPC+2 -> RETI", ints(out) == [100, 150, 200], ints(out))

# 2) hardware IRQ (vector 2) taken after EI -> handler (print 2) -> RETI resumes
prog2 = f"""
.text
.org 0x0004
    j irq_handler
.org 0x0020
main:
    li16 x6, 1
    ecall 0x000
{EI}
    li16 x6, 3
    ecall 0x000
    ecall 0x3FF
irq_handler:
    li16 x6, 2
    ecall 0x000
{RETI}
"""
out, _ = Z.assemble_and_run(prog2, pre_run=lambda s: s.raise_irq(2))
check("hardware IRQ -> vector2 handler -> RETI resumes", ints(out) == [1, 2, 3], ints(out))

# 3) IRQ stays masked while IE=0 (no EI): handler never runs
prog3 = """
.text
.org 0x0004
    j irq_handler
.org 0x0020
main:
    li16 x6, 1
    ecall 0x000
    li16 x6, 3
    ecall 0x000
    ecall 0x3FF
irq_handler:
    li16 x6, 2
    ecall 0x000
    reti
"""
out, _ = Z.assemble_and_run(prog3, pre_run=lambda s: s.raise_irq(2))
check("IRQ masked while IE=0 (no handler)", ints(out) == [1, 3], ints(out))

# 4) single-step: a debug ISR steps the debuggee one instruction at a time. STEP arms
# the step at the next RETI, which then traps to vector 1 after exactly one instruction.
# The debuggee only uses x6 (a0); the ISR uses x4/x7 (x7 = persistent step counter).
prog4 = """
.text
.org 0x0002
    j isr
.org 0x0020
main:
    li16 x6, 0
    ebreak
    addi x6, 1
    addi x6, 1
    addi x6, 1
    ecall 0x000
    ecall 0x3FF
isr:
    addi x7, 1            # entry count
    li16 x4, 1
    bne  x7, x4, isr_pr   # only the first entry (the ebreak) advances EPC past it
    mfepc x4
    addi  x4, 2
    mtepc x4
isr_pr:
    ecall 0x000           # print the debuggee a0 at this step
    li16 x4, 4
    bge  x7, x4, isr_go   # after stepping 3 instrs, continue free
    step
isr_go:
    reti
"""
out, _ = Z.assemble_and_run(prog4)
check("single-step: ISR steps a0 0->1->2->3 then continues", ints(out) == [0, 1, 2, 3, 3], ints(out))

print(f"\n{npass}/{ntot} interrupt tests passed")
sys.exit(0 if npass == ntot else 1)
