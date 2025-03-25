.org 0x0000
.text
start:
    li   a0, 10             ; I‑type: load immediate 10 into a0 (reg 6)
    li   a1, 20             ; I‑type: load immediate 20 into a1 (reg 7)
    add  a0, a1             ; R‑type: a0 = a0 + a1
    sub  a0, a1             ; R‑type: a0 = a0 - a1
    sll  a0, t1             ; R‑type: a0 = a0 << t1
    srl  a0, t1             ; R‑type: logical shift right
    sra  a0, t1             ; R‑type: arithmetic shift right
    or   a0, a1             ; R‑type: a0 = a0 | a1
    and  a0, a1             ; R‑type: a0 = a0 & a1
    xor  a0, a1             ; R‑type: a0 = a0 ^ a1
    mv   a0, a1             ; R‑type: a0 = a1
    jr   a0                ; R‑type: jump register (single operand; reg2 defaults to a0)
    jalr a0                ; R‑type: jump and link register (single operand)
    addi a0, 5             ; I‑type: a0 = a0 + 5
    slti a0, 7             ; I‑type: set a0 = (a0 < 7) ? 1 : 0
    sltui a0, 7            ; I‑type: unsigned version
    slli a0, 1             ; I‑type: shift left immediate
    srli a0, 1             ; I‑type: logical shift right immediate
    srai a0, 1             ; I‑type: arithmetic shift right immediate
    ori  a0, 0x03         ; I‑type: a0 = a0 | 0x03
    andi a0, 0x0F         ; I‑type: a0 = a0 & 0x0F
    xori a0, 0x05         ; I‑type: a0 = a0 ^ 0x05

    ; Branch instructions with targets placed immediately afterward
    beq  a0, a1, branch_equal       ; B‑type: branch if equal
branch_equal:
    li   t0, 1                     ; I‑type: set t0 (reg 0) to 1

    bne  a0, a1, branch_notequal    ; B‑type: branch if not equal
branch_notequal:
    li   t0, 2                     ; I‑type: set t0 to 2

    blt  a0, a1, branch_less        ; B‑type: branch if less than
branch_less:
    li   t1, 3                     ; I‑type: set t1 (reg 5) to 3

    bge  a0, a1, branch_notless     ; B‑type: branch if not less than
branch_notless:
    li   t1, 4                     ; I‑type: set t1 to 4

    bltu a0, a1, branch_lessu       ; B‑type: branch if less than (unsigned)
branch_lessu:
    li   a0, 5                     ; I‑type: set a0 to 5

    bgeu a0, a1, branch_notlessu    ; B‑type: branch if not less than (unsigned)
branch_notlessu:
    li   a1, 6                     ; I‑type: set a1 to 6

    bz   a0, branch_zero            ; B‑type: branch if a0 is zero (single register)
branch_zero:
    li   s0, 7                     ; I‑type: set s0 (reg 3) to 7

    bnz  a1, branch_nonzero         ; B‑type: branch if a1 is nonzero (single register)
branch_nonzero:
    li   s1, 8                     ; I‑type: set s1 (reg 4) to 8

    j    loop                      ; J‑type: jump (PC‑relative)
    jal  subroutine                ; J‑type: jump and link

    lui  s0, 0x1A3                ; U‑type: load upper immediate into s0 (reg 3)
    auipc s1, 0x0F0               ; U‑type: add upper immediate to PC into s1 (reg 4)
    ecall 0                      ; SYS‑type: system call with svc=0

loop:
    addi a0, 1                 ; I‑type: increment a0
    beq  a0, a1, end_loop       ; B‑type: branch if a0 equals a1
    j    loop                  ; J‑type: jump back to loop

subroutine:
    add  a0, a0                ; R‑type: dummy subroutine (double a0)
    jr   ra                    ; R‑type: return via jump register

end_loop:
    mv   t0, t0                ; R‑type: dummy nop (move t0 to itself)

.data
.org 0x4000
string:
    .asciiz "Hello, Z16!"       ; Data: null‑terminated string
bytes:
    .byte 0x1, 2, 0xFF, 42      ; Data: 4 bytes
words:
    .word 100, 200, 0x300       ; Data: 3 words (16‑bit values)
reserved:
    .space 16                  ; Data: reserve 16 bytes
