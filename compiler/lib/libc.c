// libc.c -- pull in the whole ZX16 ZC standard library at once.
//
// Because codegen performs dead-function elimination (only functions reachable
// from main are emitted) and #include is include-once, a program can simply
//     #include "libc.c"
// and pay code size only for the functions it actually calls.
#include "ctype.c"
#include "string.c"
#include "stdlib.c"
#include "stdio.c"
