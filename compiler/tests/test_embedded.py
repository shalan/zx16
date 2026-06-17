#!/usr/bin/env python3
"""Compile and verify the embedded C examples end-to-end.
Each case checks printed output and, where relevant, the MMIO write log and
final register state — the things that make these genuinely 'embedded'."""
import os, sys
_HERE = os.path.dirname(os.path.abspath(__file__))
_COMPILER = os.path.dirname(_HERE)
sys.path.insert(0, _COMPILER)
sys.path.insert(0, os.path.join(os.path.dirname(_COMPILER), "simulator"))

import importlib
import codegen_patterns, zcc, codegen
importlib.reload(codegen_patterns); importlib.reload(zcc); importlib.reload(codegen)
import zx16sim as Z

def compile_run(path, pre_run=None):
    asm=codegen.compile_src(open(os.path.join(_COMPILER, path)).read())
    out,sim=Z.assemble_and_run(asm, pre_run=pre_run)
    return asm, [v for k,v in out], sim

results=[]
def check(name, cond, detail=""):
    results.append((name,cond,detail))
    print(f"{'PASS' if cond else 'FAIL'} {name}" + (f"  [{detail}]" if detail and not cond else ""))

# Ex1: GPIO bit set/clear -> final register 0x20, write sequence correct
_,out,sim=compile_run('examples/01_gpio_set.c')
writes=[(a,v) for a,v,s in sim.mmio_writes]
check("01_gpio set/clear bits",
      sim.lw(0xF010)==0x20 and writes==[(0xF010,0),(0xF010,0x08),(0xF010,0x28),(0xF010,0x20)],
      f"final={hex(sim.lw(0xF010))} writes={[(hex(a),hex(v)) for a,v in writes]}")

# Ex2: poll until READY then read data=99; READY appears on 3rd status read
def setup2(sim):
    sim.mmio_read_script[0xF020]=[0,0,1]
    sim.mmio_regs[0xF021]=99
_,out,sim=compile_run('examples/02_poll_status.c', setup2)
check("02_poll_status waits for READY then reads", out==[99], f"out={out}")

# Ex3: timer register map; writes to correct offsets, reads back ctrl & count
_,out,sim=compile_run('examples/03_reg_map.c')
w={a:v for a,v,s in sim.mmio_writes}
check("03_reg_map struct field offsets",
      out==[5,1000] and w.get(0xF030)==5 and w.get(0xF032)==1000 and w.get(0xF034)==1000,
      f"out={out} writes={ {hex(a):hex(v) for a,v in w.items()} }")

# Ex4: XOR checksum of {0x12,0x34,0x56,0x78} = 0x08
_,out,sim=compile_run('examples/04_checksum.c')
check("04_checksum xor over byte buffer", out==[0x12^0x34^0x56^0x78], f"out={out}")

# Ex5: ring buffer push/pop ordering with wrap mask
_,out,sim=compile_run('examples/05_ring_buffer.c')
check("05_ring_buffer FIFO order + empty sentinel", out==[10,20,30,40,-1], f"out={out}")

# Ex6: TEA cipher (struct globals) -> matches a reference 32-bit TEA exactly.
# Regression for the struct-global under-allocation fix (printed values are s16).
_,out,sim=compile_run('examples/07_tea.c')
check("07_tea struct-global cipher vs reference",
      out==[-31852,-1131,-29271,-25717], f"out={out}")

# Ex7: MD5 of "abc" -> 900150983cd24fb0d6963f7d28e17f72 (matches hashlib)
_,out,sim=compile_run('examples/08_md5.c')
check("08_md5 \"abc\" digest vs reference",
      [v & 0xFFFF for v in out]==[0x9850,0x0190,0xb04f,0xd23c,0x7d3f,0x96d6,0x727f,0xe128],
      f"out={[hex(v & 0xFFFF) for v in out]}")

# Ex8: radix-2 fixed-point FFT, N=8 -> matches the integer reference model
_,out,sim=compile_run('examples/09_fft.c')
check("09_fft N=8 fixed-point vs reference",
      out==[28,0,-4,9,-4,4,-4,1,-4,0,-4,-1,-4,-4,-4,-9], f"out={out}")

n=sum(1 for _,c,_ in results if c)
print(f"\n{n}/{len(results)} embedded examples verified correct")
