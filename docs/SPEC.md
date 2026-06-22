# ZC — a self-hosting C subset for ZX16 (embedded profile)

ZC is a small subset of C designed for two goals at once:

1. **Self-hosting** — the ZC compiler can be written in ZC and compile itself.
2. **Bare-metal embedded use** — direct hardware access, bit manipulation, and
   unsigned address arithmetic on ZX16.

These goals reinforce each other: every feature added for embedded work (bytes,
unsigned, bitwise ops, structs) is also useful in the compiler's own source, so the
subset stays closed under "what it takes to compile itself."

The guiding rule: **ZC contains what the compiler needs plus what bare-metal ZX16
code needs — and nothing else.** Convenience features with easy rewrites are out.

---

## Types

| Type            | Size | Notes |
|-----------------|------|-------|
| `int`           | 2 bytes, signed   | the native word |
| `unsigned`      | 2 bytes, unsigned | addresses, masks, register values |
| `char`          | 1 byte, signed    | bytes, MMIO registers, string chars |
| `unsigned char` | 1 byte, unsigned  | raw byte values 0..255 |
| `T *`           | 2 bytes           | pointer to any type |
| `T[N]`          | N x sizeof(T)     | array, decays to pointer in expressions |
| `struct Tag`    | sum of members (aligned) | records; see Structs |

- `void` allowed only as a function return type.
- No `long`, `short`, `float`, `double`, `union`, `enum`, `typedef`.
- Signedness matters for: comparisons (`slt` vs `sltu`), right shift (`sra` vs
  `srl`), and `char` load (`lb` vs `lbu`). The compiler tracks it per expression.

## Structs

```c
struct Point { int x; int y; };
struct Dev   { char status; char ctrl; int count; char buf[16]; };
struct Node  { int kind; struct Node *next; };
```

- Members laid out in declaration order. `int`/`unsigned`/pointer members are
  2-byte aligned (the compiler inserts padding before them when needed, since ZX16
  `lw`/`sw` require even addresses); `char` members are byte-aligned.
- Access: `s.field` and `p->field`. Field offset is a compile-time constant; codegen
  emits `base + offset` then a load/store. (Offsets beyond the +-7 instruction range
  are materialized into a register automatically.)
- **Structs are used through pointers.** Passing/returning a struct *by value* is not
  supported in v1; pass `struct T *`. This matches both embedded register-block usage
  and the compiler's AST/symbol nodes.
- Self-referential structs are allowed via pointer members.

## Declarations

```c
int x;                 unsigned mask;
char *p;               int a[100];
struct Node *head;
int g = 5;             // global, constant scalar initializer only
```

- Globals may have a constant scalar initializer. Locals are uninitialized.
- One declaration per statement (no `int a, b;`).
- Array sizes are integer-constant literals.

## Functions

- Parameters are scalars, pointers, or `struct *` (never struct by value).
- Recursion supported and required.
- Forward references allowed.
- All arguments passed on the stack, right-to-left; result in `a0` (x6).

## Statements

- `expr ;`
- `return expr ;` / `return ;`
- `{ ... }` block (scope)
- `if (expr) stmt` / `if (expr) stmt else stmt`
- `while (expr) stmt`
- `break ;` / `continue ;`  — innermost `while` only
- local declaration (anywhere a statement may appear)
- `asm("...");` — emit the string verbatim into output assembly (escape hatch)

**Dropped:** `for`, `switch`, `do/while`, `goto`.
Rewrite `for` as `while`. `switch` is sugar for an `if`/`else if` ladder, which the
language already expresses (and which the compiler uses for token dispatch); it may
be added later as pure syntactic sugar without ABI impact.

> **`continue` in `while` (important):** `continue` jumps to the loop's condition
> test, not past an increment. Unlike `for`, a `while` keeps its increment in the
> body, so the increment must appear *before* any `continue` that should still
> advance the loop — otherwise `continue` re-tests an unchanged condition and spins.
> Idiom: `while (i < n) { i = i + 1; if (skip) continue; ...; }`.

## Expressions

Precedence (low -> high), left-associative except assignment and unary:

1.  assignment `=`
2.  equality `==` `!=`
3.  relational `<` `<=` `>` `>=`   (signed or unsigned per operand type)
4.  bitwise or `|`
5.  bitwise xor `^`
6.  bitwise and `&`
7.  shift `<<` `>>`   (`>>` arithmetic on signed, logical on unsigned)
8.  additive `+` `-`
9.  multiplicative `*` `/` `%`   (`/` `%` signed or unsigned per operand type)
10. unary `-` `~` `*`(deref) `&`(address-of) `(type)`(cast)
11. postfix `f(args)` `a[i]` `s.field` `p->field`
12. primary: identifier, int literal, char literal, string literal, `(expr)`

- **Dropped:** `&&`, `||`, `!`, `?:`, `++`, `--`, compound assignment (`+=` etc.),
  comma operator. Use nested `if` for `&&`; `x == 0` for `!x`; `x = x + 1` for `x++`.
- **Casts** limited to integer<->pointer and pointer<->pointer for absolute
  addresses: `*(volatile char *)0xF000 = c;`  `(struct Dev *)0x9100`. No arithmetic
  conversions beyond sign reinterpretation.
