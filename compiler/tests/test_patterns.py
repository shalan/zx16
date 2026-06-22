#!/usr/bin/env python3
"""Regression tests for the ZC codegen pattern library.
Each test builds a program through codegen_patterns, runs it on the ZX16 sim,
and checks the printed output. Run: python3 test_patterns.py
"""
import os, sys
_HERE = os.path.dirname(os.path.abspath(__file__))
_COMPILER = os.path.dirname(_HERE)
sys.path.insert(0, _COMPILER)
sys.path.insert(0, os.path.join(os.path.dirname(_COMPILER), "simulator"))

import importlib
import codegen_patterns as C
import zx16sim as Z

def run(asm):
    out, sim = Z.assemble_and_run(asm)
    return out

def t_arith():
    # (2+3)*(10-6) = 20
    e = C.Emitter(); C.crt0(e); C.runtime(e)
    C.func_prologue(e, "main", 0)
    C.load_const(e, 2); C.push_x6(e); C.load_const(e, 3)
    C.pop_to(e, "x5"); C.bin_op(e, '+', True)        # 5
    C.push_x6(e)
    C.load_const(e, 10); C.push_x6(e); C.load_const(e, 6)
    C.pop_to(e, "x5"); C.bin_op(e, '-', True)        # 4
    C.pop_to(e, "x5"); C.bin_op(e, '*', True)        # 5*4=20
    e.emit("    ecall 0x000"); C.func_epilogue(e)
    assert run(e.text()) == [('int', 20)]

def t_divmod():
    e = C.Emitter(); C.crt0(e); C.runtime(e)
    C.func_prologue(e, "main", 0)
    C.load_const(e, 23); C.push_x6(e); C.load_const(e, 4)
    C.pop_to(e, "x5"); C.div_op(e, False)            # 5
    e.emit("    ecall 0x000")
    C.load_const(e, 23); C.push_x6(e); C.load_const(e, 4)
    C.pop_to(e, "x5"); C.mod_op(e, False)            # 3
    e.emit("    ecall 0x000"); C.func_epilogue(e)
    assert run(e.text()) == [('int', 5), ('int', 3)]

def t_recursion():
    e = C.Emitter(); C.crt0(e); C.runtime(e)
    C.func_prologue(e, "fact", 0)
    e.emit("    lw x6, 4(x3)"); C.push_x6(e)
    C.load_const(e, 2); C.pop_to(e, "x5"); C.bin_op(e, '<', True)
    els = e.label("else")
    e.emit(f"    bz x6, {els}")
    C.load_const(e, 1)
    e.emit("    mv x2, x3"); e.emit("    pop x3"); e.emit("    pop x1"); e.emit("    ret")
    e.emit(f"{els}:")
    e.emit("    lw x6, 4(x3)"); C.push_x6(e)
    e.emit("    lw x6, 4(x3)"); e.emit("    addi x6, -1"); C.push_x6(e)
    C.call_function(e, "fact", 1)
    C.pop_to(e, "x5"); C.bin_op(e, '*', True)
    C.func_epilogue(e)
    C.func_prologue(e, "main", 0)
    C.load_const(e, 5); C.push_x6(e); C.call_function(e, "fact", 1)
    e.emit("    ecall 0x000"); C.func_epilogue(e)
    assert run(e.text()) == [('int', 120)]

def t_while():
    e = C.Emitter(); C.crt0(e); C.runtime(e)
    C.func_prologue(e, "main", 2)
    C.load_const(e, 1); C.store_local(e, 0)
    C.load_const(e, 0); C.store_local(e, 1)
    def cond(e):
        C.load_local(e, 0); C.push_x6(e)
        C.load_const(e, 10); C.pop_to(e, "x5"); C.bin_op(e, '<=', True)
    def body(e):
        C.load_local(e, 1); C.push_x6(e)
        C.load_local(e, 0); C.pop_to(e, "x5"); C.bin_op(e, '+', True)
        C.store_local(e, 1)
        C.load_local(e, 0); C.push_x6(e)
        C.load_const(e, 1); C.pop_to(e, "x5"); C.bin_op(e, '+', True)
        C.store_local(e, 0)
    C.while_loop(e, cond, body)
    C.load_local(e, 1); e.emit("    ecall 0x000"); C.func_epilogue(e)
    assert run(e.text()) == [('int', 55)]

