#!/usr/bin/env python3
"""Differential check of the interrupt/trap mechanism on the single-cycle RTL core
vs. the golden sim. Runs an EBREAK program (vector handler adjusts EPC past the
ebreak via MFEPC/ADDI/MTEPC, then RETI) on both and compares ECALL output.
(Hardware-IRQ entry is verified in the sim, compiler/tests/test_interrupts.py, and
exercised in RTL once the SoC interrupt lines are wired.)"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verify as V                              # noqa: E402

PROG = """
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

vvp = V.build_rtl()
want = V.sim_output(PROG)
got  = V.rtl_output(vvp, V.mem_image(PROG))
ok = (got == want) and ([v for _, v in got] == [100, 150, 200])
print(f"  sim: {want}")
print(f"  rtl: {got}")
print(("PASS" if ok else "FAIL") + "  single-cycle RTL EBREAK->handler->EPC+2->RETI matches sim")
sys.exit(0 if ok else 1)
