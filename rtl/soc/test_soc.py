#!/usr/bin/env python3
"""SoC integration test: build the ZX16 + nc_amba-fabric + nc_uart + nc_tmr SoC and
run firmware whose output goes through the REAL nc_uart (decoded off the serial line
by the testbench). Requires iverilog + vvp.

  - hello.c : stdio_si over the UART (puts/putint/puthex)
  - tmr.c   : nc_tmr periodic overflow polling

Run: python3 rtl/soc/test_soc.py"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import soc_run                                              # noqa: E402
FW = os.path.join(HERE, "fw")

def asm_bytes(src, org=0x20):
    """Assemble raw asm; return the emitted bytes (for position-independent payloads)."""
    import subprocess, tempfile
    f = tempfile.NamedTemporaryFile("w", suffix=".s", delete=False); f.write(src); f.close()
    out = f.name + ".bin"
    subprocess.run([sys.executable, soc_run.ASM, f.name, "-o", out], capture_output=True, text=True)
    img = open(out, "rb").read(); end = org
    for i in range(org, len(img)):
        if img[i]: end = i + 1
    return img[org:end]

npass = ntot = 0
def check(label, cond, detail=""):
    global npass, ntot
    ntot += 1; npass += bool(cond)
    print(("PASS " if cond else "FAIL ") + label + (("  " + detail) if not cond else ""))

soc_run.build_sim()

r = soc_run.run(os.path.join(FW, "hello.c"))
check("hello: UART stdio_si output via nc_uart",
      r["halted"] and not r["timeout"] and r["text"] == "Hello, ZX16 SoC!\n1234\nbeef\n",
      repr(r["text"]))

r = soc_run.run(os.path.join(FW, "tmr.c"))
check("tmr: nc_tmr periodic overflows",
      r["halted"] and not r["timeout"] and r["text"] == "timer: 5 overflows\n",
      repr(r["text"]))

# debug monitor driven over the real UART (RX commands in, TX responses out)
r = soc_run.run(os.path.join(FW, "monitor.c"),
                rx="w A000 ABCD\nr A000\nw A002 1234\nd A000 2\nq\n")
check("monitor: read/write/dump over UART",
      r["halted"] and not r["timeout"] and
      r["text"] == "ZX16MON\n>ok\n>abcd\n>ok\n>abcd 1234 \n>bye\n", repr(r["text"]))

r = soc_run.run(os.path.join(FW, "monitor.c"), rx="g 20\nq\n")
check("monitor: 'g' jump (restart -> banner twice)",
      r["halted"] and not r["timeout"] and r["text"] == "ZX16MON\n>ZX16MON\n>bye\n",
      repr(r["text"]))

# loader: write 4 raw bytes over UART, read them back as little-endian words
r = soc_run.run(os.path.join(FW, "monitor.c"),
                rx=b"L A000 4\n" + bytes([0xDE, 0xAD, 0xBE, 0xEF]) + b"d A000 2\nq\n")
check("monitor: load bytes + read back",
      r["halted"] and r["text"] == "ZX16MON\n>ok\n>adde efbe \n>bye\n", repr(r["text"]))

# loader: load a position-independent payload (print 'K', halt) and execute it
pl = asm_bytes(".text\n li16 x6,75\n li16 x5,0xC008\n sw x6,0(x5)\n ecall 0x3FF\n")
r = soc_run.run(os.path.join(FW, "monitor.c"),
                rx=b"L 9000 " + format(len(pl), "X").encode() + b"\n" + pl + b"g 9000\n")
check("monitor: load + go (loaded code prints 'K')",
      r["halted"] and not r["timeout"] and 75 in r["bytes"], repr(r["text"]))

print(f"\n{npass}/{ntot} SoC tests passed")
sys.exit(0 if npass == ntot else 1)
