# ZX16 single-cycle CPU (RTL)

A single-cycle implementation of the ZX16 ISA in **Verilog-2001**, verified against the
Python golden simulator (`simulator/zx16sim.py`) on every example program.

## Files
| File | Role |
|------|------|
| `zx16_core.v` | datapath + control + register file (one instruction per clock) |
| `zx16_alu.v`  | 16-bit ALU |
| `zx16_mem.v`  | unified 64 KB memory, word-organized, async read / sync write |
| `zx16_top.v`  | core + memory + a minimal scripted MMIO device (for `02_poll_status`) |
| `tb_zx16.v`   | testbench: `$readmemh` a program image, emulate ECALL print/halt |
| `verify.py`   | differential test: every example through the RTL **and** the golden sim |

## Verify
```sh
python3 rtl/verify.py
```
Compiles the RTL with iverilog, assembles each of the 9 ZC examples to a `$readmemh`
image, runs them on both the core and `zx16sim.py`, and diffs the console output.
Expected: `9/9 examples: RTL output matches the golden simulator` (includes MD5 and an
8-point FFT).

Structural check (no latches / loops / multiple drivers):
```sh
yosys -p "read_verilog rtl/zx16_alu.v rtl/zx16_mem.v rtl/zx16_core.v rtl/zx16_top.v; \
          hierarchy -top zx16_top; proc; check -assert"
```

## Design notes
- **Single-cycle**: combinational fetch/decode/execute; PC, registers, and memory
  commit on the rising edge. Memory is **async-read** — a simulation/teaching model;
  an FPGA mapping would use synchronous BRAM (and a multi-cycle or pipelined front end).
- **ECALL = halt + debug ports**: `ecall_svc` and `dbg_a0` are exposed; svc `0x3FF`
  halts, `0x000`/`0x001` are the print services the testbench performs (mirrors the sim).
- **Reset parameters** (both cores: `zx16_core`, `zx16_core_ahb`):
  - `RESET_PC` — default `0x0020` (toolchain entry; architectural vector reset is `0x0000`)
  - `RESET_SP` — default `0xF000` for the **lab** profile; platforms override (SoC uses `0xC000`)
- **ISA specifics encoded** (several were spec bugs fixed earlier in this project):
  the two-operand `rd/rs1 = [8:6]` field sharing; `x0` is a normal register (not
  hardwired zero); `ORI` zero-extends its imm7 while the other I-type immediates
  sign-extend; branches and `J`/`JAL` are PC+2-relative, `AUIPC` is PC-relative, and
  `JR`/`JALR` are absolute; the `J`/`JAL` range is ±512.
- **Interrupts/traps**: the core implements EPC/IE, `EBREAK`/`RETI`/`EI`/`DI`/`MFEPC`/`MTEPC`/`STEP`
  (see [docs/INTERRUPTS.md](../docs/INTERRUPTS.md)). The minimal `zx16_top` ties `irq_req=0`;
  the SoC folds timer/UART IRQs into the core (see `soc/`).

## Memory / stack profiles

These RTL trees implement **different memory maps**. The base ISA/ABI target is
documented in [docs/MEMORY_MAP.md](../docs/MEMORY_MAP.md) (general memory through
`0x7FFF`, optional page window, devices at `0xC000+`). Current RTL profiles:

| Profile | Path | Memory | Default `RESET_SP` | Notes |
|---------|------|--------|--------------------|--------|
| **Lab core** | `zx16_top` + `zx16_mem` | 64 KB unified RAM; toy MMIO at `0xF020`/`0xF021` | `0xF000` | Matches legacy compiler embedded examples |
| **AHB lab** | `ahb/` | Dual AHB SRAMs; optional same toy MMIO | `0xF000` | Pipelined AHB core |
| **SoC** | `soc/` | RAM `0x0000`–`0xBFFF`; UART `0xC000`; timer `0xD000` | **`0xC000`** | First push → `0xBFFE`; stack stays out of APB |
| **ISA v2 (docs)** | — | General `0x0000`–`0x7FFF`; optional `0x8000`–`0xBFFF`; MMIO/VRAM `0xC000+` | e.g. `0x8000` | Target map; paging not in RTL yet |

Base ABI / portable code must not **require** the page window (`0x8000`–`0xBFFF`).
The SoC today maps that range as **plain RAM** (48 KB total) — a superset of the
minimal general region, not the optional paging extension.

## Status & limitations
- 9/9 examples match the golden simulator; yosys structural check clean.
- No QSPI XIP / PSRAM page-window RTL yet (optional per memory-map annex).
- The software `__mul`/`__div` runtime is O(operand), so programs with negative or
  large multiplicands (e.g. the FFT's negative twiddles) execute millions of
  instructions — correct, but slow; the testbench cycle cap is sized accordingly.
