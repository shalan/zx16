// su26-ext enhanced graphics (see docs/SU26_EXT_GFX.md)
#ifndef SU26_EXT_GFX_H
#define SU26_EXT_GFX_H

#define GFX_BASE      0xE000
#define GFX_CTRL      0xE000
#define GFX_STATUS    0xE004
#define GFX_FRAME     0xE008
#define GFX_SCROLL_X  0xE00C
#define GFX_SCROLL_Y  0xE010
#define GFX_BG_COLOR  0xE014
#define GFX_FRAME_DIV 0xE018

#define OAM_BASE      0xE040
#define ATTR_BASE     0xE100
#define TILE_HI       0xE800
#define TILE_MAP      0xF000
#define TILE_LO       0xF200
#define PALETTE_BASE  0xFA00

#define GFX_CTRL_EN      1
#define GFX_CTRL_BLANK   2
#define GFX_CTRL_SPR_EN  4
#define GFX_STATUS_VBL   1

#define ECALL_GFX_WAIT_VBLANK  0x070
#define ECALL_GFX_GET_FRAME    0x071
#define ECALL_GFX_SET_SCROLL   0x072

#endif
