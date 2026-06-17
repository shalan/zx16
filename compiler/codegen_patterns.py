#!/usr/bin/env python3
"""
ZC codegen pattern library for ZX16.

Each function emits a validated assembly fragment for one construct. These are the
building blocks the parser will drive. The patterns encode the hard-won ZX16 rules:

  * Two-operand destructive ALU: `add rd, rs` means rd = rd + rs. Binary ops must
    move/arrange operands first.
  * SLT is two-operand; comparisons either use `mv` then `slt`, or branch directly.
  * `call` clobbers ra (x1): every non-leaf function saves/restores it.
  * Loads/stores have a ±7 byte offset; larger frame offsets need address calc.
  * Branch range ±16 bytes; a direct j/call reaches only ±512 bytes (offset is
    imm[9:1], sign bit 9), so codegen always uses la+jr / la+jalr — distance never
    bounds a jump or call.

Evaluation model (uniform and simple, not optimal):
  Every expression evaluates with its RESULT IN x6. A binary op `L op R`:
      <eval L>            # result in x6
      push x6             # save L on stack
      <eval R>            # result in x6 (= R)
      lw  x5, 0(sp)       # x5 = L
      addi sp, 2          # pop
      <combine x5 (L) and x6 (R) -> x6>

Register roles:
  x6 (a0)  expression result / return value / first arg
  x5 (t1)  scratch for the popped left operand
  x3 (s0)  frame pointer
  x2 (sp)  stack pointer
  x1 (ra)  return address
"""

class Emitter:
    def __init__(self):
        self.lines = []
        self._label_n = 0
        self.loop_stack = []   # stack of (continue_label, break_label)

    def emit(self, s=""):
        self.lines.append(s)

    def label(self, prefix="L"):
        self._label_n += 1
        return f"__{prefix}{self._label_n}"

    def push_loop(self, continue_label, break_label):
        self.loop_stack.append((continue_label, break_label))

    def pop_loop(self):
        self.loop_stack.pop()

    def cur_break(self):
        if not self.loop_stack:
            raise SyntaxError("break outside loop")
        return self.loop_stack[-1][1]

    def cur_continue(self):
        if not self.loop_stack:
            raise SyntaxError("continue outside loop")
        return self.loop_stack[-1][0]

    def text(self):
        return "\n".join(self.lines) + "\n"

# ---------------------------------------------------------------------------
# Primitive value loads (result -> x6)
# ---------------------------------------------------------------------------

def load_const(e, n):
    """Load integer constant into x6."""
    n &= 0xFFFF
    sn = n - 0x10000 if n >= 0x8000 else n
    if -64 <= sn <= 63:
        e.emit(f"    li x6, {sn}")
    else:
        hi = n >> 7
        lo = n & 0x7F
        e.emit(f"    lui x6, {hi}")
        if lo:
            e.emit(f"    ori x6, {lo}")

def push_x6(e):
    e.emit("    push x6")

def pop_to(e, reg):
    e.emit(f"    lw {reg}, 0(x2)")
    e.emit("    addi x2, 2")

# ---------------------------------------------------------------------------
# Binary operators: left in x5, right in x6, result -> x6
# ---------------------------------------------------------------------------

