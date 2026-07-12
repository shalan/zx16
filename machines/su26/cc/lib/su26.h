// su26.h — helpers for the Su26 educational machine (ECALL I/O)
// Include from ZC programs:  #include "su26.h"
// Note: zcc uses #include "file" and may need the path relative to the source
// or compile with include path = this directory.

// Intrinsics (codegen INTRINSIC_IO): putchar(c), putint(n) → ecall 0x001 / 0x000

// Keyboard poll: sets out via ecall 0x030 into globals, returns pressed flag.
// Implementation in su26_ecall.c — or use inline asm in examples.

#define SU26_ECALL_PRINT_INT   0x000
#define SU26_ECALL_PRINT_CHAR  0x001
#define SU26_ECALL_HALT        0x3FF
#define SU26_ECALL_READ_STR    0x010
#define SU26_ECALL_READ_INT    0x011
#define SU26_ECALL_PRINT_STR   0x012
#define SU26_ECALL_TONE        0x020
#define SU26_ECALL_VOLUME      0x021
#define SU26_ECALL_STOP_AUDIO  0x022
#define SU26_ECALL_KEYBOARD    0x030
#define SU26_ECALL_SEED_RNG    0x031
#define SU26_ECALL_RANDOM      0x032
#define SU26_ECALL_REGS_DUMP   0x040
#define SU26_ECALL_MEM_DUMP    0x041

// VRAM
#define SU26_TILE_MAP   0xF000
#define SU26_TILE_DATA  0xF200
#define SU26_PALETTE    0xFA00
#define SU26_MAP_COLS   20
#define SU26_MAP_ROWS   15
