// stdio.c -- default stdio for the ZX16 simulator (ECALL-based). This is an alias for
// stdio_sim.c; real-silicon firmware includes stdio_si.c instead (UART, build with
// codegen.INTRINSIC_IO=False). See compiler/lib/stdio_sim.c and stdio_si.c.
#include "stdio_sim.c"
