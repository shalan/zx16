# Machine: `su26`

Educational ZX16 platform for **CSCE 2303 Su26** (handout).

## Deviations from Green Card / generic reference

| Item | Green Card / ref | **su26** |
|------|------------------|----------|
| PC / load | often 0x0000 or flexible | **0x0020** |
| SP | 0xF000 (MMIO base) | **0xEFFE** (below tile map) |
| I/O | varies | **ECALL only** (no UART/timer MMIO) |
| Interrupts | full SYS | **out of scope** |

## I/O model

All host I/O is via **ECALL** (see `machine.yaml`). Graphics is **memory-mapped VRAM**
(`0xF000` / `0xF200` / `0xFA00`); the host composites tiles continuously.

## Simulator

```bash
python3 -m machines.zx16sim --machine su26 path/to/prog.bin
python3 -m machines.zx16sim --machine su26 path/to/prog.bin --trace
```

## Compiler port (`zx16cc --machine su26`)

```bash
python3 -m machines.zx16cc --machine su26 machines/su26/cc/examples/hello.c -o /tmp/hello
python3 -m machines.zx16sim --machine su26 /tmp/hello.bin
```

- CRT0 sets SP=`0xEFFE`, jumps to `main`, then `ecall 0x3FF`
- `putint` / `putchar` → ecall `0x000` / `0x001`
- Headers: `cc/lib/su26.h` (RNG, keyboard helpers)

## Examples

| Path | Description |
|------|-------------|
| `cc/examples/hello.c` | putstr / putint |
| `cc/examples/rng_demo.c` | seed_rng + random |
| `examples/smoke.s` | minimal asm halt |
