# su26 smoke — minimal asm
.text
.org 0x0020
    li      a0, 7
    ecall   0x000               # print_int
    ecall   0x3FF               # halt
