.org 0x0000
.text
start:
    lui   a0, 0x10000
    auipc a1, 0x20000
    mv    a0, a1
    jal   a0, label

label:
    ecall 1
    ecall 3
