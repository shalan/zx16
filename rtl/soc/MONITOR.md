# ZX16 UART Debug Monitor — Guide

`fw/monitor.c` is a tiny ROM monitor that runs on the ZX16 SoC and talks to a host
over the `nc_uart` serial line. It lets you **peek/poke memory and memory-mapped
peripherals, load a program into RAM, and run it** — i.e. a debug console + bootloader.
It is built on `stdio_si.c` (UART I/O) and the SoC's interrupt-free path.

---

## 1. Build and run

**In simulation (recommended):** drive it through `soc_run.py`, which compiles the
firmware, runs the RTL SoC under iverilog/vvp, injects your keystrokes on the UART RX
line (`rx=`), and returns everything the UART transmitted.

```python
import sys; sys.path.insert(0, "rtl/soc")
import soc_run; soc_run.build_sim()

r = soc_run.run("rtl/soc/fw/monitor.c", rx="w A000 1234\nr A000\nq\n")
print(r["text"])     # ZX16MON\n>ok\n>1234\n>bye\n
```

`rx` is a `str` (ASCII) or an iterable of byte values (use `bytes` when sending raw
binary, e.g. for the loader). The return dict has `text`, `bytes`, `halted`, `timeout`.

**On real hardware:** wire a serial terminal to the UART (`uart_tx`/`uart_rx`). The
sim uses `BRR.DIV=0` → 16 clocks/bit; on silicon set `BRR` for your `PCLK`
(`baud = PCLK / (16·(DIV+1))`). The monitor **does not echo** input, so enable local
echo in your terminal if you want to see what you type.

---

## 2. The session

On reset the monitor prints a banner and then a `>` prompt before every command:

```
ZX16MON
>
```

You type a command line (terminated by Enter). Commands are single letters with
**hex** arguments separated by spaces/newlines. Whitespace is forgiving. There is no
command history or editing.

---

## 3. Command reference

| Command | Action | Replies |
|---|---|---|
| `r <addr>` | read the 16-bit word at `addr` | the word, lowercase hex |
| `w <addr> <val>` | write 16-bit `val` to `addr` | `ok` |
| `d <addr> <n>` | dump `n` consecutive 16-bit words from `addr` | `n` words, space-separated |
| `L <addr> <n>` | load `n` **raw bytes** (sent right after the newline) into RAM at `addr` | `ok` |
| `g <addr>` | jump to `addr` and execute (does **not** return) | — |
| `q` | quit → CPU halts | `bye` |
| *(anything else)* | — | `?` |

All addresses are **byte** addresses; words are 16-bit little-endian. Hex output is
minimal-width lowercase (`0` → `0`, `255` → `ff`, `0xABCD` → `abcd`).

### Details & examples

- **`r <addr>`** — `r C004` reads the UART status register; `r A000` reads RAM word `A000`.
- **`w <addr> <val>`** — `w A000 BEEF` stores `0xBEEF`. Works on RAM *and* MMIO
  peripherals, e.g. `w D108 63` sets the timer's `ARR` to 99.
- **`d <addr> <n>`** — `d A000 4` prints the words at `A000, A002, A004, A006`.
- **`L <addr> <n>`** — load: send `L <addr> <n>` + newline, then exactly `n` raw bytes.
  The monitor writes them byte-by-byte starting at `addr`, then prints `ok`. (`n` is hex.)
- **`g <addr>`** — transfers control to `addr` via an indirect jump. The loaded code
  runs; control does not come back to the monitor (unless that code jumps back).
- **`q`** — prints `bye` and executes `ecall 0x3FF` (halt).

---

## 4. A worked session

Host sends `w A000 ABCD\nr A000\nw A002 1234\nd A000 2\nq\n`; the UART carries:

```
ZX16MON
>ok          (w A000 ABCD)
>abcd        (r A000)
>ok          (w A002 1234)
>abcd 1234   (d A000 2)
>bye         (q)
```

---

## 5. Loading and running a program (bootloader)

`L` + `g` make the monitor a bootloader: stream a program into RAM, then execute it.

```python
payload = bytes.fromhex("...")          # assembled, position-independent machine code
rx = b"L 9000 " + format(len(payload), "X").encode() + b"\n" + payload + b"g 9000\n"
print(soc_run.run("rtl/soc/fw/monitor.c", rx=rx)["text"])
```

The image **must be position-independent or assembled for its load address**
(`.org <addr>`): ZX16 `la`/jumps resolve to absolute addresses baked at assembly time.
A program compiled by ZC is laid out for `0x0020`, so to load it elsewhere assemble it
with the matching `.org`. See **Debugging** below for using the trap mechanism as a
breakpoint debugger.

---

## 6. Debugging (breakpoints & single-step)

The monitor is **not yet an interactive debugger** — it has no `b`/`c`/`regs`/`s`
commands. But the SoC's CPU has the full debug substrate, so those are one firmware
layer away (all verified at the ISA level — see [../../docs/INTERRUPTS.md](../../docs/INTERRUPTS.md)):

- **Software breakpoint** — overwrite an instruction with `ebreak` (after saving the
  original); it traps to a handler at vector 1, which can inspect state over the UART and
  `reti` to continue. Demonstrated end-to-end by `test_dbg_soc.py`
  (plant → trap → dump-over-UART → restore → continue).
- **Single-step** — the `step` instruction makes the CPU execute **exactly one**
  instruction after the next `reti`, then trap back to vector 1, so a handler can advance
  the debuggee one instruction at a time. Verified in `test_irq_rtl.py` (single-cycle)
  and `test_irq_ahb.py` (AHB pipeline, ws 0 & 2).
- **Registers** — on a trap the GPRs are untouched, so a handler reads the debuggee's
  registers by saving `x0–x7` to a buffer on entry (and `mfepc` for the PC).

A full interactive debugger wraps these in the command loop: `b <addr>` plants an
`ebreak`, `c` continues, `s` single-steps, `regs` dumps the saved registers, and a
**sticky** breakpoint re-arms itself by single-stepping over the original instruction
then re-inserting the `ebreak`. The ISA primitives
(`ebreak`/`reti`/`step`/`mfepc`/`mtepc` + `EPC`/`IE`) are all in place; this layer is the
planned next addition to `monitor.c`.

---

## 7. What memory you can reach

The monitor uses the ZX16 16-bit address map, so it can touch all of it:

| Range | Contents |
|---|---|
| `0x0000–0x001F` | interrupt vectors |
| `0x0020–0x7FFF` | program code |
| `~0x8000–0x8012` | the monitor's own `.data` (don't clobber) |
| `~0x8014–0xBFFF` | free RAM (use e.g. `0xA000` for scratch) |
| `0xBFFE↓` | stack |
| `0xC000–0xCFFF` | UART (CR `C000`, SR `C004`, DR `C008`) |
| `0xD000–0xDFFF` | timer (CR `D000`, CNT `D100`, ARR `D108`, …) |

So `r`/`w` double as a peripheral poke tool: read UART/timer status, configure the
timer, etc., live from the host.

---

## 8. Notes & limitations

- 16-bit words only (`r`/`w`/`d`); byte-granular writes go through `L`'s raw stream.
- Hex in, hex out; no decimal, no history/line-editing, no echo.
- `g` is one-way (no return); to come back, the loaded code must jump to the monitor.
- No interactive `b`/`c`/`regs`/`s` debug commands yet (see §6) — the underlying
  breakpoint/single-step support exists, but isn't wired into the command loop.
- The UART RX FIFO is 32 deep, so a host can paste a whole command line without
  per-byte flow control.
