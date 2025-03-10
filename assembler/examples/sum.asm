# A simple example
    .text
    .org    0
main:
    li      s0, 10
    li      s1, 0
    lui     t0, %hi(0xA3B)
    addi    t0, %lo(0xA3B)
    
L1:
    BZ      s0, done        # branch to done of s0 is zero
    addi    s1, s0
    addi    s1, -1
    j       L1
done:     
    mv      a0, s0
    lui     a0, %hi(str)
    addi    a0, %lo(str)
    ecall   5               # service 5 to print a string
exit:
    ecall   3

    .data
    .org    0x100
str:   
    .asciiz "hello world!"
A:
    .byte   50
B:
    .word   0x23A0, 500, 30000
C:
    .space  200