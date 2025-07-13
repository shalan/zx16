# ECALL service numbers
.equ    SYS_GETSTR,        0x001   # Output single character
.equ    SYS_GETINT,        0x002   # Input single character
.equ    SYS_PUTSTR,        0x003   # Output null-terminated string
.equ    SYS_TONE,          0x004   # Output integer as decimal
.equ    SYS_VOL,           0x005   # Output integer as decimal
.equ    SYS_AUDIO_STOP,    0x006   # Output integer as decimal
.equ    SYS_GETKEY,        0x007   # Output integer as decimal
.equ    SYS_REGS_DUMP,     0x008   # Output integer as decimal
.equ    SYS_MEM_DUMP,      0x009   # Output integer as decimal
.equ    SYS_EXIT,          0x00A   # Exit program

.text
.org 0x000
    j   main
.org 0x0020
main:
    la      a0, welcome
    ecall   SYS_PUTSTR
    la      a0, prompt1
    ecall   SYS_PUTSTR
    ecall   SYS_GETINT
    mv      t0, a0
    ecall   SYS_GETINT
    add     a0, t0
    la      a0, prompt2
    ecall   SYS_PUTSTR
    ecall   SYS_REGS_DUMP
    ecall   SYS_EXIT


.data
welcome:
    .string     "Welcome to ECALL services test"
prompt1:
    .string     "Enter two integers to add"
prompt2:
    .string     "The sum is: "