def t_ifelse():
    # print max(8,5) using if/else -> 8
    e = C.Emitter(); C.crt0(e); C.runtime(e)
    C.func_prologue(e, "main", 1)
    def cond(e):
        C.load_const(e, 8); C.push_x6(e)
        C.load_const(e, 5); C.pop_to(e, "x5"); C.bin_op(e, '>', True)
    def then(e):
        C.load_const(e, 8); C.store_local(e, 0)
    def els(e):
        C.load_const(e, 5); C.store_local(e, 0)
    C.if_then_else(e, cond, then, els)
    C.load_local(e, 0); e.emit("    ecall 0x000"); C.func_epilogue(e)
    assert run(e.text()) == [('int', 8)]

def t_bigconst():
    e = C.Emitter(); C.crt0(e); C.runtime(e)
    C.func_prologue(e, "main", 0)
    C.load_const(e, 1000); e.emit("    ecall 0x000")
    C.load_const(e, -5); e.emit("    ecall 0x000")
    C.func_epilogue(e)
    assert run(e.text()) == [('int', 1000), ('int', -5)]

def t_bitwise():
    # (1<<3)|(1<<0)=9 ; 0xFF & 0x0F = 15 ; 0xF0 ^ 0xFF = 0x0F ; ~0 = -1
    e = C.Emitter(); C.crt0(e); C.runtime(e)
    C.func_prologue(e, "main", 0)
    C.load_const(e, 1); C.push_x6(e); C.load_const(e, 3)
    C.pop_to(e, "x5"); C.bit_op(e, '<<'); C.push_x6(e)
    C.load_const(e, 1); C.push_x6(e); C.load_const(e, 0)
    C.pop_to(e, "x5"); C.bit_op(e, '<<')
    C.pop_to(e, "x5"); C.bit_op(e, '|'); e.emit("    ecall 0x000")   # 9
    C.load_const(e, 0xFF); C.push_x6(e); C.load_const(e, 0x0F)
    C.pop_to(e, "x5"); C.bit_op(e, '&'); e.emit("    ecall 0x000")   # 15
    C.load_const(e, 0xF0); C.push_x6(e); C.load_const(e, 0xFF)
    C.pop_to(e, "x5"); C.bit_op(e, '^'); e.emit("    ecall 0x000")   # 15
    C.load_const(e, 0); C.bit_not(e); e.emit("    ecall 0x000")      # -1
    C.func_epilogue(e)
    assert run(e.text()) == [('int',9),('int',15),('int',15),('int',-1)]

def t_struct():
    # struct at 0x9100: write fields (incl. out-of-range offset), read back
    e = C.Emitter(); C.crt0(e); C.runtime(e)
    C.func_prologue(e, "main", 0)
    C.load_abs_addr(e, 0x9100, "x4")
    C.load_const(e, 17);  C.store_word_at(e, "x4", 0, "x6")   # field@0
    C.load_const(e, 51);  C.store_word_at(e, "x4", 4, "x6")   # field@4
    C.load_const(e, 92);  C.store_word_at(e, "x4", 200, "x6") # field@200 (far)
    C.load_word_at(e, "x4", 0, "x6");   e.emit("    ecall 0x000")
    C.load_word_at(e, "x4", 4, "x6");   e.emit("    ecall 0x000")
    C.load_word_at(e, "x4", 200, "x6"); e.emit("    ecall 0x000")
    C.func_epilogue(e)
    assert run(e.text()) == [('int',17),('int',51),('int',92)]

