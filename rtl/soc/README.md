# ZX16 SoC — 16-bit CPU on a 32-bit NativeChips AMBA fabric

A small MCU that drops the 16-bit ZX16 AHB core onto NativeChips' 32-bit AMBA fabric
(`nc_amba`) with real APB peripherals (`nc_uart`, `nc_tmr`). The point: **real UART
output on silicon**, not just the simulator's `ecall` print services.

```
  zx16_core_ahb (16-bit, I + D AHB-Lite masters)
        │  zx16_ahb16to32  ×2   (address window + 16↔32 data lanes)
  nc_mcu_fabric (W_ADDR=32, W_DATA=32, W_PADDR=16, APB1 off)
        ├─ S0 @0x0000_0000 → zx16_ahb32_sram      (on-chip RAM)
        ├─ S1 / S2                                 (unused, tied off)
        └─ AHB→APB0 @0x4000_0000 → 16-slot APB3 splitter
               slot 0 @0x4000_0000 → nc_uart       (ZX16 sees 0xC000)
               slot 1 @0x4000_1000 → nc_tmr        (ZX16 sees 0xD000)
               slots 2..15                          (unused, PREADY tied high)
```

## Address map

The ZX16 is 16-bit, so it reaches the 32-bit system through a fixed window
("small high window"):

| ZX16 address | System / fabric | What |
|---|---|---|
| `0x0000–0xBFFF` | `0x0000_0000–0x0000_BFFF` | on-chip RAM (48 KB; SP starts at `0xC000`) |
| `0xC000–0xCFFF` | `0x4000_0000` (APB slot 0) | `nc_uart`  (CR `0xC000`, SR `0xC004`, DR `0xC008`) |
| `0xD000–0xDFFF` | `0x4000_1000` (APB slot 1) | `nc_tmr`   (CR `0xD000`, CNT `0xD100`, ARR `0xD108`) |
| `0xE000–0xFFFF` | `0x4000_2000–0x4000_3FFF` | APB slots 2–3 (free) |

The window is 16 KB, so the ZX16 reaches APB slots 0–3. A 16-bit store writes the
**low 16 bits** of a 32-bit APB register (the upper half is zeroed by the adapter);
keep timer `PSC`/`ARR` < 65536.

## Files

| file | role |
|---|---|
| `vendor/` | minimal vendored `nc_amba` + `nc_uart`/`nc_tmr` (see `vendor/PROVENANCE.md`) |
| `zx16_ahb16to32.v` | **adapter** — 16-bit ZX16 master ↔ 32-bit fabric port (address remap + byte/halfword lane steering) |
| `zx16_ahb32_sram.v` | behavioral 32-bit AHB SRAM (byte enables, `$readmemh`) |
| `zx16_soc.v` | top: core + 2 adapters + fabric + RAM + UART + timer |
| `tb_zx16_soc.v` | testbench; decodes the real UART TX line, halts on `ecall 0x3FF` |
| `soc_run.py` | compile firmware → assemble → pack `memh` → iverilog/vvp → capture UART |
| `test_soc.py` | integration tests (`hello`, `tmr`, monitor) |
| `test_irq_soc.py` | end-to-end hardware timer interrupt (ISR clears + counts → `RETI`) |
| `test_dbg_soc.py` | on-chip `ebreak` debugger demo (breakpoint → dump over UART → continue) |
| `fw/` | firmware: `hello.c`, `tmr.c`, `monitor.c` |

## Firmware I/O: `stdio_sim` vs `stdio_si`

`putchar`/`putint` are simulator **intrinsics** (ECALL). For real hardware, compile
with `codegen.INTRINSIC_IO = False` and include `stdio_si.c`, which implements
`putchar`/`putint`/`puts`/`puthex` over the UART (and `uart_getc`/`uart_haschar`).
`soc_run.py` sets this up and also lowers the stack below the peripheral window
(`STACK_TOP = 0xC000`). The ECALL version lives in `stdio_sim.c` (`stdio.c` aliases it).

## Debug monitor (`fw/monitor.c`)

A UART monitor that runs on the SoC and lets a host poke the system over serial.
**Full usage guide: [MONITOR.md](MONITOR.md).**
Commands take hex args, whitespace/newline separated:

| cmd | action |
|---|---|
| `r <addr>` | read a 16-bit word, print it |
| `w <addr> <val>` | write a 16-bit word |
| `d <addr> <n>` | dump `n` words from `addr` |
| `L <addr> <n>` | load `n` raw bytes (streamed after the newline) into RAM at `addr` |
| `g <addr>` | jump to `addr` / execute (does not return; uses inline `asm` + a global) |
| `q` | quit → halt |

So `L` + `g` make the monitor a **bootloader**: stream a program in over UART, then run it.
A loaded image must be position-independent or assembled for its load address — note the
assembler currently ignores `.org <non-default>` (code lands at `0x0020`), so relocatable
loading needs that assembler fix first.

It uses `uart_getc`/`uart_haschar` from `stdio_si.c`. The SoC's UART is instantiated
with `RX_FIFO_DEPTH=32` so a host can stream a command line without per-byte flow
control. `soc_run.run(c, rx="...")` injects serial input; `test_soc.py` drives it.
(Note: ZC has no empty statement, so firmware busy-waits use `while (cond) { }`.)

## Interrupts & on-chip debugger

The AHB core implements the ZX16 trap mechanism (`EPC`/`IE`, J-table vectors,
`ebreak`/`reti`/`ei`/`di`/`mfepc`/`mtepc`; see [docs/INTERRUPTS.md](../../docs/INTERRUPTS.md)).
The SoC adds a tiny **interrupt controller** in `zx16_soc.v` that folds peripheral IRQs
into the core's `irq_req`/`irq_num`:

| source | vector | ZX16 handler addr |
|---|---|---|
| `nc_tmr` `irq_o` | 2 (`0x0004`) | put a `J` at `0x0004` |
| `nc_uart` `irq_o` | 3 (`0x0006`) | put a `J` at `0x0006` |

A handler must clear the peripheral's own IRQ (e.g. the timer's `ICR`) before `RETI`,
and enable the source in the peripheral (the timer's `IM`) plus `EI` in the CPU.
`test_irq_soc.py` does exactly this end-to-end: a periodic timer interrupt drives an
assembly ISR that clears the flag and counts, three times, before the program prints
and halts.

**On-chip debugger (`test_dbg_soc.py`).** A software breakpoint = overwrite an
instruction with `ebreak` (save the original first; the I/D masters share RAM through
the fabric, so this self-modifying write is coherent). The trap vectors to a debug ISR
that dumps register state over the UART; to continue, restore the original instruction
and `RETI` (which re-executes it, since `EPC` = the breakpoint address). This is the
core of a UART debugger — wrap the monitor's command loop around the ISR for an
interactive `bp`/`regs`/`continue` protocol.

## Run

```sh
python3 rtl/soc/soc_run.py rtl/soc/fw/hello.c   # -> "Hello, ZX16 SoC!\n1234\nbeef\n"
python3 rtl/soc/test_soc.py                      # integration test (needs iverilog)
```

Drive the monitor from Python:
```python
import sys; sys.path.insert(0, "rtl/soc"); import soc_run; soc_run.build_sim()
print(soc_run.run("rtl/soc/fw/monitor.c", rx="w A000 1234\nr A000\nq\n")["text"])
```