def bin_op(e, op, runtime_calls):
    """Combine x5 (left) and x6 (right) per `op`, result in x6.
    runtime_calls: set True to use __mul/__div/__mod helpers."""
    if op == '+':
        e.emit("    add x5, x6")       # x5 = L + R
        e.emit("    mv x6, x5")
    elif op == '-':
        e.emit("    sub x5, x6")       # x5 = L - R
        e.emit("    mv x6, x5")
    elif op == '*':
        # __mul(a,b): push b, push a
        e.emit("    push x6")          # b = R
        e.emit("    push x5")          # a = L
        e.emit("    la x4, __mul")
        e.emit("    jalr x1, x4")
        e.emit("    addi x2, 4")
    elif op == '/':
        e.emit("    push x6")
        e.emit("    push x5")
        e.emit("    la x4, __div")
        e.emit("    jalr x1, x4")
        e.emit("    addi x2, 4")
    elif op == '%':
        e.emit("    push x6")
        e.emit("    push x5")
        e.emit("    la x4, __mod")
        e.emit("    jalr x1, x4")
        e.emit("    addi x2, 4")
    elif op in ('<', '>', '<=', '>=', '==', '!='):
        # produce 0/1 in x6 using branches
        t = e.label("cmp")
        d = e.label("cmpd")
        # arrange: compare L (x5) ? R (x6)
        if op == '<':   e.emit(f"    blt x5, x6, {t}")
        elif op == '>': e.emit(f"    blt x6, x5, {t}")
        elif op == '<=':e.emit(f"    bge x6, x5, {t}")
        elif op == '>=':e.emit(f"    bge x5, x6, {t}")
        elif op == '==':e.emit(f"    beq x5, x6, {t}")
        elif op == '!=':e.emit(f"    bne x5, x6, {t}")
        e.emit("    li x6, 0")
        e.emit(f"    j {d}")
        e.emit(f"{t}:")
        e.emit("    li x6, 1")
        e.emit(f"{d}:")
    else:
        raise ValueError(f"unknown op {op}")

def unary_neg(e):
    """x6 = -x6"""
    e.emit("    xori x6, -1")
    e.emit("    addi x6, 1")

def unary_not(e):
    """logical not: x6 = (x6 == 0) ? 1 : 0"""
    t = e.label("not"); d = e.label("notd")
    e.emit(f"    bz x6, {t}")
    e.emit("    li x6, 0")
    e.emit(f"    j {d}")
    e.emit(f"{t}:")
    e.emit("    li x6, 1")
    e.emit(f"{d}:")

# ---------------------------------------------------------------------------
# Control flow
# ---------------------------------------------------------------------------

def far_jump(e, label):
    """Unconditional jump of unbounded distance. Direct `j` only reaches +-512
    bytes, which a large function body exceeds; la+jr is unbounded. Uses x4 scratch."""
    e.emit(f"    la x4, {label}")
    e.emit(f"    jr x4")

def if_then_else(e, gen_cond, gen_then, gen_else=None):
    """if (cond) then [else]. gen_* are callables that emit into e.
    Uses short-branch-over-far-jump so arbitrarily long bodies AND distances work."""
    end_l = e.label("endif")
    gen_cond(e)                 # result in x6
    if gen_else:
        else_l = e.label("else")
        then_l = e.label("then")
        e.emit(f"    bnz x6, {then_l}")
        far_jump(e, else_l)
        e.emit(f"{then_l}:")
        gen_then(e)
        far_jump(e, end_l)
        e.emit(f"{else_l}:")
        gen_else(e)
        e.emit(f"{end_l}:")
    else:
        then_l = e.label("then")
        e.emit(f"    bnz x6, {then_l}")
        far_jump(e, end_l)
        e.emit(f"{then_l}:")
        gen_then(e)
        e.emit(f"{end_l}:")

def while_loop(e, gen_cond, gen_body):
    # Short conditional branch to enter the body; far jumps for exit and back-edge,
    # since the body can be larger than the +-512 byte direct-jump range.
    top = e.label("while")
    end = e.label("wend")
    skip = e.label("wbody")
    e.push_loop(top, end)         # continue target = top, break target = end
    e.emit(f"{top}:")
    gen_cond(e)                     # result in x6
    e.emit(f"    bnz x6, {skip}")   # short branch: enter body
    far_jump(e, end)                # exit loop (far)
    e.emit(f"{skip}:")
    gen_body(e)
    far_jump(e, top)                # back-edge (far)
    e.emit(f"{end}:")
    e.pop_loop()

def emit_break(e):
    far_jump(e, e.cur_break())

def emit_continue(e):
    far_jump(e, e.cur_continue())

# ---------------------------------------------------------------------------
# Function prologue / epilogue
# ---------------------------------------------------------------------------

def func_prologue(e, name, n_locals):
    e.emit(f"{name}:")
    e.emit("    push x1")        # save ra (clobbered by any call)
    e.emit("    push x3")        # save caller's frame pointer
    e.emit("    mv x3, x2")      # s0 = sp  (frame base = saved old s0)
    if n_locals:
        e.emit(f"    addi x2, {-2*n_locals}")  # allocate locals

