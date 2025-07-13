# Some colors
.equ    COLOR_RED,          0xE0
.equ    COLOR_BLUE,         0x03
.equ    COLOR_GREEN,        0x1C
.equ    COLOR_WHITE,        0xFF
.equ    COLOR_BLACK,        0x00
.equ    COLOR_YELLOW,       0xFC

.equ    SYS_EXIT,          0x00A   # Exit program


.text
.org 0x000
    j   main
.org 0x0020
main:
    la      a0, tile_red
    la      a1, video_tile_0
    call    fill_tile_fn
    la      a0, tile_blue
    la      a1, video_tile_1
    call    fill_tile_fn
    la      a0, tile_green
    la      a1, video_tile_2
    call    fill_tile_fn
    la      a0, tile_yellow
    la      a1, video_tile_3
    call    fill_tile_fn

    li      a0, 0       # tile 0, red
    li      a1, 0       # at col 0
    call    draw_col_fn

    li      a0, 1       # tile 1, blue
    li      a1, 1       # at col 1
    call    draw_col_fn
    
    li      a0, 2       # tile 2, green
    li      a1, 2       # at col 2
    call    draw_col_fn

    ecall   SYS_EXIT
    
    

draw_col_fn:
    li16    t0, 15
    la      t1, video_tile_map
    add     t1, a1
loop_1:
    bz      t0, done_1
    sb      a0, 0(t1)
    dec     t0
    addi    t1, 20
    j       loop_1
done_1:
    ret    

fill_tile_fn:
    li16    t0, 128
loop_2:
    bz      t0, done_2
    lbu     t1, 0(a0)
    sb      t1, 0(a1)
    inc     a0
    inc     a1
    dec     t0
    j       loop_2
done_2:
    ret

    
.data
colors:
    .byte   COLOR_RED, COLOR_BLUE, COLOR_GREEN, COLOR_WHITE, COLOR_BLACK, COLOR_YELLOW

tile_red:
    .fill   128, 1, 0x00       # red
tile_blue:
    .fill   128, 1, 0x11       # blue
tile_green:
    .fill   128, 1, 0x22       # green
tile_yellow:
    .fill   128, 1, 0x55       # green

# the video memory
# The tile map
    .org    0xF000
video_tile_map:

# The tile definitions
    .org    0xF200
video_tile_0:
    .org    0xF280
video_tile_1:
    .org    0xF300
video_tile_2:
    .org    0xF380
video_tile_3:
    .org    0xF400
video_tile_4:
    .org    0xF480
video_tile_5:

# The palette
    .org    0xFA00
video_palette:

