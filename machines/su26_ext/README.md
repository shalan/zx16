# Machine: `su26-ext`

**Parent:** `su26`  
Adds **UART**, **timer**, and **enhanced 2D graphics** (32 tiles, ATTR, palette
banks, 8 sprites, vblank/scroll).

**Graphics architecture:** [`docs/SU26_EXT_GFX.md`](../docs/SU26_EXT_GFX.md)

## New MMIO

| Device | Base | Notes |
|--------|------|--------|
| UART0 | `0xC000` | Compatible with `compiler/lib/stdio_si.c` |
| TIMER0 | `0xD000` | Compatible with `compiler/lib/timer_si.c` |

### UART registers

| Offset | Name | Role |
|--------|------|------|
| +0x000 | CR | EN, TXEN, RXEN |
| +0x004 | SR | TXE (bit0), RXNE (bit1) |
| +0x008 | DR | data |
| +0x100 | BRR | baud divisor (sim ignores timing) |

### Timer registers

| Offset | Name | Role |
|--------|------|------|
| +0x000 | CR | CEN enable |
| +0x024 | RIS | UIF overflow flag |
| +0x02C | ICR | write 1 to clear UIF |
| +0x100 | CNT | counter |
| +0x104 | PSC | prescaler |
| +0x108 | ARR | auto-reload |

Sim model: each executed instruction advances the timer clock by 1; when CEN=1,
every `(PSC+1)` steps increments CNT; at ARR wrap, sets UIF.

## Extra ecalls

| svc | Name |
|-----|------|
| `0x050` | timer_millis |
| `0x051` | timer_set_match (ARR) |
| `0x052` | timer_wait_uif |
| `0x060` | uart_putc |
| `0x061` | uart_getc |
| `0x062` | uart_haschar |
| `0x070` | gfx_wait_vblank |
| `0x071` | gfx_get_frame |
| `0x072` | gfx_set_scroll |

All **su26** ecalls remain available.

## Graphics (summary)

| Feature | Spec |
|---------|------|
| Tiles | **32** × 4 bpp (lo `@0xF200`, hi `@0xE800`) |
| Attr map | `@0xE100` bank/flip/prio |
| Palette | 4×16 RGB565 `@0xFA00` |
| Sprites | 8 × OAM `@0xE040` |
| CTRL | `@0xE000` vblank/frame/scroll |

## Build & run

```bash
python3 -m machines.zx16cc  --machine su26-ext machines/su26-ext/cc/examples/uart_hello.c -o /tmp/uh
python3 -m machines.zx16sim --machine su26-ext /tmp/uh.bin

python3 -m machines.zx16cc  --machine su26-ext machines/su26-ext/cc/examples/timer_beep.c -o /tmp/tm
python3 -m machines.zx16sim --machine su26-ext /tmp/tm.bin
```

### GFX demos

```bash
# All 32 tiles from Super Mario Bros. NES tileset (Spriters Resource 52571)
python3 tools/build_all_tiles.py
python3 -m machines.zx16sim --machine su26-ext bins/all_tiles.bin --gui

# All 64 palette colors
python3 tools/build_max_colors.py
python3 -m machines.zx16sim --machine su26-ext bins/max_colors.bin --gui
```

## Compiler port

- Same CRT0 SP=`0xEFFE` as su26  
- `cc/lib/stdio_uart.c` — putchar via UART MMIO (optional path)  
- `cc/lib/timer.c` — timer_start / timer_expired helpers  
- Examples use either ecall UART or MMIO drivers  
