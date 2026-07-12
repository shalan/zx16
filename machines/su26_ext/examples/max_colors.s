# su26-ext: display all 64 palette colors (4 banks × 16 indices)
#
# Layout (20×15 tile map):
#   Rows 0–2   bank 0, columns 0–15 = color indices 0–15 (tiles 0–15)
#   Rows 3–5   bank 1, same
#   Rows 6–8   bank 2
#   Rows 9–11  bank 3
#   Rows 12–14 repeat bank 3 (or checker padding)
#   Cols 16–19: repeat indices 0–3
#
# Tiles 0..15: solid fill 0x00,0x11,...,0xFF (4bpp index = tile id)
# Palette: 4×16 RGB565 distinct colors at 0xFA00
#
# Build:
#   python3 tools/zx16asm.py machines/su26_ext/examples/max_colors.s \
#       -o bins/max_colors.bin -f bin
#   # OR: python3 tools/build_max_colors.py
# Run:
#   python3 -m machines.zx16sim --machine su26-ext bins/max_colors.bin --gui

.text
.org 0x0020
main:
    li      t0, 0xE0
    slli    t0, 8
    li      t1, 1
    sb      t1, 0(t0)           # GFX CTRL EN

    jal     ra, fill_palettes
    jal     ra, fill_tiles
    jal     ra, fill_map_attr

hang:
    j       hang

# ---- 64 RGB565 colors ----
# color(bank,i): systematic distinct 5-6-5 values
fill_palettes:
    addi    sp, -2
    sw      ra, 0(sp)
    clr     s0                  # bank
pb:
    clr     s1                  # i
pi:
    # r = (i*2 + bank*5 + 1) & 31
    mv      t0, s1
    add     t0, s1
    mv      t1, s0
    add     t1, s0
    add     t1, s0
    add     t1, s0
    add     t1, s0              # bank*5
    add     t0, t1
    addi    t0, 1
    li      a1, 31
    and     t0, a1              # r
    # g = (i*4 + bank*8 + 4) & 63
    mv      t1, s1
    slli    t1, 2
    mv      a0, s0
    slli    a0, 3
    add     t1, a0
    addi    t1, 4
    li      a1, 63
    and     t1, a1              # g
    # b = (i*3 + bank*7) & 31
    mv      a0, s1
    add     a0, s1
    add     a0, s1
    mv      a1, s0
    slli    a1, 3
    sub     a1, s0              # bank*7 = bank*8 - bank
    add     a0, a1
    li      a1, 31
    and     a0, a1              # b
    # rgb565
    mv      a1, t0
    slli    a1, 11
    slli    t1, 5
    or      a1, t1
    or      a1, a0
    # store
    li      t0, 0xFA
    slli    t0, 8
    mv      a0, s0
    slli    a0, 4
    add     a0, s1
    slli    a0, 1
    add     t0, a0
    sb      a1, 0(t0)
    srli    a1, 8
    sb      a1, 1(t0)

    addi    s1, 1
    li      t0, 16
    blt     s1, t0, pi_j
    j       pb_next
pi_j:
    j       pi
pb_next:
    addi    s0, 1
    li      t0, 4
    blt     s0, t0, pb_j
    j       pb_done
pb_j:
    j       pb
pb_done:
    lw      ra, 0(sp)
    addi    sp, 2
    ret

fill_tiles:
    clr     s0
ft:
    li      t0, 0xF2
    slli    t0, 8
    mv      a0, s0
    slli    a0, 7
    add     t0, a0
    mv      a0, s0
    slli    a0, 4
    or      a0, s0
    li      a1, 128
ftf:
    sb      a0, 0(t0)
    addi    t0, 1
    addi    a1, -1
    bnz     a1, ftf
    addi    s0, 1
    li      t0, 16
    blt     s0, t0, ft_j
    ret
ft_j:
    j       ft

fill_map_attr:
    clr     s0                  # row
fmr:
    # bank = min(row/3, 3)
    mv      a1, s0
    clr     a0                  # bank
    li      t0, 3
d3:
    blt     a1, t0, d3d
    sub     a1, t0
    addi    a0, 1
    j       d3
d3d:
    li      t0, 4
    blt     a0, t0, bok
    li      a0, 3
bok:
    # a0 = bank — save in s1 temporarily? need bank across cols
    # store bank in t1
    mv      t1, a0              # bank
    clr     s1                  # col
fmc:
    # tile = col % 16
    mv      a1, s1
    li      t0, 16
    blt     a1, t0, tuse
    addi    a1, -16
tuse:
    # map addr
    li      a0, 0xF0
    slli    a0, 8
    mv      t0, s0
    slli    t0, 4
    add     a0, t0
    mv      t0, s0
    slli    t0, 2
    add     a0, t0
    add     a0, s1
    sb      a1, 0(a0)
    # attr
    li      a0, 0xE1
    slli    a0, 8
    mv      t0, s0
    slli    t0, 4
    add     a0, t0
    mv      t0, s0
    slli    t0, 2
    add     a0, t0
    add     a0, s1
    sb      t1, 0(a0)           # bank

    addi    s1, 1
    li      t0, 20
    blt     s1, t0, fmc_j
    j       fmr_n
fmc_j:
    j       fmc
fmr_n:
    addi    s0, 1
    li      t0, 15
    blt     s0, t0, fmr_j
    ret
fmr_j:
    j       fmr