def t_unsigned_cmp():
    # 0xF000 vs 0x0010: unsigned, 0xF000 > 0x0010 (signed it'd be negative<positive)
    e = C.Emitter(); C.crt0(e); C.runtime(e)
    C.func_prologue(e, "main", 0)
    C.load_const(e, 0xF000); C.push_x6(e); C.load_const(e, 0x0010)
    C.pop_to(e, "x5"); C.cmp_unsigned(e, '>'); e.emit("    ecall 0x000")  # 1
    C.func_epilogue(e)
    assert run(e.text()) == [('int',1)]

def t_break_nested():
    # nested loops; inner break must exit inner only -> sum = 0+1+2 = 3
    e = C.Emitter(); C.crt0(e); C.runtime(e)
    C.func_prologue(e, "main", 3)
    C.load_const(e,0); C.store_local(e,0)
    C.load_const(e,1); C.store_local(e,1)
    def oc(e):
        C.load_local(e,1); C.push_x6(e); C.load_const(e,3); C.pop_to(e,"x5"); C.bin_op(e,'<=',True)
    def ob(e):
        C.load_const(e,1); C.store_local(e,2)
        def ic(e):
            C.load_local(e,2); C.push_x6(e); C.load_const(e,100); C.pop_to(e,"x5"); C.bin_op(e,'<=',True)
        def ib(e):
            def c(e):
                C.load_local(e,2); C.push_x6(e); C.load_local(e,1); C.pop_to(e,"x5"); C.bin_op(e,'==',True)
            C.if_then_else(e, c, lambda e: C.emit_break(e), None)
            C.load_local(e,0); C.push_x6(e); C.load_const(e,1); C.pop_to(e,"x5"); C.bin_op(e,'+',True); C.store_local(e,0)
            C.load_local(e,2); C.push_x6(e); C.load_const(e,1); C.pop_to(e,"x5"); C.bin_op(e,'+',True); C.store_local(e,2)
        C.while_loop(e, ic, ib)
        C.load_local(e,1); C.push_x6(e); C.load_const(e,1); C.pop_to(e,"x5"); C.bin_op(e,'+',True); C.store_local(e,1)
    C.while_loop(e, oc, ob)
    C.load_local(e,0); e.emit("    ecall 0x000"); C.func_epilogue(e)
    assert run(e.text()) == [('int',3)]

def t_continue():
    # count odds in 1..10 via continue -> 5
    e = C.Emitter(); C.crt0(e); C.runtime(e)
    C.func_prologue(e, "main", 2)
    C.load_const(e,0); C.store_local(e,0)
    C.load_const(e,0); C.store_local(e,1)
    def cond(e):
        C.load_local(e,1); C.push_x6(e); C.load_const(e,10); C.pop_to(e,"x5"); C.bin_op(e,'<',True)
    def body(e):
        C.load_local(e,1); C.push_x6(e); C.load_const(e,1); C.pop_to(e,"x5"); C.bin_op(e,'+',True); C.store_local(e,1)
        def c(e):
            C.load_local(e,1); C.push_x6(e); C.load_const(e,2); C.pop_to(e,"x5"); C.mod_op(e,False)
            C.push_x6(e); C.load_const(e,0); C.pop_to(e,"x5"); C.bin_op(e,'==',True)
        C.if_then_else(e, c, lambda e: C.emit_continue(e), None)
        C.load_local(e,0); C.push_x6(e); C.load_const(e,1); C.pop_to(e,"x5"); C.bin_op(e,'+',True); C.store_local(e,0)
    C.while_loop(e, cond, body)
    C.load_local(e,0); e.emit("    ecall 0x000"); C.func_epilogue(e)
    assert run(e.text()) == [('int',5)]

if __name__ == '__main__':
    tests = [t_arith, t_divmod, t_recursion, t_while, t_ifelse, t_bigconst,
             t_bitwise, t_struct, t_unsigned_cmp, t_break_nested, t_continue]
    passed = 0
    for t in tests:
        try:
            t(); print(f"PASS {t.__name__}"); passed += 1
        except AssertionError as ex:
            print(f"FAIL {t.__name__}: {ex}")
        except Exception as ex:
            print(f"ERROR {t.__name__}: {ex}")
    print(f"\n{passed}/{len(tests)} patterns validated")
