# Machines package (in-tree)

This directory is part of **shalan/zx16**. Machine CLIs:

```bash
python3 -m machines.zx16cc  --machine su26|su26-ext <file.c> -o out
python3 -m machines.zx16sim --machine su26|su26-ext out.bin [--gui]
```

## Relationship to `compiler/` ISS

| | `compiler` / golden ISS | `machines/*` |
|--|-------------------------|--------------|
| Role | toolchain correctness | course / SoC machine models |
| SP reset | often 0xF000 | su26: **0xEFFE** |
| UART / timer / enhanced GFX | no | su26-ext |

Adding a machine: create `machines/<name>/` with `machine.yaml`, `simulator/`, optional `cc/`, and register via folder name (see `registry.py`).
