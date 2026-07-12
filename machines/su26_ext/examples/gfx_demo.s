# su26-ext GFX demo: fill palette, solid tiles, map, one sprite, scroll via ecall
# Run: assemble then
#   python3 -m machines.zx16sim --machine su26-ext bins/gfx_demo.bin
# Then dump RGB via Python helper or inspect sim.render_rgb()

.text
.org 0x0020
main:
    # --- palette bank 0: idx1 = red RGB565 0xF800, idx2 = green 0x07E0, idx3 = blue 0x001F
    li      t0, 0xFA
    slli    t0, 8               # 0xFA00
    # entry 1
    li      t1, 0x00
    sb      t1, 2(t0)           # lo of index 1 (offset 2)
    li      t1, 0xF8
    sb      t1, 3(t0)
    # entry 2 green 0x07E0
    li      t1, 0xE0
    sb      t1, 4(t0)
    li      t1, 0x07
    sb      t1, 5(t0)
    # entry 3 blue 0x001F
    li      t1, 0x1F
    sb      t1, 6(t0)
    li      t1, 0x00
    sb      t1, 7(t0)

    # --- tile 1 solid color 1 (0x11)
    li      t0, 0xF2
    slli    t0, 8               # 0xF200
    li      t1, 128
    add     t0, t1              # tile 1 @ F280
    li      a0, 0x11
    li      a1, 128
fill1:
    sb      a0, 0(t0)
    addi    t0, 1
    addi    a1, -1
    bnz     a1, fill1

    # --- tile 2 solid 0x22
    li      t0, 0xF2
    slli    t0, 8
    li      t1, 0x00
    # 2*128 = 256
    li      t1, 64
    slli    t1, 2
    add     t0, t1
    li      a0, 0x22
    li      a1, 128
fill2:
    sb      a0, 0(t0)
    addi    t0, 1
    addi    a1, -1
    bnz     a1, fill2

    # --- map: checker of tile 1 and 2
    li      t0, 0xF0
    slli    t0, 8               # F000
    li      a1, 300
    clr     s0
maplp:
    mv      a0, s0
    andi    a0, 1
    addi    a0, 1               # 1 or 2
    sb      a0, 0(t0)
    addi    t0, 1
    addi    s0, 1
    addi    a1, -1
    bnz     a1, maplp

    # --- sprite 0: tile 3 need define — use tile 1 at (40,40)
    # first make tile 3 = blue solid 0x33 at F200+3*128
    li      t0, 0xF2
    slli    t0, 8
    li      t1, 96
    slli    t1, 2               # 384 = 3*128
    add     t0, t1
    li      a0, 0x33
    li      a1, 128
fill3:
    sb      a0, 0(t0)
    addi    t0, 1
    addi    a1, -1
    bnz     a1, fill3

    li      t0, 0xE0
    slli    t0, 8
    li      t1, 0x40
    add     t0, t1              # OAM 0xE040
    li      t1, 40
    sb      t1, 0(t0)           # x
    sb      t1, 1(t0)           # y
    li      t1, 3
    sb      t1, 2(t0)           # tile
    li      t1, 0x21            # enable + prio
    sb      t1, 3(t0)

    # CTRL enable+sprites already default; set scroll
    li      a0, 8
    li      a1, 4
    ecall   0x072               # gfx_set_scroll

    # wait a couple vblanks
    ecall   0x070
    ecall   0x070
    ecall   0x071               # frame count in a0
    ecall   0x000               # print frame
    ecall   0x3FF
