# ZX16 machines

Machine profiles for the ZX16 ecosystem: each machine defines **reset**, **memory map**,
**MMIO devices**, **ECALL services**, a **simulator**, and a **compiler (zx16cc) port**.

| Machine | Purpose |
|---------|---------|
| **`su26`** | CSCE 2303 Summer 2026 educational platform (handout `zx16-sim-su26.pdf`) |
| **`su26-ext`** | `su26` + **UART** + **timer** + **enhanced 2D GFX** (32 tiles, banks, sprites, vblank) — see `docs/SU26_EXT_GFX.md` |

Python package folder for `su26-ext` is `su26_ext/` (hyphen is the public machine name only).

```
machines/
  README.md
  registry.py          # discover machines
  zx16sim.py           # python3 -m machines.zx16sim --machine su26 prog.bin
  zx16cc.py            # python3 -m machines.zx16cc  --machine su26 foo.c
  common/              # shared ISA core + disasm
  su26/
    machine.yaml       # authoritative machine description
    README.md
    simulator/         # ISS for this machine
    cc/                # compiler port: CRT, libs, examples
    examples/          # asm / end-to-end demos
  su26_ext/            # machine name: su26-ext
    machine.yaml       # parent: su26 + UART/timer
    ...
```

## Quick start

```bash
# From repo root (this worktree: /path/to/zx16)
python3 -m machines.zx16cc  --machine su26     machines/su26/cc/examples/hello.c -o /tmp/hello
python3 -m machines.zx16sim --machine su26     /tmp/hello.bin
# → hello su26 42

python3 -m machines.zx16cc  --machine su26-ext machines/su26_ext/cc/examples/uart_hello.c -o /tmp/uh
python3 -m machines.zx16sim --machine su26-ext /tmp/uh.bin
# → uart-hello su26-ext / 1234

python3 -m machines.zx16cc  --machine su26-ext machines/su26_ext/cc/examples/timer_beep.c -o /tmp/tb
python3 -m machines.zx16sim --machine su26-ext /tmp/tb.bin
# → timer start / timer tick!

# Interactive GUI (browser) — su26-ext uses full scroll/sprite compositor
python3 -m machines.zx16sim --machine su26-ext bins/scroll_live.bin --gui
# open http://127.0.0.1:8765/  → click Run
```

See **INTEGRATION.md** for merging into `shalan/zx16`.

## Adding a machine

1. Create `machines/<name>/machine.yaml` (optionally `parent: su26`).
2. Implement `machines/<name>/simulator/sim.py` with `class MachineSim` (or subclass parent).
3. Add `machines/<name>/cc/` (target hooks + `lib/` + `examples/`).
4. Register in `registry.py` if not auto-discovered by folder name.

## Relationship to Green Card / reference sim

- **ISA decode/execute** is shared (`common/isa_core.py`), aligned with the Green Card.
- **Machine deviations** (SP reset, ecall map, MMIO) live only in the machine profile.
- `su26` intentionally sets **SP = 0xEFFE** (handout); reference silicon crt0 often uses `0xF000`.
