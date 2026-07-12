# su26-ext live scroll — fast loop for interactive GUI
# python3 -m machines.zx16sim --machine su26-ext bins/scroll_live.bin --gui
#
# No blocking ecall 0x070 (that starved the GUI). Instead:
#   - set FRAME_DIV low
#   - busy-wait a short fixed count
#   - bump scroll + sprite each frame

.text
.org 0x0020
main:
    # GFXCTRL @ 0xE000: EN|SPR, FRAME_DIV=500
    li      t0, 0xE0
    slli    t0, 8
    li      t1, 5
    sb      t1, 0(t0)           # CTRL
    mv      t1, t0
    li      a0, 24
    add     t1, a0
    li      a0, 0xF4            # 500 = 0x01F4
    sb      a0, 0(t1)
    li      a0, 0x01
    sb      a0, 1(t1)

    # palette RGB565 bank0
    li      t0, 0xFA
    slli    t0, 8
    # idx1 red F800
    li      t1, 0x00
    sb      t1, 2(t0)
    li      t1, 0xF8
    sb      t1, 3(t0)
    # idx2 green 07E0
    li      t1, 0xE0
    sb      t1, 4(t0)
    li      t1, 0x07
    sb      t1, 5(t0)
    # idx3 blue 001F
    li      t1, 0x1F
    sb      t1, 6(t0)
    clr     t1
    sb      t1, 7(t0)
    # idx4 yellow FFE0
    mv      t1, t0
    addi    t1, 8
    li      a0, 0xE0
    sb      a0, 0(t1)
    li      a0, 0xFF
    sb      a0, 1(t1)

    jal     ra, make_tiles
    jal     ra, fill_map
    jal     ra, init_sprite

    clr     s0                  # scroll_x
    clr     s1                  # scroll_y

loop:
    # short delay (keep GUI responsive)
    li      t0, 2000
delay:
    addi    t0, -1
    bnz     t0, delay

    addi    s0, 2
    li      t1, 320
modx:
    blt     s0, t1, doy
    sub     s0, t1
    j       modx
doy:
    addi    s1, 1
    li      t1, 240
mody:
    blt     s1, t1, setsc
    sub     s1, t1
    j       mody
setsc:
    mv      a0, s0
    mv      a1, s1
    ecall   0x072               # set scroll (marks video dirty)

    # bounce sprite X
    li      t0, 0xE0
    slli    t0, 8
    li      t1, 0x40
    add     t0, t1              # OAM
    lbu     t1, 0(t0)
    addi    t1, 3
    li      a0, 280
    blt     t1, a0, sxok
    li      t1, 8
sxok:
    sb      t1, 0(t0)
    lbu     t1, 1(t0)
    addi    t1, 1
    li      a0, 200
    blt     t1, a0, syok
    li      t1, 8
syok:
    sb      t1, 1(t0)

    j       loop

fill_map:
    li      t0, 0xF0
    slli    t0, 8
    li      a1, 300
    clr     s0
fmlp:
    mv      a0, s0
    andi    a0, 3
    addi    a0, 1
    sb      a0, 0(t0)
    addi    t0, 1
    addi    s0, 1
    addi    a1, -1
    bnz     a1, fmlp
    ret

init_sprite:
    li      t0, 0xE0
    slli    t0, 8
    li      t1, 0x40
    add     t0, t1
    li      t1, 60
    sb      t1, 0(t0)
    sb      t1, 1(t0)
    li      t1, 4
    sb      t1, 2(t0)
    li      t1, 0x21            # enable + prio
    sb      t1, 3(t0)
    ret

make_tiles:
    addi    sp, -2
    sw      ra, 0(sp)
    li      s0, 1
mt_lp:
    li      t0, 0xF2
    slli    t0, 8
    mv      a0, s0
    slli    a0, 7
    add     t0, a0
    mv      a0, s0
    slli    a0, 4
    or      a0, s0
    li      a1, 128
mt_fill:
    sb      a0, 0(t0)
    addi    t0, 1
    addi    a1, -1
    bnz     a1, mt_fill
    addi    s0, 1
    li      t1, 5
    blt     s0, t1, mt_more
    j       mt_done
mt_more:
    j       mt_lp
mt_done:
    lw      ra, 0(sp)
    addi    sp, 2
    ret