- `volatile` accepted in declarations and casts. Because the compiler does no
  optimization, every access already emits a real load/store, so `volatile` is
  honored automatically; the keyword is accepted for portability and intent.
- String literals have type `char *`, stored in a read-only pool.
- `*` `/` `%` use runtime helpers; every other operator is a single ZX16 instruction.
  `/` and `%` go through `__udivmod` (restoring binary long division, bounded to 16
  iterations) — directly when either operand is unsigned/pointer, else via the signed
  wrappers `__div`/`__mod`. Signed `/` truncates toward zero and `%` takes the sign of
  the dividend (C99); division by zero is defined to yield quotient `0xFFFF` (no trap,
  no hang).

## Lexical

- Identifiers: `[A-Za-z_][A-Za-z0-9_]*`
- Integer literals: decimal and `0x` hex (hex essential for embedded).
- Char literals: `'a'`, escapes `\n \t \0 \\ \' \r`.
- String literals: `"..."`, same escapes.
- Comments: `//` to end of line. (No `/* */`.)
- Minimal preprocessor: `#include "file"` (recursive, **include-once**; no `<system>`
  headers) and object-like `#define NAME value` (single line, no parameters; nested
  macros allowed). A `#define` constant may be used where a literal is required (e.g.
  array sizes). Not supported: function-like macros, conditionals (`#if`/`#ifdef`),
  `#undef`, `##`, `#`. `int`/`unsigned` globals still work as RAM-backed constants.

## Runtime / ABI (ZX16)

- `int`/`unsigned`/`char`/pointer occupy one 16-bit stack slot when evaluated.
- Stack-based evaluation: every expression leaves its result in `x6`. A binary op
  pushes the left operand, evaluates the right into `x6`, pops left into `x5`,
  combines into `x6`.
- Calling convention: caller pushes args right-to-left, `call`, then pops args.
  Result in `a0` (x6). **Every non-leaf function saves/restores `ra` (x1)** — `call`
  clobbers it.
- Frame: `push ra; push s0; mv s0, sp; sub sp for locals`. Param i at `s0+4+2i`;
  local i at `s0-2-2i`. `s0` = x3 = frame pointer.
- Runtime helpers preserve the frame pointer `x3`. `__mul` takes stack args; the
  divide/modulo helpers (`__udivmod`, signed `__div`/`__mod`) take register args
  (`x5`=dividend, `x4`=divisor; result in `x6`, plus `x7`=remainder for `__udivmod`)
  and also preserve `x1`.
- `crt0` sets `sp = 0xF000`, calls `main`, halts via `ecall 0x3FF`.
- MMIO: absolute addresses via integer->pointer cast, e.g. `*(volatile char*)0xF000`.
  Byte access uses `lb`/`lbu`/`sb`; word uses `lw`/`sw`.

## Standard library (source-level, `compiler/lib/`)

`#include` a header-equivalent and call what you need. **Dead-function elimination**
(codegen emits only functions reachable from `main`) means unused entries cost no
code, so pulling in the whole library is free for what you don't call.

- `string.c` — `strlen`, `strcpy`, `strncpy`, `strcat`, `strcmp`, `strncmp`, `strchr`,
  `memcpy`, `memset`, `memcmp`, `memmove`.
- `ctype.c` — `isdigit`, `isalpha`, `isalnum`, `isspace`, `isupper`, `islower`,
  `toupper`, `tolower`.
- `stdlib.c` — `atoi`, `itoa`, `utoa`, `itohex`. (No `printf`: ZC has no varargs, so
  format a number into a buffer, then print it.)
- `stdio.c` — `putstr`, `puts` (appends `\n`), `puthex`. `putchar`/`putint` are
  compiler intrinsics (ECALL), not library functions.
- `libc.c` — `#include`s all of the above (include-once).

## Codegen rules forced by ZX16 (validated against the simulator)

- **Two-operand destructive ALU**: `add rd,rs` => `rd=rd+rs`. Binary ops arrange
  operands first. `slt`/`and`/`or`/`xor`/`sll`/`srl`/`sra` are all two-operand.
- **Branch range +-16 bytes**: `if`/`while` use a short conditional branch over an
  unconditional far jump (`la`+`jr`, unbounded), so bodies of any size work. A direct
  `j` reaches only +-512 bytes, so codegen never emits one.
- **Direct jump/call range +-512 bytes**: codegen always calls via `la`+`jalr`, so a
  function is reachable regardless of distance — required once the program grows large
  (e.g. the self-hosted compiler).
- **Load/store offset +-7 bytes**: larger struct/frame/array offsets are computed
  into a register (`addi` for <=63, `li16`+`add` beyond).
- Compiler-generated labels use a non-dot prefix (dot-labels are directives).

## What "self-hosting + embedded" requires (checklist)

Compiler needs: recursion, calls, `int`/`char`/pointers/arrays/**structs**, globals,
string literals, `if/else`, `while`, comparison/arithmetic operators, character-level
string processing.

Embedded needs: `unsigned`, `char` as true byte, bitwise `& | ^ ~ << >>`,
integer<->pointer casts for MMIO, `volatile` (auto-honored), `asm()` escape hatch,
hex literals.

Both sets are present; neither needs anything dropped. The subset is closed.
