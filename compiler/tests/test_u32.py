#!/usr/bin/env python3
"""Verify compiler/lib/u32.c (32-bit integer library) against Python references.

Builds a ZC program = u32.c + a generated main that runs each op on edge-case
vectors and prints the results, compiles+runs it on the ZX16 sim, and checks every
output against the corresponding 32-bit Python computation.
"""
import os, sys
_HERE = os.path.dirname(os.path.abspath(__file__))
_COMPILER = os.path.dirname(_HERE)
_ROOT = os.path.dirname(_COMPILER)
sys.path.insert(0, _COMPILER)
sys.path.insert(0, os.path.join(_ROOT, "simulator"))
import importlib, codegen_patterns, zcc, codegen          # noqa: E402
for m in (codegen_patterns, zcc, codegen): importlib.reload(m)
import zx16sim as Z                                        # noqa: E402

LIB = os.path.join(_COMPILER, "lib", "u32.c")
M = 0xFFFFFFFF

# ---- 32-bit references ----
def s16(x): return x - 65536 if x >= 32768 else x
def hl(v):  return ((v >> 16) & 0xFFFF, v & 0xFFFF)
def sgn(x): return x - 0x100000000 if x & 0x80000000 else x

R_BIN = {
    'add32': lambda a, b: (a + b) & M,
    'sub32': lambda a, b: (a - b) & M,
    'and32': lambda a, b: a & b,
    'or32':  lambda a, b: a | b,
    'xor32': lambda a, b: a ^ b,
    'mul32': lambda a, b: (a * b) & M,
}
R_UN = {'neg32': lambda a: (-a) & M, 'not32': lambda a: (~a) & M}
def r_shl(a, n): return (a << (n & 31)) & M
def r_shr(a, n): return a >> (n & 31)
def r_sar(a, n): return (sgn(a) >> (n & 31)) & M
def r_rol(a, c): c &= 31; return a if c == 0 else ((a << c) | (a >> (32 - c))) & M
def r_ror(a, c): c &= 31; return a if c == 0 else ((a >> c) | (a << (32 - c))) & M
R_SH = {'shl32': r_shl, 'shr32': r_shr, 'sar32': r_sar, 'rol32': r_rol, 'ror32': r_ror}
R_CMP = {'ult32': lambda a, b: 1 if a < b else 0,
         'slt32': lambda a, b: 1 if sgn(a) < sgn(b) else 0,
         'eq32':  lambda a, b: 1 if a == b else 0}

stmts, tests = [], []
def setv(var, v): h, l = hl(v); return f"set32(&{var},0x{h:04X},0x{l:04X});"
def t_bin(op, a, b):
    stmts.append(f"  {setv('a',a)} {setv('b',b)} {op}(&r,&a,&b); putint(r.hi); putint(r.lo);")
    h, l = hl(R_BIN[op](a, b)); tests.append((f"{op}({a:#010x},{b:#010x})", [s16(h), s16(l)]))
def t_un(op, a):
    stmts.append(f"  {setv('a',a)} {op}(&r,&a); putint(r.hi); putint(r.lo);")
    h, l = hl(R_UN[op](a)); tests.append((f"{op}({a:#010x})", [s16(h), s16(l)]))
def t_sh(op, a, n):
    stmts.append(f"  {setv('a',a)} {op}(&r,&a,{n}); putint(r.hi); putint(r.lo);")
    h, l = hl(R_SH[op](a, n)); tests.append((f"{op}({a:#010x},{n})", [s16(h), s16(l)]))
def t_cmp(op, a, b):
    stmts.append(f"  {setv('a',a)} {setv('b',b)} putint({op}(&a,&b));")
    tests.append((f"{op}({a:#010x},{b:#010x})", [R_CMP[op](a, b)]))
