#!/usr/bin/env python3
"""End-to-end hardware-interrupt test on the ZX16 SoC: the nc_tmr periodic timer
raises its IRQ -> SoC interrupt controller -> AHB core takes it (IE=1) -> vector 2
-> asm ISR clears the timer UIF and bumps a counter -> RETI. After 3 timer interrupts
the main loop prints 'K' and halts. If interrupts don't work the loop spins -> TIMEOUT.

(RTL-only: the golden sim doesn't model the nc peripherals, so no differential here;
the AHB core's trap entry/RETI are also differentially checked at the ISA level.)"""
import os, sys, subprocess, re
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import soc_run                                    # noqa: E402

ASM = r"""
.org 0x0004
    j tmr_isr                 # vector 2 (timer) at 0x0004
.org 0x0020
start:
    li16 x2, 0xBFFE           # SP, below the 0xC000 peripheral window
    # UART: BRR=0, CR=EN|TXEN
    li16 x5, 0xC100
    li16 x6, 0
    sw   x6, 0(x5)
    li16 x5, 0xC000
    li16 x6, 0x301
    sw   x6, 0(x5)
    # timer: PSC=0, ARR=99, IM=update, CR=CEN
    li16 x5, 0xD104
    li16 x6, 0
    sw   x6, 0(x5)
    li16 x5, 0xD108
    li16 x6, 99
    sw   x6, 0(x5)
    li16 x5, 0xD020           # IM: unmask update interrupt -> irq_o
    li16 x6, 1
    sw   x6, 0(x5)
    li16 x5, 0xD000           # CR: CEN
    li16 x6, 1
    sw   x6, 0(x5)
    # count = 0 at 0xA000
    li16 x5, 0xA000
    li16 x6, 0
    sw   x6, 0(x5)
    ei                        # enable interrupts
wait_loop:
    li16 x5, 0xA000
    lw   x6, 0(x5)
    li16 x4, 3
    blt  x6, x4, wait_loop    # spin until 3 timer interrupts have fired
    li16 x5, 0xC008           # UART DR = 'K'
    li16 x6, 75
    sw   x6, 0(x5)
    ecall 0x3FF               # halt
tmr_isr:
    push x6
    push x5
    li16 x5, 0xD02C           # clear timer UIF (ICR bit0)
    li16 x6, 1
    sw   x6, 0(x5)
    li16 x5, 0xA000           # count++
    lw   x6, 0(x5)
    addi x6, 1
    sw   x6, 0(x5)
    pop  x5
    pop  x6
    reti
"""

def main():
    sp = soc_run.SCRATCH
    open(sp + "/irq.s", "w").write(ASM)
    r = subprocess.run([sys.executable, soc_run.ASM, sp + "/irq.s", "-o", sp + "/irq.bin"],
                       capture_output=True, text=True)
    if "successfully" not in r.stdout:
        print("ASM FAIL:", r.stdout[-300:], r.stderr[:200]); sys.exit(1)
    image = open(sp + "/irq.bin", "rb").read()
    open(sp + "/zx16_soc.memh", "w").write(soc_run.pack_memh(image))
    soc_run.build_sim()
    rr = subprocess.run(["vvp", soc_run.VVP, "+memh=" + sp + "/zx16_soc.memh"],
                        capture_output=True, text=True, timeout=120)
    bs = [int(m) for m in re.findall(r"UART (\d+)", rr.stdout)]
    halted = "HALT" in rr.stdout
    ok = halted and (75 in bs)
    print(f"  UART bytes={bs} halted={halted} timeout={'TIMEOUT' in rr.stdout}")
    print(("PASS" if ok else "FAIL") +
          "  SoC hardware timer interrupt -> ISR -> RETI (3 IRQs, then 'K')")
    sys.exit(0 if ok else 1)

if __name__ == "__main__":
    main()
