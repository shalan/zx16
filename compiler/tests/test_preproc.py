#!/usr/bin/env python3
"""Tests for the zcc preprocessor: #include (recursive, include-once) and
object-like #define (incl. nested macros, use as array size / loop bound, and
rejection of function-like macros / missing includes)."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
COMPILER = os.path.dirname(HERE)
ROOT = os.path.dirname(COMPILER)
sys.path.insert(0, COMPILER)
sys.path.insert(0, os.path.join(ROOT, "simulator"))
import importlib, codegen_patterns, zcc, codegen   # noqa: E402
for m in (codegen_patterns, zcc, codegen): importlib.reload(m)
import zx16sim as Z                                  # noqa: E402
LIBDIR = os.path.join(COMPILER, "lib")

npass = ntot = 0
def check(label, cond):
    global npass, ntot
    ntot += 1; npass += bool(cond)
    print(("PASS " if cond else "FAIL ") + label)

# 1) #include u32.c TWICE (include-once) + #define as array size and loop bound
src = '''
#include "u32.c"
#include "u32.c"
#define RUNS 3
#define N 8
int arr[N];
int main(void){
    struct u32 a; struct u32 b; int i; int s;
    set32(&a, 1, 0); set32(&b, 0, 1);          // a = 0x00010000
    i = 0; while (i < RUNS){ add32(&a, &a, &b); i = i + 1; }
    putint(a.hi); putint(a.lo);                // 1, 3
    i = 0; s = 0; while (i < N){ arr[i] = i; s = s + arr[i]; i = i + 1; }
    putint(s);                                  // 0+...+7 = 28
    return 0;
}
'''
out, _ = Z.assemble_and_run(codegen.compile_src(src, base_dir=LIBDIR))
check("#include u32 x2 (include-once) + #define array/loop -> [1,3,28]",
      [v for k, v in out] == [1, 3, 28])

# 2) nested object-like macro (SIZE -> WIDTH -> 4)
src2 = ('#define WIDTH 4\n#define SIZE WIDTH\n'
        'int main(void){ int a[SIZE]; int i; int s; i=0; s=0;'
        ' while(i<SIZE){ a[i]=i*i; s=s+a[i]; i=i+1; } putint(s); return 0; }')
out, _ = Z.assemble_and_run(codegen.compile_src(src2))
check("nested #define (SIZE->WIDTH->4): sum i*i, i<4 = 14", [v for k, v in out] == [14])

# 3) function-like #define is rejected
try:
    codegen.compile_src('#define MAX(a,b) a\nint main(void){ return 0; }')
    check("function-like #define rejected", False)
except zcc.PreprocError:
    check("function-like #define rejected", True)

# 4) missing #include errors clearly
try:
    codegen.compile_src('#include "does_not_exist.c"\nint main(void){ return 0; }')
    check("missing #include errors", False)
except zcc.PreprocError:
    check("missing #include errors", True)

print(f"\n{npass}/{ntot} preprocessor tests passed")
sys.exit(0 if npass == ntot else 1)
