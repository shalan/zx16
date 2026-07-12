# su26-ext: TX 'A' via UART MMIO then halt
.text
.org 0x0020
    # t0 = 0xC000
    li      t0, 0xC0
    slli    t0, 8
    # CR low = 0x01, CR high = 0x03 → 0x0301
    li      t1, 0x01
    sb      t1, 0(t0)
    li      t1, 0x03
    sb      t1, 1(t0)
    # DR at 0xC008
    mv      t1, t0
    addi    t1, 8
    li      a0, 65              # 'A'
    sb      a0, 0(t1)
    ecall   0x3FF