def func_epilogue(e):
    e.emit("    mv x2, x3")      # free locals
    e.emit("    pop x3")         # restore frame pointer
    e.emit("    pop x1")         # restore ra
    e.emit("    ret")

def local_addr_offset(i):
    """byte offset of local i relative to s0 (negative)."""
    return -2 - 2*i

def param_addr_offset(i):
    """byte offset of param i relative to s0 (positive: above saved s0/ra)."""
    return 4 + 2*i

def load_local(e, i):
    off = local_addr_offset(i)
    if -8 <= off <= 7:
        e.emit(f"    lw x6, {off}(x3)")
    else:
        e.emit("    mv x6, x3")
        e.emit(f"    addi x6, {off}")    # may itself overflow imm; codegen will split
        e.emit("    lw x6, 0(x6)")

def store_local(e, i):
    """store x6 into local i."""
    off = local_addr_offset(i)
    if -8 <= off <= 7:
        e.emit(f"    sw x6, {off}(x3)")
    else:
        e.emit("    mv x5, x3")
        e.emit(f"    addi x5, {off}")
        e.emit("    sw x6, 0(x5)")

def call_function(e, name, n_args):
    """Args already pushed right-to-left. Uses a far-call (la + jalr) so the target
    is reachable regardless of distance — a direct `call` (JAL) only reaches ±512 bytes,
    which a large program (e.g. the self-hosted compiler) exceeds. Result in x6.
    x5 is scratch (the evaluation model treats it as clobberable across a call)."""
    e.emit(f"    la x5, {name}")
    e.emit("    jalr x1, x5")
    if n_args:
        e.emit(f"    addi x2, {2*n_args}")

def return_value(e):
    """expression result already in x6; jump to epilogue handled by caller."""
    pass

# ---------------------------------------------------------------------------
# Member / pointer / array address computation
# ---------------------------------------------------------------------------

def addr_plus_offset(e, base_reg, off, dst_reg):
    """dst_reg = base_reg + off, choosing the cheapest sequence.
    Leaves an address in dst_reg suitable for 0(dst_reg) access."""
    if off == 0 and dst_reg == base_reg:
        return
    if -64 <= off <= 63:
        if dst_reg != base_reg:
            e.emit(f"    mv {dst_reg}, {base_reg}")
        if off:
            e.emit(f"    addi {dst_reg}, {off}")
    else:
        e.emit(f"    li16 {dst_reg}, {off & 0xFFFF}")
        e.emit(f"    add {dst_reg}, {base_reg}")

def load_word_at(e, base_reg, off, dst="x6"):
    """dst = *(int*)(base_reg + off)"""
    if -8 <= off <= 7:
        e.emit(f"    lw {dst}, {off}({base_reg})")
    else:
        addr_plus_offset(e, base_reg, off, "x5")
        e.emit(f"    lw {dst}, 0(x5)")

def store_word_at(e, base_reg, off, src="x6"):
    """*(int*)(base_reg + off) = src"""
    if -8 <= off <= 7:
        e.emit(f"    sw {src}, {off}({base_reg})")
    else:
        addr_plus_offset(e, base_reg, off, "x5")
        e.emit(f"    sw {src}, 0(x5)")

def load_byte_at(e, base_reg, off, dst="x6", signed=True):
    op = "lb" if signed else "lbu"
    if -8 <= off <= 7:
        e.emit(f"    {op} {dst}, {off}({base_reg})")
    else:
        addr_plus_offset(e, base_reg, off, "x5")
        e.emit(f"    {op} {dst}, 0(x5)")

def store_byte_at(e, base_reg, off, src="x6"):
    if -8 <= off <= 7:
        e.emit(f"    sb {src}, {off}({base_reg})")
    else:
        addr_plus_offset(e, base_reg, off, "x5")
        e.emit(f"    sb {src}, 0(x5)")

# ---------------------------------------------------------------------------
# Bitwise + shift ops (single ZX16 instructions): left x5, right x6 -> x6
# ---------------------------------------------------------------------------

