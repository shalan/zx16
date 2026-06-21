#!/usr/bin/env python3
"""Exhaustive check of ZC integer divide/modulo codegen + runtime against C
semantics, for BOTH signed and unsigned operands across the full 16-bit range.

History: the original __div/__mod used a signed compare in a repeated-subtraction
loop, so they were correct only for operands in [0,32767]. Unsigned values >32767
and signed negatives were both wrong (65535/10 -> 0, -7/2 -> 0). The runtime now
uses restoring binary long division (__udivmod) with signed wrappers (__div/__mod,
truncation toward zero, remainder takes the dividend's sign)."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
COMPILER = os.path.dirname(HERE); ROOT = os.path.dirname(COMPILER)
sys.path.insert(0, COMPILER); sys.path.insert(0, os.path.join(ROOT, "simulator"))
import importlib, codegen_patterns, zcc, codegen      # noqa: E402
for m in (codegen_patterns, zcc, codegen): importlib.reload(m)
import zx16sim as Z                                    # noqa: E402

def s16(x): x &= 0xFFFF; return x - 0x10000 if x & 0x8000 else x
def u16(x): return x & 0xFFFF

def cdiv(a, b):                 # C truncation toward zero
    q = abs(a) // abs(b)
    return -q if (a < 0) ^ (b < 0) else q
def cmod(a, b):                 # remainder has sign of dividend: a - (a/b)*b
    return a - cdiv(a, b) * b

AV = [0,1,-1,2,-2,3,-3,5,-5,7,-7,8,-8,10,-10,16,-16,100,-100,127,-128,255,
      -256,1000,-1000,12345,-12345,30000,-30000,32767,-32768]
BV = [1,-1,2,-2,3,-3,7,-7,10,-10,16,-16,100,-100,1000,-1000,32767,-32768]
UV = [0,1,2,3,10,16,17,255,256,1000,10000,12345,32767,32768,40000,50000,
      54321,60000,65534,65535]
UD = [1,2,3,7,10,16,255,256,1000,10000,32768,40000,60000,65535]

def gen(decl, avals, bvals):
    na, nb = len(avals), len(bvals)
    lines = [f"{decl} av[{na}]; {decl} bv[{nb}];", "int main(void){ int i; int j;"]
    for i, v in enumerate(avals): lines.append(f" av[{i}]={v};")
    for j, v in enumerate(bvals): lines.append(f" bv[{j}]={v};")
    lines.append(" i=0; while(i<%d){ j=0; while(j<%d){" % (na, nb))
    lines.append("   putint(av[i]/bv[j]); putint(av[i]%bv[j]); j=j+1; } i=i+1; }")
    lines.append(" return 0; }")
    return "\n".join(lines)

def run(src):
    out, _ = Z.assemble_and_run(codegen.compile_src(src))
    return [v for k, v in out]

npass = nfail = 0
def section(name, decl, avals, bvals, refdiv, refmod):
    global npass, nfail
    got = run(gen(decl, avals, bvals)); k = 0; fails = []
    for a in avals:
        for b in bvals:
            eq, em = s16(refdiv(a, b)), s16(refmod(a, b))
            gq, gm = got[k], got[k + 1]; k += 2
            if gq == eq and gm == em: npass += 1
            else:
                nfail += 1
                if len(fails) < 6: fails.append(f"{a}/{b}: q {gq}!={eq} or r {gm}!={em}")
    print(f"  {name:<26} {('PASS' if not fails else 'FAIL')}  ({len(avals)*len(bvals)} pairs)")
    for f in fails: print("      " + f)

print("divide/modulo correctness:")
section("signed",   "int",      AV, BV, cdiv, cmod)
section("unsigned", "unsigned", UV, UD, lambda a, b: u16(a) // u16(b),
        lambda a, b: u16(a) % u16(b))

# spot cases that used to fail outright
spot = run("int main(void){ unsigned u; int a; u=65535; a=-7;"
           " putint(u/10); putint(u%10); putint(a/2); putint(a%2);"
           " putint(7/a); putint(7%a); return 0; }")
exp = [6553, 5, -3, -1, -1, 0]   # ...; 7/-7=-1; 7%-7 = 7-(-1)(-7) = 0
ok = spot == exp
npass += ok; nfail += (not ok)
print(f"  {'regression spot-cases':<26} {'PASS' if ok else 'FAIL'}   got={spot} exp={exp}")

print(f"\n{npass}/{npass+nfail} divide/modulo cases correct")
sys.exit(0 if nfail == 0 else 1)
