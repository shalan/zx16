#!/usr/bin/env python3
"""
ZC codegen walk: AST (from zcc.Parser) -> ZX16 assembly, via codegen_patterns.

Conventions:
  - Every rvalue expression evaluates with result in x6.
  - Every lvalue evaluates its ADDRESS into x6 (gen_addr).
  - Locals/params live in the frame; globals/strings in labeled memory.
  - Types are tracked enough to choose signed/unsigned compares & shifts, byte vs
    word access, and pointer arithmetic scaling.
"""
import codegen_patterns as C
import zcc

WORD = 2

class CodegenError(Exception): pass

class Func:
    def __init__(self, name):
        self.name=name
        self.slots={}      # varname -> (frame_index, type)  (locals + params unified)
        self.n_locals=0
        self.param_order=[] # names in order

class Codegen:
    def __init__(self, parser):
        self.P=parser
        self.e=C.Emitter()
        self.strings=[]      # list of (label, text)
        self.global_syms={}  # name -> (label, type, arrlen)
        self.cur=None        # current Func
        self.func_types={}   # fname -> return type

    # ---------- type helpers ----------
    def is_unsigned(self, t):
        return t is not None and t.get('ptr',0)==0 and t['base'] in ('unsigned','uchar')
    def is_byte(self, t):
        return t is not None and t.get('ptr',0)==0 and t['base'] in ('char','uchar')
    def is_ptr(self, t):
        return t is not None and t.get('ptr',0)>0
    def elem_type(self, t):
        # type pointed to / element type
        return {'base':t['base'],'ptr':t['ptr']-1} if t['ptr']>0 else t
    def type_size(self,t): return self.P.type_size(t)
    def elem_size(self, t):
        # size of what a pointer/array element addresses
        if t['ptr']>1: return WORD
        if t['ptr']==1:
            b=t['base']
            if b in ('char','uchar'): return 1
            if b in ('int','unsigned'): return 2
            if isinstance(b,tuple): return self.P.structs[b[1]]['size']
            return 2
        return self.type_size(t)

    # ---------- program ----------
    def gen_program(self):
        e=self.e
        C.crt0(e)
        C.runtime(e)
        # globals storage
        for (name,ty,arrlen,init) in self.P.globals:
            label=f"g_{name}"
            self.global_syms[name]=(label,ty,arrlen)
        # functions
        for fidx in self.P.funcs:
            fn=self.P.nodes[fidx]
            self.func_types[fn['name']]=fn['ret']
        for fidx in self.P.funcs:
            self.gen_func(fidx)
        # data section
        e.emit(".data")
        for (name,ty,arrlen,init) in self.P.globals:
            label=f"g_{name}"
            if arrlen:
                e.emit(f"{label}: .space {self.type_size(ty)*arrlen}")
            else:
                sz=self.type_size(ty)
                if sz<=WORD:
                    # scalar (int/unsigned/char/pointer): one word, constant init
                    e.emit(f"{label}: .word {init if init is not None else 0}")
                else:
                    # struct (or any multi-word) global: reserve its FULL size,
                    # word-rounded. This branch previously also emitted a single
                    # .word, so struct globals were under-allocated to 2 bytes and
                    # overlapped the next global (A.hi aliased B.lo) -- the actual
                    # cause of the TEA failure (misattributed to evaluation order).
                    e.emit(f"{label}: .space {(sz+WORD-1)//WORD*WORD}")
        for (label,text) in self.strings:
            data=','.join(str(ord(c)) for c in text)+',0'
            e.emit(f"{label}: .byte {data}")
        return e.text()

    # ---------- functions ----------
    def collect_locals(self, idx, fn):
        n=self.P.nodes[idx]; op=n['op']
        if op=='block':
            for s in n['stmts']: self.collect_locals(s,fn)
        elif op=='if':
            self.collect_locals(n['then'],fn)
            if n['els'] is not None: self.collect_locals(n['els'],fn)
        elif op=='while':
            self.collect_locals(n['body'],fn)
        elif op=='vardecl':
            if n['arrlen']:
                nslots=(self.type_size(n['vtype'])*n['arrlen']+WORD-1)//WORD
            else:
                # scalars are 1 word; structs occupy ceil(size/word) words
                nslots=(self.type_size(n['vtype'])+WORD-1)//WORD
            base_index=fn.n_locals
            fn.slots[n['name']]=(base_index, n['vtype'], n['arrlen'])
            fn.n_locals+=nslots

    def gen_func(self, fidx):
        fn=self.P.nodes[fidx]
        f=Func(fn['name']); self.cur=f
        # params occupy positive offsets; record them
        for i,(pname,pty) in enumerate(fn['params']):
            f.slots[pname]=('param',i,pty)
            f.param_order.append(pname)
        # collect locals to size the frame
        self.collect_locals(fn['body'], f)
        C.func_prologue(self.e, fn['name'], f.n_locals)
        self.epilogue_label=self.e.label("epi")
        self.gen_stmt(fn['body'])
        self.e.emit(f"{self.epilogue_label}:")
        C.func_epilogue(self.e)
        self.cur=None

    # ---------- statements ----------
    def gen_stmt(self, idx):
        n=self.P.nodes[idx]; op=n['op']; e=self.e
        if op=='block':
            for s in n['stmts']: self.gen_stmt(s)
        elif op=='vardecl':
            if n['init'] is not None:
                self.gen_expr(n['init'])
                self.store_to_var(n['name'])
        elif op=='exprstmt':
            self.gen_expr(n['expr'])
        elif op=='return':
            if n['val'] is not None: self.gen_expr(n['val'])
            C.far_jump(e, self.epilogue_label)
        elif op=='if':
            gc=lambda e: self.gen_expr(n['cond'])
            gt=lambda e: self.gen_stmt(n['then'])
            ge=(lambda e: self.gen_stmt(n['els'])) if n['els'] is not None else None
            C.if_then_else(e, gc, gt, ge)
        elif op=='while':
            gc=lambda e: self.gen_expr(n['cond'])
            gb=lambda e: self.gen_stmt(n['body'])
            C.while_loop(e, gc, gb)
        elif op=='break':
            C.emit_break(e)
        elif op=='continue':
            C.emit_continue(e)
        elif op=='asm':
            C.emit_asm(e, n['text'])
        else:
            raise CodegenError(f"stmt op {op}")

    # ---------- variable access ----------
    def var_info(self, name):
        f=self.cur
        if name in f.slots:
            return ('local', f.slots[name])
        if name in self.global_syms:
            return ('global', self.global_syms[name])
        raise CodegenError(f"undefined variable {name}")

    def var_type(self, name):
        kind,info=self.var_info(name)
        if kind=='local':
            if info[0]=='param': return info[2]
            return info[1]
        return info[1]

    def gen_var_addr(self, name, dst="x6"):
        """address of variable -> dst"""
        kind,info=self.var_info(name)
        e=self.e
        if kind=='local':
            if info[0]=='param':
                off=C.param_addr_offset(info[1])
            else:
                base_index=info[0]; arrlen=info[2]; vtype=info[1]
                if arrlen:
                    # array occupies slots [base_index .. base_index+nslots-1];
                    # element 0 sits at the most-negative offset so a[k]=base+2k
                    nslots=(self.type_size(vtype)*arrlen+WORD-1)//WORD
                    off=C.local_addr_offset(base_index+nslots-1)
                else:
                    # struct fields grow upward from the most-negative slot
                    nslots=(self.type_size(vtype)+WORD-1)//WORD
                    off=C.local_addr_offset(base_index+nslots-1)
            C.addr_plus_offset(e, "x3", off, dst)
        else:
            label=info[0]
            e.emit(f"    la {dst}, {label}")

    def load_from_var(self, name):
        ty=self.var_type(name)
        # arrays evaluate to their address
        kind,info=self.var_info(name)
        is_array = (kind=='local' and info[0]!='param' and info[2]) or (kind=='global' and info[2])
        if is_array:
            self.gen_var_addr(name,"x6"); return ty
        self.gen_var_addr(name,"x5")
        if self.is_byte(ty):
            self.e.emit(f"    {'lbu' if self.is_unsigned(ty) else 'lb'} x6, 0(x5)")
        else:
            self.e.emit("    lw x6, 0(x5)")
        return ty

    def store_to_var(self, name):
        """value in x6 -> variable"""
        ty=self.var_type(name)
        self.e.emit("    push x6")          # save value
        self.gen_var_addr(name,"x5")
        self.e.emit("    lw x6, 0(x2)")     # restore value
        self.e.emit("    addi x2, 2")
        if self.is_byte(ty):
            self.e.emit("    sb x6, 0(x5)")
        else:
            self.e.emit("    sw x6, 0(x5)")

    # ---------- expressions (result -> x6); returns type ----------
    def gen_expr(self, idx):
        n=self.P.nodes[idx]; op=n['op']; e=self.e
        if op=='intlit':
            C.load_const(e, n['val']); return {'base':'int','ptr':0}
        if op=='charlit':
            C.load_const(e, n['val']); return {'base':'char','ptr':0}
        if op=='strlit':
            label=self.e.label("str"); self.strings.append((label,n['val']))
            e.emit(f"    la x6, {label}"); return {'base':'char','ptr':1}
        if op=='ident':
            return self.load_from_var(n['name'])
        if op=='assign':
            return self.gen_assign(n)
        if op=='binop':
            return self.gen_binop(n)
        if op=='unop':
            return self.gen_unop(n)
        if op=='cast':
            self.gen_expr(n['operand']); return n['ctype']
        if op=='call':
            return self.gen_call(n)
        if op=='index':
            return self.gen_index_rvalue(n)
        if op=='member':
            return self.gen_member_rvalue(n)
        raise CodegenError(f"expr op {op}")

    def gen_binop(self, n):
        e=self.e
        lt=self.gen_expr(n['lhs'])     # result x6
        C.push_x6(e)
        rt=self.gen_expr(n['rhs'])     # result x6
        C.pop_to(e, "x5")              # x5 = left, x6 = right
        bop=n['bop']
        unsigned = self.is_unsigned(lt) or self.is_unsigned(rt) or self.is_ptr(lt)
        # pointer arithmetic scaling: ptr +/- int  -> scale int by elem size
        if bop in ('+','-') and self.is_ptr(lt) and not self.is_ptr(rt):
            esz=self.elem_size(lt)
            if esz==2:
                e.emit("    li x4, 1"); e.emit("    sll x6, x4")   # right *= 2
            elif esz==4:
                e.emit("    li x4, 2"); e.emit("    sll x6, x4")
            elif esz!=1:
                # general scale via repeated add is overkill; structs use member, arrays pow2
                raise CodegenError("pointer step with non-pow2 element size")
        if bop in ('+','-','*','/','%'):
            # arithmetic; ensure correct order for - and /
            if bop=='+': C.bin_op(e,'+',True)
            elif bop=='-': C.bin_op(e,'-',True)
            elif bop=='*': C.bin_op(e,'*',True)
            elif bop=='/': C.bin_op(e,'/',True)
            elif bop=='%': C.bin_op(e,'%',True)
            return lt if not self.is_ptr(rt) else rt
        if bop in ('&','|','^'):
            C.bit_op(e,bop); return lt
        if bop=='<<':
            C.bit_op(e,'<<'); return lt
        if bop=='>>':
            C.bit_op(e,'>>' if unsigned else '>>s'); return lt
        if bop in ('<','>','<=','>='):
            if unsigned: C.cmp_unsigned(e,bop)
            else: C.bin_op(e,bop,True)
            return {'base':'int','ptr':0}
        if bop in ('==','!='):
            C.bin_op(e,bop,True); return {'base':'int','ptr':0}
        raise CodegenError(f"binop {bop}")

    def gen_unop(self, n):
        e=self.e; uop=n['uop']
        if uop=='-':
            self.gen_expr(n['operand']); C.unary_neg(e); return {'base':'int','ptr':0}
        if uop=='~':
            self.gen_expr(n['operand']); C.bit_not(e); return {'base':'int','ptr':0}
        if uop=='*':
            t=self.gen_expr(n['operand'])   # pointer value in x6
            et=self.elem_type(t)
            e.emit("    mv x5, x6")
            if self.is_byte(et):
                e.emit(f"    {'lbu' if self.is_unsigned(et) else 'lb'} x6, 0(x5)")
            else:
                e.emit("    lw x6, 0(x5)")
            return et
        if uop=='&':
            t=self.gen_addr(n['operand'])   # address in x6
            return {'base':t['base'],'ptr':t['ptr']+1}
        raise CodegenError(f"unop {uop}")

    def gen_call(self, n):
        e=self.e
        fnode=self.P.nodes[n['fn']]
        if fnode['op']!='ident': raise CodegenError("only direct calls supported")
        fname=fnode['name']
        # intrinsics: putint(x) -> ecall 0x000 ; putchar(c) -> ecall 0x001
        if fname=='putint' and len(n['args'])==1:
            self.gen_expr(n['args'][0]); e.emit("    ecall 0x000")
            return {'base':'int','ptr':0}
        if fname=='putchar' and len(n['args'])==1:
            self.gen_expr(n['args'][0]); e.emit("    ecall 0x001")
            return {'base':'int','ptr':0}
        # push args right-to-left
        for a in reversed(n['args']):
            self.gen_expr(a)
            C.push_x6(e)
        C.call_function(e, fname, len(n['args']))
        return self.func_types.get(fname, {'base':'int','ptr':0})

    # ---------- lvalue address generation (-> x6) ----------
    def gen_addr(self, idx):
        n=self.P.nodes[idx]; op=n['op']; e=self.e
        if op=='ident':
            self.gen_var_addr(n['name'],"x6"); return self.var_type(n['name'])
        if op=='unop' and n['uop']=='*':
            t=self.gen_expr(n['operand']); return self.elem_type(t)   # address already in x6
        if op=='index':
            return self.gen_index_addr(n)
        if op=='member':
            return self.gen_member_addr(n)
        raise CodegenError(f"not an lvalue: {op}")

    def gen_assign(self, n):
        e=self.e
        # compute rhs -> x6, save; compute lhs address -> x5; store
        rt=self.gen_expr(n['rhs'])
        C.push_x6(e)
        lt=self.gen_addr(n['lhs'])      # address -> x6
        e.emit("    mv x5, x6")         # x5 = addr
        e.emit("    lw x6, 0(x2)")      # x6 = value
        e.emit("    addi x2, 2")
        if self.is_byte(lt):
            e.emit("    sb x6, 0(x5)")
        else:
            e.emit("    sw x6, 0(x5)")
        return lt

    # ---------- index / member ----------
    def scale_index(self, esz):
        """x6 (index) *= esz, using shift for powers of two, else __mul."""
        e=self.e
        if esz==1: return
        if esz==2:
            e.emit("    li x5, 1"); e.emit("    sll x6, x5")   # x6 <<= 1
        elif esz==4:
            e.emit("    li x5, 2"); e.emit("    sll x6, x5")
        elif esz==8:
            e.emit("    li x5, 3"); e.emit("    sll x6, x5")
        else:
            # general: __mul(x6, esz)
            e.emit("    push x6")          # a = index
            C.load_const(e, esz); e.emit("    push x6")  # b = esz
            # __mul expects [sp]=a,[sp+2]=b; we pushed a then b -> [sp]=b,[sp+2]=a
            # swap by adjusting: easier to push in right order
            e.emit("    addi x2, 4")       # undo
            e.emit("    push x6")          # actually redo cleanly below
            # (esz>8 with non-pow2 is rare; do explicit)
            # fall back: repeated handling omitted — esz here is struct size
            raise CodegenError("non-power-of-two element size not yet supported")

    def gen_index_addr(self, n):
        e=self.e
        bt=self.gen_expr(n['base'])     # base address/pointer -> x6
        C.push_x6(e)
        self.gen_expr(n['idx'])         # index -> x6
        esz=self.elem_size(bt)
        self.scale_index(esz)           # x6 = index*esz
        C.pop_to(e,"x5")                # x5 = base, x6 = scaled index
        e.emit("    add x6, x5")        # x6 = index*esz + base
        return self.elem_type(bt)

    def gen_index_rvalue(self, n):
        et=self.gen_index_addr(n)       # addr in x6
        e=self.e; e.emit("    mv x5, x6")
        if self.is_byte(et):
            e.emit(f"    {'lbu' if self.is_unsigned(et) else 'lb'} x6, 0(x5)")
        else:
            e.emit("    lw x6, 0(x5)")
        return et

    def struct_of(self, t):
        b=t['base']
        if isinstance(b,tuple) and b[0]=='struct': return self.P.structs[b[1]]
        raise CodegenError("member of non-struct")

    def gen_member_addr(self, n):
        e=self.e
        if n['arrow']:
            bt=self.gen_expr(n['base'])         # pointer -> x6
            st=self.struct_of(self.elem_type(bt))
        else:
            bt=self.gen_addr(n['base'])         # struct address -> x6
            st=self.struct_of(bt)
        off=None; ftype=None
        for (fname,ft,fo,fa) in st['fields']:
            if fname==n['field']: off=fo; ftype=ft; break
        if off is None: raise CodegenError(f"no field {n['field']}")
        C.addr_plus_offset(e,"x6",off,"x6")
        return ftype

    def gen_member_rvalue(self, n):
        ft=self.gen_member_addr(n)
        e=self.e; e.emit("    mv x5, x6")
        if self.is_byte(ft):
            e.emit(f"    {'lbu' if self.is_unsigned(ft) else 'lb'} x6, 0(x5)")
        else:
            e.emit("    lw x6, 0(x5)")
        return ft


def compile_src(src):
    p=zcc.parse(src)
    return Codegen(p).gen_program()


if __name__=='__main__':
    import sys
    src=open(sys.argv[1]).read() if len(sys.argv)>1 else '''
    int add(int a, int b){ return a+b; }
    int main(void){ int x; x = add(3,4); return x; }
    '''
    print(compile_src(src))