def bit_op(e, op):
    if op == '&':
        e.emit("    and x5, x6"); e.emit("    mv x6, x5")
    elif op == '|':
        e.emit("    or x5, x6");  e.emit("    mv x6, x5")
    elif op == '^':
        e.emit("    xor x5, x6"); e.emit("    mv x6, x5")
    elif op == '<<':
        # shift amount in x6, value in x5  -> x5 << x6
        e.emit("    sll x5, x6"); e.emit("    mv x6, x5")
    elif op == '>>':
        e.emit("    srl x5, x6"); e.emit("    mv x6, x5")   # logical (unsigned)
    elif op == '>>s':
        e.emit("    sra x5, x6"); e.emit("    mv x6, x5")   # arithmetic (signed)
    else:
        raise ValueError(f"unknown bit op {op}")

def bit_not(e):
    """x6 = ~x6"""
    e.emit("    xori x6, -1")

# unsigned comparison variants (left x5, right x6 -> 0/1 in x6)
def cmp_unsigned(e, op):
    t = e.label("ucmp"); d = e.label("ucmpd")
    if op == '<':    e.emit(f"    bltu x5, x6, {t}")
    elif op == '>':  e.emit(f"    bltu x6, x5, {t}")
    elif op == '<=': e.emit(f"    bgeu x6, x5, {t}")
    elif op == '>=': e.emit(f"    bgeu x5, x6, {t}")
    else: raise ValueError(op)
    e.emit("    li x6, 0"); e.emit(f"    j {d}")
    e.emit(f"{t}:"); e.emit("    li x6, 1"); e.emit(f"{d}:")

def load_abs_addr(e, addr, dst="x6"):
    """dst = constant absolute address (for (int*)0xF000 style casts)."""
    e.emit(f"    li16 {dst}, {addr & 0xFFFF}")

def emit_asm(e, text):
    """asm("...") passthrough: emit verbatim."""
    for line in text.splitlines():
        e.emit("    " + line.strip())

# ---------------------------------------------------------------------------
# Program skeleton
# ---------------------------------------------------------------------------

def crt0(e):
    e.emit(".text")
    e.emit(".org 0x0020")
    e.emit("__start:")
    e.emit("    li16 x2, 0xF000")
    e.emit("    la x5, main")
    e.emit("    jalr x1, x5")
    e.emit("    ecall 0x3FF")

def runtime(e):
    # Helpers preserve x3 and x4 (callee-saved: x3 is the caller's frame pointer).
    # They read args relative to a temporarily adjusted view of the stack.
    # On entry [sp]=a, [sp+2]=b. After we push x3,x4 the args shift by 4.
    e.emit("__mul:")
    e.emit("    push x3")
    e.emit("    push x4")
    e.emit("    lw x3, 4(x2)")     # a  (args shifted by the 2 pushes = 4 bytes)
    e.emit("    lw x4, 6(x2)")     # b
    e.emit("    li x6, 0")
    e.emit("__mul_lp:")
    e.emit("    bz x3, __mul_done")
    e.emit("    add x6, x4")
    e.emit("    addi x3, -1")
    e.emit("    j __mul_lp")
    e.emit("__mul_done:")
    e.emit("    pop x4")
    e.emit("    pop x3")
    e.emit("    ret")
    e.emit("__div:")
    e.emit("    push x3")
    e.emit("    push x4")
    e.emit("    lw x3, 4(x2)")
    e.emit("    lw x4, 6(x2)")
    e.emit("    li x6, 0")
    e.emit("__div_lp:")
    e.emit("    blt x3, x4, __div_done")
    e.emit("    sub x3, x4")
    e.emit("    addi x6, 1")
    e.emit("    j __div_lp")
    e.emit("__div_done:")
    e.emit("    pop x4")
    e.emit("    pop x3")
    e.emit("    ret")
    e.emit("__mod:")
    e.emit("    push x3")
    e.emit("    push x4")
    e.emit("    lw x3, 4(x2)")
    e.emit("    lw x4, 6(x2)")
    e.emit("__mod_lp:")
    e.emit("    blt x3, x4, __mod_done")
    e.emit("    sub x3, x4")
    e.emit("    j __mod_lp")
    e.emit("__mod_done:")
    e.emit("    mv x6, x3")
    e.emit("    pop x4")
    e.emit("    pop x3")
    e.emit("    ret")
