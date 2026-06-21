#!/usr/bin/env python3
"""On-chip EBREAK debugger demo on the SoC. Firmware plants a software breakpoint
(saves the original instruction, overwrites it with EBREAK), runs into it; the trap
vectors to a debug ISR that dumps the debuggee's a0 over the UART, restores the
original instruction, and RETIs to re-execute it (continue). Proves the full
breakpoint path on real RTL: plant -> trap -> inspect-over-UART -> restore -> continue.

Expected UART: 'B'(66), a0-at-breakpoint(64), a0-after-continue(65), 'D'(68)."""
import os, sys, subprocess, re
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import soc_run                                    # noqa: E402

ASM = r"""
.org 0x0002
    j dbg_isr                  # ebreak vector (vector 1)
.org 0x0020
start:
    li16 x2, 0xBFFE            # SP
    li16 x5, 0xC000            # UART CR = EN|TXEN
    li16 x6, 0x301
    sw   x6, 0(x5)
    # plant a breakpoint at 'target': save original, overwrite with EBREAK
    la   x5, target
    lw   x6, 0(x5)             # original instruction word
    li16 x4, 0xA000
    sw   x6, 0(x4)             # save original @ 0xA000
    li16 x4, 0xA002
    sw   x5, 0(x4)             # save bp address @ 0xA002
    li16 x6, 0x000F            # EBREAK encoding
    sw   x6, 0(x5)             # plant the breakpoint
    # run the debuggee
    li16 x6, 64                # a0 = 64 (observable at the breakpoint)
target:
    addi x6, 1                 # <- breakpoint here; original bumps a0 to 65
    li16 x5, 0xC008            # UART DR
    sw   x6, 0(x5)             # print a0 (65 -> proves the original re-executed)
    li16 x6, 68                # 'D' (done)
    sw   x6, 0(x5)
    ecall 0x3FF               # halt
dbg_isr:
    push x4
    push x5
    li16 x4, 0xC008            # UART DR
    li16 x5, 66                # 'B' = breakpoint hit
    sw   x5, 0(x4)
    sw   x6, 0(x4)             # dump debuggee a0 (=64) over the UART
    li16 x5, 0xA000            # restore the original instruction at the breakpoint
    lw   x5, 0(x5)
    li16 x4, 0xA002
    lw   x4, 0(x4)
    sw   x5, 0(x4)
    pop  x5
    pop  x4
    reti                       # EPC = bp addr -> re-execute the restored original
"""

def main():
    sp = soc_run.SCRATCH
    open(sp + "/dbg.s", "w").write(ASM)
    r = subprocess.run([sys.executable, soc_run.ASM, sp + "/dbg.s", "-o", sp + "/dbg.bin"],
                       capture_output=True, text=True)
    if "successfully" not in r.stdout:
        print("ASM FAIL:", r.stdout[-300:], r.stderr[:200]); sys.exit(1)
    image = open(sp + "/dbg.bin", "rb").read()
    open(sp + "/zx16_soc.memh", "w").write(soc_run.pack_memh(image))
    soc_run.build_sim()
    rr = subprocess.run(["vvp", soc_run.VVP, "+memh=" + sp + "/zx16_soc.memh"],
                        capture_output=True, text=True, timeout=120)
    bs = [int(m) for m in re.findall(r"UART (\d+)", rr.stdout)]
    halted = "HALT" in rr.stdout
    ok = halted and bs == [66, 64, 65, 68]
    print(f"  UART bytes={bs} halted={halted} timeout={'TIMEOUT' in rr.stdout}")
    print(f"  (expected [66='B', 64=a0@bp, 65=a0 after continue, 68='D'])")
    print(("PASS" if ok else "FAIL") +
          "  on-chip EBREAK breakpoint: plant -> trap -> dump-over-UART -> restore -> continue")
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
