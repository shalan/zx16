    .text
    .org    0
main:
    li a0, 0
    li t0, 5
    bz a0, else
    ecall 1
label1:
addi t0, -5
else:
    addi t0, 2
    ecall 1
    ecall 3



