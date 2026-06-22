#!/usr/bin/env python3
"""Build + run a ZX16 SoC firmware image on the RTL SoC (ZX16 core + nc_amba fabric
+ nc_uart + nc_tmr) and return the bytes the real UART transmitted.

Flow: compile .c (INTRINSIC_IO off, stack below the peripheral window) -> assemble to
a 64 KB image -> pack little-endian 32-bit words -> iverilog/vvp with +memh -> parse
the testbench's "UART <n>" lines.

Usage: python3 rtl/soc/soc_run.py firmware.c
"""
import os, sys, subprocess, tempfile, re, glob
HERE = os.path.dirname(os.path.abspath(__file__))
RTLSOC = HERE
RTL = os.path.dirname(HERE)
ROOT = os.path.dirname(RTL)
sys.path.insert(0, os.path.join(ROOT, "compiler"))
sys.path.insert(0, os.path.join(ROOT, "simulator"))
import codegen, codegen_patterns                              # noqa: E402
LIB = os.path.join(ROOT, "compiler", "lib")
ASM = os.path.join(ROOT, "assembler", "zx16asm.py")
SCRATCH = os.environ.get("ZX16_SCRATCH", tempfile.gettempdir())
VVP = os.path.join(SCRATCH, "zx16_soc.vvp")

RTL_FILES = ([os.path.join(RTL, "zx16_alu.v"),
              os.path.join(RTL, "ahb", "zx16_core_ahb.v"),
              os.path.join(RTLSOC, "zx16_ahb16to32.v"),
              os.path.join(RTLSOC, "zx16_ahb32_sram.v"),
              os.path.join(RTLSOC, "zx16_soc.v"),
              os.path.join(RTLSOC, "tb_zx16_soc.v")]
             + sorted(glob.glob(os.path.join(RTLSOC, "vendor", "*.v"))))

def build_sim():
    r = subprocess.run(["iverilog", "-g2012", "-s", "tb_zx16_soc", "-o", VVP] + RTL_FILES,
                       capture_output=True, text=True)
    if r.returncode != 0:
        raise RuntimeError("iverilog failed:\n" + r.stdout + r.stderr)

def compile_firmware(cfile):
    """Compile a SoC firmware .c to a 64 KB byte image (UART I/O, SP below 0xC000)."""
    save_io, save_sp = codegen.INTRINSIC_IO, codegen_patterns.STACK_TOP
    codegen.INTRINSIC_IO = False
    codegen_patterns.STACK_TOP = 0xC000
    try:
        asm = codegen.compile_src(open(cfile).read(), base_dir=LIB)
    finally:
        codegen.INTRINSIC_IO, codegen_patterns.STACK_TOP = save_io, save_sp
    with tempfile.NamedTemporaryFile("w", suffix=".s", delete=False) as f:
        f.write(asm); src = f.name
    out = src + ".bin"
    r = subprocess.run([sys.executable, ASM, src, "-o", out], capture_output=True, text=True)
    if "successfully" not in r.stdout:
        raise RuntimeError("assembly failed:\n" + r.stdout + r.stderr)
    return open(out, "rb").read()

def pack_memh(b):
    if len(b) % 4:
        b = b + b"\x00" * (4 - len(b) % 4)
    return "".join(f"{b[i] | (b[i+1]<<8) | (b[i+2]<<16) | (b[i+3]<<24):08x}\n"
                   for i in range(0, len(b), 4))

def run(cfile, timeout=120, rx=None):
    """Run firmware; optionally inject `rx` (str or iterable of byte values) on the
    UART RX line (for the debug monitor). Returns captured UART TX + halt/timeout."""
    image = compile_firmware(cfile)
    memh = os.path.join(SCRATCH, "zx16_soc.memh")
    open(memh, "w").write(pack_memh(image))
    args = ["vvp", VVP, "+memh=" + memh]
    if rx is not None:
        data = rx.encode() if isinstance(rx, str) else bytes(rx)
        rxf = os.path.join(SCRATCH, "zx16_soc.rx")
        open(rxf, "w").write("".join(f"{b}\n" for b in data))
        args.append("+rxfile=" + rxf)
    if not os.path.exists(VVP):
        build_sim()
    r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    out_bytes, halted, timed = [], False, False
    for line in r.stdout.splitlines():
        m = re.match(r"UART (\d+)", line)
        if m: out_bytes.append(int(m.group(1))); continue
        if line.strip() == "HALT": halted = True
        if line.strip() == "TIMEOUT": timed = True
    return {"bytes": out_bytes, "text": "".join(chr(c) for c in out_bytes),
            "halted": halted, "timeout": timed, "raw": r.stdout}

if __name__ == "__main__":
    build_sim()
    for c in sys.argv[1:]:
        res = run(c)
        print(f"{os.path.basename(c)}: halted={res['halted']} timeout={res['timeout']}")
        print("  UART bytes:", res["bytes"])
        print("  UART text :", repr(res["text"]))
