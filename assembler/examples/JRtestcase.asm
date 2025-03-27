# Function Calls

    .text
    .org    0
main:

li a0, 5
li t0, 1
sra a0, t0
li t0, 118
sltu a0, t0
jal ra, func
ecall 1

ecall 3


func:
xori a0, 6
jr ra
