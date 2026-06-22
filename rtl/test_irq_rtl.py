#!/usr/bin/env python3
"""Differential check of the interrupt/trap + single-step mechanism on the single-cycle
RTL core vs. the golden sim. Two programs:
  (1) EBREAK -> vector handler adjusts EPC past the ebreak (MFEPC/ADDI/MTEPC) -> RETI.
  (2) single-step: a debug ISR steps the debuggee one instruction at a time (a0 0->1->2->3),
      then continues.
Both run on the RTL core (via tb_zx16) and the sim; their ECALL output must match.
(Hardware-IRQ entry is verified in the sim and exercised in RTL by the SoC IRQ test.)"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify as V                              # noqa: E402

EBREAK_PROG = """
.text
.org 0x0002
    j ebk_handler
.org 0x0020
main:
    li16 x6, 100
    ecall 0x000
    ebreak
    li16 x6, 200
    ecall 0x000
    ecall 0x3FF
ebk_handler:
    li16 x6, 150
    ecall 0x000
    mfepc x6
    addi  x6, 2
    mtepc x6
    reti
"""

STEP_PROG = """
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
    addi x7, 1
    li16 x4, 1
    bne  x7, x4, isr_pr
    mfepc x4
    addi  x4, 2
    mtepc x4
isr_pr:
    ecall 0x000
    li16 x4, 4
    bge  x7, x4, isr_go
    step
isr_go:
    reti
"""

vvp = V.build_rtl()
npass = ntot = 0
for label, prog, want_vals in [("EBREAK round-trip", EBREAK_PROG, [100, 150, 200]),
                               ("single-step a0 0->1->2->3", STEP_PROG, [0, 1, 2, 3, 3])]:
    want = V.sim_output(prog)
    got = V.rtl_output(vvp, V.mem_image(prog))
    ok = (got == want) and ([v for _, v in got] == want_vals)
    ntot += 1; npass += ok
    print(f"{'PASS' if ok else 'FAIL'}  {label:<26} rtl={[v for _,v in got]} sim={[v for _,v in want]}")

print(f"\n{npass}/{ntot} single-cycle RTL trap/step checks match the sim")
sys.exit(0 if npass == ntot else 1)
