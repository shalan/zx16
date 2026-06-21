#!/usr/bin/env python3
"""Tests for the ZX16 ZC standard library (compiler/lib): string.c, ctype.c,
stdlib.c, stdio.c, and the umbrella libc.c. Each group compiles a program that
#includes the relevant lib (resolved from compiler/lib) and checks the runtime
output. Also verifies include-once + dead-function elimination via libc.c."""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
COMPILER = os.path.dirname(HERE); ROOT = os.path.dirname(COMPILER)
sys.path.insert(0, COMPILER); sys.path.insert(0, os.path.join(ROOT, "simulator"))
import importlib, codegen_patterns, zcc, codegen      # noqa: E402
for m in (codegen_patterns, zcc, codegen): importlib.reload(m)
import zx16sim as Z                                    # noqa: E402
LIB = os.path.join(COMPILER, "lib")

npass = ntot = 0
def check(label, cond):
    global npass, ntot
    ntot += 1; npass += bool(cond)
    print(("PASS " if cond else "FAIL ") + label)

def out(src):
    o, _ = Z.assemble_and_run(codegen.compile_src(src, base_dir=LIB))
    return o
def ints(src): return [v for k, v in out(src) if k == 'int']
def chars(src): return [v for k, v in out(src) if k == 'char']

# ---- string.c -----------------------------------------------------------------
S = '''#include "string.c"
char g1[16]; char g2[16];
int main(void){
  char *p;
  putint(strlen("hello"));
  strcpy(g1,"abc"); putint(strlen(g1)); putint(g1[0]); putint(g1[2]);
  strcat(g1,"de"); putint(strlen(g1)); putint(g1[4]);
  putint(strcmp("abc","abc")); putint(strcmp("abc","abd")); putint(strcmp("abd","abc"));
  putint(strncmp("abcXX","abcYY",3)); putint(memcmp("abc","abd",3));
  strncpy(g2,"hi",5); putint(g2[0]); putint(g2[1]); putint(g2[2]); putint(g2[4]);
  memset(g2,65,4); putint(g2[0]); putint(g2[3]);
  p="hello"; putint(strchr(p,'l') - p);
  return 0; }'''
check("string.c: len/cpy/cat/cmp/ncmp/memcmp/ncpy/memset/chr",
      ints(S) == [5, 3,97,99, 5,101, 0,-1,1, 0, -1, 104,105,0,0, 65,65, 2])

# ---- string.c: memmove overlap (both directions) ------------------------------
MM = '''#include "string.c"
char buf[8];
int main(void){ int i;
  i=0; while(i<6){ buf[i]='a'+i; i=i+1; } buf[6]=0;
  memmove(buf+2, buf, 4); i=0; while(i<6){ putint(buf[i]); i=i+1; }
  i=0; while(i<6){ buf[i]='a'+i; i=i+1; }
  memmove(buf, buf+2, 4); i=0; while(i<6){ putint(buf[i]); i=i+1; }
  return 0; }'''
check("string.c: memmove fwd+bwd overlap",
      ints(MM) == [97,98,97,98,99,100, 99,100,101,102,101,102])

# ---- ctype.c ------------------------------------------------------------------
C = '''#include "ctype.c"
int main(void){
  putint(isdigit('5')); putint(isdigit('a'));
  putint(isalpha('a')); putint(isalpha('Z')); putint(isalpha('0'));
  putint(isalnum('7')); putint(isalnum('x')); putint(isalnum(' '));
  putint(isspace(' ')); putint(isspace(9)); putint(isspace('x'));
  putint(isupper('A')); putint(islower('A'));
  putint(toupper('a')); putint(tolower('A')); putint(toupper('5'));
  return 0; }'''
check("ctype.c: isdigit/alpha/alnum/space/upper/lower/toupper/tolower",
      ints(C) == [1,0, 1,1,0, 1,1,0, 1,1,0, 1,0, 65,97,53])

# ---- stdlib.c: atoi -----------------------------------------------------------
A = '''#include "stdlib.c"
int main(void){
  putint(atoi("123")); putint(atoi("-45")); putint(atoi("  +7"));
  putint(atoi("12ab")); putint(atoi("")); putint(atoi("0"));
  return 0; }'''
check("stdlib.c: atoi (sign, leading ws, trailing junk)",
      ints(A) == [123, -45, 7, 12, 0, 0])

# ---- stdlib.c: itoa/utoa/itohex (printed strings, '\n'-delimited) --------------
C2 = '''#include "stdlib.c"
#include "stdio.c"
char b[8];
int main(void){
  putstr(itoa(0,b)); putchar(10); putstr(itoa(123,b)); putchar(10);
  putstr(itoa(-456,b)); putchar(10); putstr(itoa(-32768,b)); putchar(10);
  putstr(itoa(32767,b)); putchar(10);
  putstr(utoa(0,b)); putchar(10); putstr(utoa(65535,b)); putchar(10);
  putstr(utoa(40000,b)); putchar(10);
  putstr(itohex(0,b)); putchar(10); putstr(itohex(255,b)); putchar(10);
  putstr(itohex(16,b)); putchar(10); putstr(itohex(43981,b)); putchar(10);
  return 0; }'''
words = ''.join(chr(c) for c in chars(C2)).split('\n')[:-1]
check("stdlib.c: itoa/utoa/itohex (incl INT_MIN, 0xABCD)",
      words == ["0","123","-456","-32768","32767","0","65535","40000","0","ff","10","abcd"])

# ---- stdio.c ------------------------------------------------------------------
IO = '''#include "stdio.c"
int main(void){ putstr("hi"); putchar(10); puts("ok"); puthex(255); putchar(10); puthex(0);
  return 0; }'''
check("stdio.c: putstr / puts(+newline) / puthex",
      chars(IO) == [104,105,10, 111,107,10, 102,102,10, 48])

# ---- libc.c: include-once + dead-function elimination -------------------------
L = '''#include "libc.c"
#include "libc.c"
int main(void){ putint(strlen("test")); return 0; }'''
asm = codegen.compile_src(L, base_dir=LIB)
check("libc.c: include-once compiles + strlen works", ints(L) == [4])
check("libc.c: dead-fn elim keeps strlen, drops unused",
      ('strlen:' in asm) and not any(f in asm for f in
        ('memmove:','itoa:','itohex:','isspace:','strcat:','atoi:')))

print(f"\n{npass}/{ntot} libc tests passed")
sys.exit(0 if npass == ntot else 1)
