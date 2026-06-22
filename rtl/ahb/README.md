# ZX16 CPU with AHB-Lite (2-stage pipeline)

A 2-stage pipelined ZX16 core with **decoupled memory**: the core is an AHB-Lite
*master* on two independent buses (instruction + data). Memory and peripherals are
external AHB-Lite *slaves*. Verified against the Python golden simulator at zero wait
states **and** with `HREADY` wait states injected.

## Files
| File | Role |
|------|------|
| `zx16_core_ahb.v` | 2-stage pipelined core, dual AHB-Lite masters (reuses `../zx16_alu.v`) |
| `ahb_sram.v` | AHB-Lite SRAM slave — `$readmemh`-loadable, runtime wait states; `MMIO=1` adds the scripted status/data device |
| `tb_zx16_ahb.v` | SoC testbench: core + I/D SRAM slaves, ECALL print/halt, `+ws=<n>` |
| `verify_ahb.py` | differential test vs `simulator/zx16sim.py` (zero-wait + wait-state stress) |

## Verify
```sh
python3 rtl/ahb/verify_ahb.py        # ws=0 then ws=2
python3 rtl/ahb/verify_ahb.py 0      # zero-wait only (fast)
```
Expected: **9/9 match** at both `ws=0` and `ws=2`, including MD5 and an 8-point FFT.

## Microarchitecture
- **2 stages map onto the AHB phases**: *Fetch* = address phase (drive `HADDR=PC`),
  *Execute* = data phase (instruction on `HRDATA` → decode / ALU / branch / reg-write).
  The fetch of instruction *i+1* overlaps the execute of *i* → ~1 CPI on straight-line code.
- **Hazards (simple, no forwarding)**: taken branch/jump = 1-cycle flush; loads/stores
  serialize (I-bus idles, D-bus does address then data phase, then the pipeline refills);
  `HREADY` low = **freeze** (hold bus address/control and all pipeline state).
- **Dual AHB-Lite masters** (Harvard at the bus level): no I/D contention, no arbiter.
- 16-bit `HADDR`/`HWDATA`/`HRDATA`; `HSIZE` = halfword (`LW`/`SW`) or byte (`LB`/`LBU`/`SB`)
  with byte-lane select on `HADDR[0]`; `HBURST`=SINGLE; `HTRANS` IDLE/NONSEQ; `HRESETn`
  async active-low.
- **ECALL** = halt + debug ports (`svc 0x3FF` halts; `0x000`/`0x001` print). Reset
  PC=`0x0020`, SP=`0xF000`.

## Notes
- The single-cycle core in `../` remains as the simple reference; this is the SoC-ready one.
- `ahb_sram.v` is a behavioral memory model for simulation; a real SoC would place a
  memory macro / BRAM behind the same AHB-Lite slave interface.
- `yosys` structural check of the core is clean (the register file maps to flip-flops).