def t_div(a, b):
    stmts.append(f"  {setv('a',a)} {setv('b',b)} udivmod32(&q,&m,&a,&b); "
                 f"putint(q.hi); putint(q.lo); putint(m.hi); putint(m.lo);")
    qv = M if b == 0 else a // b
    rv = a if b == 0 else a % b
    qh, ql = hl(qv); rh, rl = hl(rv)
    tests.append((f"udivmod32({a:#010x},{b:#010x})", [s16(qh), s16(ql), s16(rh), s16(rl)]))

# ---- vectors ----
for a, b in [(0xFFFFFFFF, 1), (0x0000FFFF, 1), (0x12345678, 0x9ABCDEF0), (0, 0), (0x7FFFFFFF, 1)]: t_bin('add32', a, b)
for a, b in [(0, 1), (0x00010000, 1), (0x12345678, 0x00005678), (5, 5), (0x80000000, 1)]: t_bin('sub32', a, b)
for a in [0, 1, 0xFFFFFFFF, 0x80000000, 0x12345678]: t_un('neg32', a)
for a in [0, 0xFFFFFFFF, 0xF0F0F0F0, 0x12345678]: t_un('not32', a)
for op in ('and32', 'or32', 'xor32'):
    for a, b in [(0xF0F0F0F0, 0x0FF00FF0), (0xFFFFFFFF, 0x12345678), (0, 0x12345678)]: t_bin(op, a, b)
for n in [0, 1, 15, 16, 31, 4, 20]: t_sh('shl32', 0x12345678, n)
t_sh('shl32', 1, 31); t_sh('shl32', 0xFFFFFFFF, 8)
for n in [0, 1, 15, 16, 31, 4, 20]: t_sh('shr32', 0x80000000, n)
t_sh('shr32', 0x12345678, 20)
for n in [1, 16, 31, 4, 0]: t_sh('sar32', 0x80000000, n)
t_sh('sar32', 0xFFFF0000, 4); t_sh('sar32', 0x7FFFFFFF, 4)
for n in [0, 4, 16, 20, 31]: t_sh('rol32', 0x12345678, n)
for n in [0, 4, 16, 20, 31]: t_sh('ror32', 0x12345678, n)
for a, b in [(1, 2), (2, 1), (0xFFFFFFFF, 1), (0x80000000, 0x7FFFFFFF), (5, 5)]: t_cmp('ult32', a, b)
for a, b in [(1, 2), (0xFFFFFFFF, 1), (0x80000000, 1), (0x7FFFFFFF, 0x80000000), (5, 5)]: t_cmp('slt32', a, b)
for a, b in [(5, 5), (5, 6), (0x12340000, 0x12340000), (0x12340000, 0x12340001)]: t_cmp('eq32', a, b)
for a, b in [(0x12345678, 3), (0x10000, 0x10000), (0xFFFF, 0x10001), (123456, 654321), (0xFFFFFFFF, 2), (7, 0)]: t_bin('mul32', a, b)
for a, b in [(100, 7), (0xFFFFFFFF, 0x10000), (0x12345678, 0x1000), (42, 1), (5, 10), (0xABCDEF12, 0x1234), (1000000, 3)]: t_div(a, b)

main = ("int main(void){\n  struct u32 a; struct u32 b; struct u32 r; struct u32 q; struct u32 m;\n"
        + "\n".join(stmts) + "\n  return 0;\n}\n")
src = open(LIB).read() + "\n" + main

asm = codegen.compile_src(src)
out, _ = Z.assemble_and_run(asm)
vals = [v for _, v in out]

idx = npass = 0
for label, exp in tests:
    got = vals[idx:idx + len(exp)]; idx += len(exp)
    if got == exp:
        npass += 1
    else:
        print(f"FAIL {label}: got {got} exp {exp}")
extra = "" if idx == len(vals) else f"  (!! output count {len(vals)} != expected {idx})"
print(f"\n{npass}/{len(tests)} u32 ops match Python references{extra}")
sys.exit(0 if npass == len(tests) and idx == len(vals) else 1)
