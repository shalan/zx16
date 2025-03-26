.text
.org    0
main:
    li a0, 5
    li t0, 1
    sra a0, t0
    li a0, 3
    sltui a0, 2
    jal x3, func
func:
    xori a0, 6
    ecall 1
    jal x3, exit

exit:
    ecall 3

