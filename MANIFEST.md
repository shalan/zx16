# ZX16 / ZC project — file manifest

Everything generated in this conversation, grouped by purpose.

## Repository layout

```
.
├── README.md    ZX16 ISA specification
├── MANIFEST.md
├── assembler/   zx16asm.py
├── simulator/   zx16sim.py
├── compiler/    zcc.py, codegen.py, codegen_patterns.py
│   ├── examples/   01_gpio_set.c .. 07_tea.c
│   └── tests/      test_patterns.py, test_compile.py, test_embedded.py
└── docs/        SPEC.md (ZC language spec)
```

This mirrors the upstream `shalan/zx16` layout (assembler/, simulator/, docs/) and
adds `compiler/` for the ZC toolchain. The suites resolve their own paths, so they
run from anywhere, e.g. `python3 compiler/tests/test_compile.py`.

## ZX16 ISA (the assembly target)

- **README.md** — the ZX16 ISA specification (the repo's canonical spec, promoted to
  replace the original). Fixes the original's LI16 expansion (LUI+ORI, not ADDI), the
  J-range (-512..+510), removes the unimplemented LJ pseudo, corrects NOP/NEG, documents
  that x0 is general-purpose (not hardwired zero), clarifies U-Type/SYS encodings, and
  notes branches/jumps are PC+2-relative.
- **zx16asm.py** — the repo assembler with three bug fixes applied (drop-in replacement):
  1. logical-immediate range (ORI/ANDI/XORI accept full 7-bit field 0..127),
  2. pseudo-instruction sizing (push/pop/la are 4 bytes — labels after them were
     misplaced before),
  3. J-type jump range corrected to -512..+510 bytes. The offset field is imm[9:1]
     with the sign at bit 9, so only -512..+510 round-trips; the original -1024..+1020
     check silently miscompiled 511 offsets (e.g. +800 assembled, then executed as -224).

  The three fixes are applied directly in `assembler/zx16asm.py` (a drop-in replacement
  for the upstream file); no separate patch files are kept.

## ZC language + compiler

- **SPEC.md** — the ZC-embedded language specification. A self-hosting C subset with
  int/unsigned/char/pointers/arrays/structs, if/else, while + break/continue, full
  arithmetic+bitwise+unsigned operators, MMIO casts, volatile, asm(), hex literals.
  Drops for/switch/&&/||/! and the usual big-C items.
- **zcc.py** — lexer + recursive-descent parser producing a flat AST node table.
- **codegen.py** — AST -> ZX16 assembly walk: symbol table, type tracking
  (signed/unsigned, byte/word), lvalue/address generation, structs, pointers,
  arrays, globals, string pool, putint/putchar intrinsics.
- **codegen_patterns.py** — the validated codegen pattern library (the emit
  primitives codegen.py drives): expression eval, control flow, prologue/epilogue,
  far-calls, far-jumps, the __mul/__div/__mod software runtime.

## Execution / verification infrastructure

- **zx16sim.py** — a ZX16 instruction-set simulator with an MMIO device model
  (write log + scriptable register reads) so embedded programs are verified by
  execution, not assumed correct.

## Test suites (all currently green)

- **test_patterns.py** — 11/11 codegen primitives validated by execution.
- **test_compile.py** — 12/12 end-to-end ZC programs compiled and run.
- **test_embedded.py** — 5/5 embedded examples verified (incl. MMIO write-log checks).

## Example C programs (compiler/examples/)

- 01_gpio_set.c — GPIO bit set/clear via MMIO register   [verified]
- 02_poll_status.c — poll status register until READY     [verified]
- 03_reg_map.c — timer peripheral as a struct register map [verified]
- 04_checksum.c — XOR checksum over a byte buffer          [verified]
- 05_ring_buffer.c — FIFO ring buffer with wrap masking    [verified]
- 06_matmul.c — 3x3 integer matrix multiply               [verified vs reference]
- 07_tea.c — TEA cipher w/ 32-bit emulation layer  [verified vs reference]

## Resolved: the TEA failure was struct-global under-allocation

07_tea.c was the only program using struct *globals* (v0/v1/sum/k0..k3/delta), and it
printed wrong output. This was first hypothesized to be an evaluation-order bug (a
stale left operand), but execution tracing showed the real cause: codegen emitted a
single `.word` (2 bytes) for every non-array global regardless of type, so each 4-byte
struct global was under-allocated and overlapped the next one (A.hi aliased B.lo).
Setting one struct's `.lo` silently clobbered the previous struct's `.hi` -- which
*looked like* ".lo was read where .hi was needed." Fixed in codegen.py by reserving
each global's full, word-rounded size. TEA now matches a reference 32-bit TEA exactly
(0x8394fb95, 0x8da99b8b), and the path to MD5 / integer-FFT is unblocked.

## Status summary

Working: ZX16 assembler (fixed), simulator, ZC compiler (lexer/parser/codegen),
self-hosting-grade feature set, far-call/far-jump for large programs.
Verified by execution: 28 test programs + 5 embedded examples + matmul + TEA.
Not done: the actual self-host (compiler is written in Python, not yet in ZC);
MD5 and FFT stress tests (now unblocked).
