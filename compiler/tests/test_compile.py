#!/usr/bin/env python3
"""End-to-end tests for zcc: compile ZC source, run on ZX16 sim, check output."""
import os, sys
_HERE = os.path.dirname(os.path.abspath(__file__))
_COMPILER = os.path.dirname(_HERE)
sys.path.insert(0, _COMPILER)
sys.path.insert(0, os.path.join(os.path.dirname(_COMPILER), "simulator"))

import importlib
import codegen_patterns, zcc, codegen
importlib.reload(codegen_patterns); importlib.reload(zcc); importlib.reload(codegen)
import zx16sim as Z

def run(src):
    asm=codegen.compile_src(src)
    out,sim=Z.assemble_and_run(asm)
    return [v for (k,v) in out]

CASES=[]
def case(name, src, expect):
    CASES.append((name,src,expect))

case("arith", '''
int main(void){ putint( (2+3)*(10-6) ); return 0; }
''', [20])

case("recursion_fact", '''
int fact(int n){ if (n < 2) return 1; return n * fact(n-1); }
int main(void){ putint(fact(5)); return 0; }
''', [120])

case("while_sum", '''
int main(void){
  int i; int s;
  i = 1; s = 0;
  while (i <= 10){ s = s + i; i = i + 1; }
  putint(s); return 0;
}
''', [55])

case("ifelse", '''
int main(void){
  int a; a = 8;
  if (a > 5) putint(1); else putint(0);
  return 0;
}
''', [1])

case("break_continue", '''
int main(void){
  int i; int c;
  i = 0; c = 0;
  while (i < 10){
    i = i + 1;
    if (i == 7) break;
    if (i == 3) continue;
    c = c + 1;
  }
  putint(c); return 0;   // 1,2,4,5,6 -> 5
}
''', [5])

case("bitwise", '''
int main(void){
  putint( (1 << 3) | 1 );      // 9
  putint( 0xFF & 0x0F );       // 15
  putint( 0xF0 ^ 0xFF );       // 15
  return 0;
}
''', [9,15,15])

case("globals", '''
int counter;
int bump(void){ counter = counter + 1; return counter; }
int main(void){
  counter = 40;
  bump(); bump();
  putint(counter); return 0;
}
''', [42])

case("pointers", '''
int main(void){
  int x; int *p;
  x = 5;
  p = &x;
  *p = *p + 37;
  putint(x); return 0;
}
''', [42])

case("array", '''
int main(void){
  int a[5];
  int i;
  i = 0;
  while (i < 5){ a[i] = i * i; i = i + 1; }
  putint(a[0] + a[1] + a[2] + a[3] + a[4]);  // 0+1+4+9+16=30
  return 0;
}
''', [30])

case("struct", '''
struct Point { int x; int y; };
int main(void){
  struct Point pt;
  struct Point *p;
  p = &pt;
  p->x = 10;
  p->y = 32;
  putint(p->x + p->y); return 0;
}
''', [42])

case("unsigned_cmp", '''
int main(void){
  unsigned a; unsigned b;
  a = 0xF000; b = 0x0010;
  if (a > b) putint(1); else putint(0);  // unsigned: 1
  return 0;
}
''', [1])

case("char_string", '''
int main(void){
  char *s;
  s = "AB";
  putchar(*s);          // 'A' = 65
  putchar(*(s+1));      // 'B' = 66
  return 0;
}
''', [65,66])

if __name__=='__main__':
    passed=0
    for (name,src,expect) in CASES:
        try:
            got=run(src)
            if got==expect:
                print(f"PASS {name}"); passed+=1
            else:
                print(f"FAIL {name}: got {got} expected {expect}")
        except Exception as ex:
            print(f"ERROR {name}: {type(ex).__name__}: {ex}")
    print(f"\n{passed}/{len(CASES)} end-to-end programs compiled and ran correctly")
