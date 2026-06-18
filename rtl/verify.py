#!/usr/bin/env python3
"""Differential verification for the ZX16 single-cycle RTL core.

For each ZC example: compile it, run it on (a) the Verilog core via iverilog/vvp
and (b) the Python golden simulator, then compare the console output (the ECALL
print_int / print_char sequence). A match on every program -- including MD5, FFT,
and TEA -- is strong evidence the RTL implements the ISA correctly.

Run:  python3 rtl/verify.py
"""
import sys, os, glob, subprocess, re, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
for d in ('compiler', 'simulator', 'assembler'):
    sys.path.insert(0, os.path.join(ROOT, d))
import codegen          # noqa: E402
import zx16sim as Z     # noqa: E402
import zx16asm          # noqa: E402

EXAMPLES = os.path.join(ROOT, 'compiler', 'examples')
RTL_SRCS = ['zx16_alu.v', 'zx16_mem.v', 'zx16_core.v', 'zx16_top.v', 'tb_zx16.v']


def build_rtl():
    vvp = os.path.join(tempfile.gettempdir(), 'zx16_verify.vvp')
    srcs = [os.path.join(HERE, f) for f in RTL_SRCS]
    subprocess.run(['iverilog', '-o', vvp] + srcs, check=True)
    return vvp


def sim_output(asm, pre=None):
    out, _ = Z.assemble_and_run(asm, pre_run=pre)
    return [('INT' if k == 'int' else 'CHR', v) for k, v in out]


def mem_image(asm):
    a = zx16asm.ZX16Assembler()
    if not a.assemble(asm, '<verify>'):
        raise RuntimeError('assembly failed')
    lines = [L for L in a.get_memory_file_output().splitlines() if not L.startswith('#')]
    fd, path = tempfile.mkstemp(suffix='.mem')
    with os.fdopen(fd, 'w') as f:
        f.write("\n".join(lines) + "\n")
    return path


def rtl_output(vvp, memfile):
    r = subprocess.run(['vvp', vvp, '+mem=' + memfile],
                       capture_output=True, text=True, timeout=300)
    res = []
    for line in r.stdout.splitlines():
        m = re.match(r'OUT INT (-?\d+)', line)
        if m:
            res.append(('INT', int(m.group(1)))); continue
        m = re.match(r'OUT CHR (\d+)', line)
        if m:
            res.append(('CHR', int(m.group(1)))); continue
        if 'OUT TIMEOUT' in line:
            res.append(('TIMEOUT', 0))
    return res


def setup_poll(sim):                       # mirrors test_embedded's 02 setup
    sim.mmio_read_script[0xF020] = [0, 0, 1]
    sim.mmio_regs[0xF021] = 99


def main():
    vvp = build_rtl()
    progs = sorted(glob.glob(os.path.join(EXAMPLES, '*.c')))
    npass = 0
    for c in progs:
        name = os.path.basename(c)
        asm = codegen.compile_src(open(c).read())
        pre = setup_poll if name.startswith('02') else None
        want = sim_output(asm, pre)
        got = rtl_output(vvp, mem_image(asm))
        ok = (got == want)
        npass += ok
        print(f"{'PASS' if ok else 'FAIL'}  {name:<20} sim={len(want)} vals, rtl={len(got)} vals")
        if not ok:
            print(f"      sim: {want}")
            print(f"      rtl: {got}")
    print(f"\n{npass}/{len(progs)} examples: RTL output matches the golden simulator")
    sys.exit(0 if npass == len(progs) else 1)


if __name__ == '__main__':
    main()
