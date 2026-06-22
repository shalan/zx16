#!/usr/bin/env python3
"""Differential check of the trap + single-step mechanism on the 2-stage AHB-Lite core
vs. the golden sim, at zero and two wait states (the pipeline + registered D-bus make
the trap/step paths interact with HREADY stalls). Programs: EBREAK round-trip, and a
debug ISR single-stepping the debuggee one instruction at a time."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify_ahb as VA                         # noqa: E402

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

vvp = VA.build()
npass = ntot = 0
for label, prog, want_vals in [("EBREAK round-trip", EBREAK_PROG, [100, 150, 200]),
                               ("single-step a0 0->1->2->3", STEP_PROG, [0, 1, 2, 3, 3])]:
    want = VA.sim_output(prog)
    mem = VA.mem_image(prog)
    for ws in (0, 2):
        got = VA.rtl_output(vvp, mem, ws=ws)
        ok = (got == want) and ([v for _, v in got] == want_vals)
        ntot += 1; npass += ok
        print(f"{'PASS' if ok else 'FAIL'}  {label:<26} ws={ws}  rtl={[v for _,v in got]}")

print(f"\n{npass}/{ntot} AHB-core trap/step checks match the sim (ws 0 & 2)")
sys.exit(0 if npass == ntot else 1)
