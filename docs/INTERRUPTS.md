# ZX16 Interrupts & Traps

The ISA reserves a 16-entry interrupt vector table at `0x0000–0x001F`. This document
defines the **trap mechanism** that uses it: how a trap is taken, how state is saved,
and how a handler returns. Reference implementation: `simulator/zx16sim.py` (the cores
follow it). Design choice: **jump-table vectors + a dedicated EPC register**.

## Vector table (jump table)

16 entries, 2 bytes each, at `0x0000, 0x0002, … 0x001E`. **Each entry is a `J`
instruction** to the handler (not a pointer). On a trap to vector *i*, hardware sets
`PC ← i*2`; the `J` there jumps to the handler. (`J` reaches ±512 B — handlers live
near the table or are reached by a trampoline.)

| vector | addr | source |
|---|---|---|
| 0 | `0x0000` | reset (toolchain convention currently enters at `0x0020` directly) |
| 1 | `0x0002` | **EBREAK** (software breakpoint / debug trap) |
| 2..15 | `0x0004`..`0x001E` | hardware IRQs (assigned by the SoC; e.g. timer, UART) |

## State

- **`EPC`** — return address saved on trap (a dedicated register, not a GPR).
- **`IE`** — global interrupt enable. Reset = 0 (interrupts off until firmware enables).

## Trap entry / exit

**Hardware IRQ** *i* (taken at an instruction boundary while `IE=1`):
```
EPC ← PC            ; the instruction that would have run next
IE  ← 0             ; mask further interrupts (no auto-nesting)
PC  ← i*2           ; vector
```
**EBREAK** (always traps, regardless of `IE`):
```
EPC ← PC            ; address of the EBREAK itself
IE  ← 0
PC  ← 0x0002        ; vector 1
```
**RETI** (return from handler): `PC ← EPC ; IE ← 1`.

Because `EBREAK` saves its own address, `RETI` re-executes it — correct for a software
breakpoint (the debugger restores the original instruction first). To *continue past* a
bare `EBREAK`, the handler advances EPC: `MFEPC rd ; ADDI rd,2 ; MTEPC rd ; RETI`.

A handler preserves any GPRs it uses on the stack (`x2`/`sp` is valid on entry); the
only thing it cannot save with a normal instruction is `PC`, which is why `EPC` is
hardware.

## Instructions (SYS-type, opcode `111`, sub-function in bits `[5:3]`)

| mnemonic | `[5:3]` | raw word | effect |
|---|---|---|---|
| `ECALL svc` | `000` | `(svc<<6)\|0x7` | environment service (print/halt) — unchanged |
| `EBREAK` | `001` | `0x000F` | trap to vector 1 |
| `RETI`   | `010` | `0x0017` | `PC←EPC; IE←1` |
| `EI`     | `011` | `0x001F` | `IE←1` |
| `DI`     | `100` | `0x0027` | `IE←0` |
| `MFEPC rd` | `101` | `(rd<<6)\|0x2F` | `rd ← EPC` |
| `MTEPC rd` | `110` | `(rd<<6)\|0x37` | `EPC ← rd` |
| `STEP`     | `111` | `0x003F`        | request single-step (armed by the next `RETI`) |

`ECALL` keeps its environment-service role (so the toolchain/`stdio_sim` are unchanged);
`EBREAK` is the in-memory vectoring trap used for breakpoints.

## Single-step

`STEP` sets a step request; it does **not** take effect immediately. The next `RETI`
*arms* it, so the CPU executes **exactly one** instruction back in the debuggee and then
traps to vector 1 — with `EPC` set to the following instruction (the resume point, not
re-execute). A debug handler therefore steps the debuggee one instruction at a time with
`... STEP ; RETI` and regains control after each one. (`EBREAK` and a hardware IRQ both
trap *before* their instruction and re-run it; `STEP` traps *after* and advances.)
A hardware interrupt is not taken while a step is in flight.

## Example (continue past an EBREAK)

```asm
.org 0x0002
    j   bp_handler          ; vector 1
.org 0x0020
main:
    ...
    ebreak                  ; (.word 0x000F)
    ...                     ; resumes here after the handler
bp_handler:
    ...                     ; save x6, inspect, etc.
    mfepc x6                ; (.word 0x01AF)
    addi  x6, 2
    mtepc x6                ; (.word 0x01B7)
    reti                    ; (.word 0x0017)
```

## Status

- **Reference sim (`zx16sim.py`): implemented + tested** (`compiler/tests/test_interrupts.py`):
  EBREAK round-trip, hardware IRQ round-trip, IRQ masking while `IE=0`. `raise_irq(n)`
  models a pending hardware interrupt.
- **Pending:** assembler mnemonics (use raw `.word` meanwhile); the AHB + single-cycle
  cores; SoC IRQ wiring (`nc_uart`/`nc_tmr` `irq_o` → interrupt controller → core); an
  EBREAK-based on-chip debugger.
