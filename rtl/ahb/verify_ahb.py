#!/usr/bin/env python3
"""Differential verification of the AHB-Lite 2-stage ZX16 core against the Python
golden simulator. Runs every ZC example through the AHB SoC (iverilog) and zx16sim.py
and compares console output -- at zero wait states and with AHB wait states injected
(proving the master's HREADY/stall handling).

Usage:  python3 rtl/ahb/verify_ahb.py [ws ...]      (default: 0 2)
"""
import sys, os, glob, subprocess, re, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))     # rtl/ahb -> rtl -> root
for d in ('compiler', 'simulator', 'assembler'):
    sys.path.insert(0, os.path.join(ROOT, d))
import codegen          # noqa: E402
import zx16sim as Z     # noqa: E402
import zx16asm          # noqa: E402

EXAMPLES = os.path.join(ROOT, 'compiler', 'examples')
SRCS = [os.path.join(ROOT, 'rtl', 'zx16_alu.v'),
        os.path.join(HERE, 'zx16_core_ahb.v'),
        os.path.join(HERE, 'ahb_sram.v'),
        os.path.join(HERE, 'tb_zx16_ahb.v')]


def build():
    vvp = os.path.join(tempfile.gettempdir(), 'zx16ahb_verify.vvp')
    subprocess.run(['iverilog', '-o', vvp] + SRCS, check=True)
    return vvp


def sim_output(asm, pre=None):
    out, _ = Z.assemble_and_run(asm, pre_run=pre)
    return [('INT' if k == 'int' else 'CHR', v) for k, v in out]


def mem_image(asm):
    a = zx16asm.ZX16Assembler()
    if not a.assemble(asm, '<v>'):
        raise RuntimeError('assemble failed')
    lines = [L for L in a.get_memory_file_output().splitlines() if not L.startswith('#')]
    fd, p = tempfile.mkstemp(suffix='.mem')
    with os.fdopen(fd, 'w') as f:
        f.write("\n".join(lines) + "\n")
    return p


def rtl_output(vvp, mem, ws=0):
    args = ['vvp', vvp, '+mem=' + mem] + (['+ws=%d' % ws] if ws else [])
    r = subprocess.run(args, capture_output=True, text=True, timeout=900)
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


def setup_poll(sim):
    sim.mmio_read_script[0xF020] = [0, 0, 1]
    sim.mmio_regs[0xF021] = 99


def main():
    ws_list = [int(x) for x in sys.argv[1:]] or [0, 2]
    vvp = build()
    progs = sorted(glob.glob(os.path.join(EXAMPLES, '*.c')))
    overall = True
    for ws in ws_list:
        print(f"\n=== wait states = {ws} ===")
        npass = 0
        for c in progs:
            name = os.path.basename(c)
            asm = codegen.compile_src(open(c).read())
            pre = setup_poll if name.startswith('02') else None
            want = sim_output(asm, pre)
            got = rtl_output(vvp, mem_image(asm), ws)
            ok = (got == want); npass += ok
            print(f"  {'PASS' if ok else 'FAIL'}  {name:<20} sim={len(want)} rtl={len(got)}")
            if not ok:
                print(f"        sim={want}")
                print(f"        rtl={got}")
        overall &= (npass == len(progs))
        print(f"  {npass}/{len(progs)} match (ws={ws})")
    sys.exit(0 if overall else 1)


if __name__ == '__main__':
    main()
