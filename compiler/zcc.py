#!/usr/bin/env python3
"""
zcc — a compiler for ZC-embedded, targeting ZX16 assembly.

Pipeline:  source text -> lexer -> tokens -> parser -> AST -> codegen -> asm

Written in Python now, structured so it ports to ZC itself later (the AST is a flat
node table addressed by integer handles, mirroring how the self-hosted version will
use struct pointers / array indices).

This file is built and tested incrementally. Stage 1: lexer.
"""

import os, re

# ---------------------------------------------------------------------------
# Tokens
# ---------------------------------------------------------------------------

# token kinds (strings for readability; in ZC these become int constants)
T_EOF='eof'; T_ID='id'; T_INT='int'; T_CHAR='char'; T_STR='str'
T_KW='kw'; T_PUNCT='punct'

KEYWORDS = {
    'int','char','unsigned','void','struct','if','else','while',
    'break','continue','return','sizeof','volatile','asm',
}

# multi-char punctuators, longest first so the scanner is greedy
PUNCT3 = []  # none in ZC
PUNCT2 = ['==','!=','<=','>=','<<','>>','->']
PUNCT1 = list('+-*/%&|^~<>=(){}[];,.!')

class Token:
    __slots__=('kind','val','line')
    def __init__(self,kind,val,line):
        self.kind=kind; self.val=val; self.line=line
    def __repr__(self):
        return f"{self.kind}:{self.val!r}@{self.line}"

class LexError(Exception): pass

def is_id_start(c): return c.isalpha() or c=='_'
def is_id_char(c):  return c.isalnum() or c=='_'

def lex(src):
    toks=[]; i=0; n=len(src); line=1
    def err(msg): raise LexError(f"line {line}: {msg}")
    while i<n:
        c=src[i]
        # whitespace
        if c=='\n': line+=1; i+=1; continue
        if c in ' \t\r': i+=1; continue
        # line comments
        if c=='/' and i+1<n and src[i+1]=='/':
            while i<n and src[i]!='\n': i+=1
            continue
        # identifiers / keywords
        if is_id_start(c):
            j=i+1
            while j<n and is_id_char(src[j]): j+=1
            word=src[i:j]
            toks.append(Token(T_KW if word in KEYWORDS else T_ID, word, line))
            i=j; continue
        # numbers (decimal + hex)
        if c.isdigit():
            j=i
            if c=='0' and i+1<n and src[i+1] in 'xX':
                j=i+2
                while j<n and src[j] in '0123456789abcdefABCDEF': j+=1
                val=int(src[i:j],16)
            else:
                while j<n and src[j].isdigit(): j+=1
                val=int(src[i:j],10)
            toks.append(Token(T_INT,val,line)); i=j; continue
        # char literal
        if c=="'":
            i+=1
            if i>=n: err("unterminated char literal")
            if src[i]=='\\':
                i+=1
                esc={'n':10,'t':9,'r':13,'0':0,'\\':92,"'":39}
                if src[i] not in esc: err(f"bad escape \\{src[i]}")
                val=esc[src[i]]; i+=1
            else:
                val=ord(src[i]); i+=1
            if i>=n or src[i]!="'": err("unterminated char literal")
            i+=1
            toks.append(Token(T_CHAR,val,line)); continue
        # string literal
        if c=='"':
            i+=1; buf=[]
            while i<n and src[i]!='"':
                if src[i]=='\\':
                    i+=1
                    esc={'n':'\n','t':'\t','r':'\r','0':'\0','\\':'\\','"':'"'}
                    if src[i] not in esc: err(f"bad escape \\{src[i]}")
                    buf.append(esc[src[i]]); i+=1
                else:
                    if src[i]=='\n': err("newline in string")
                    buf.append(src[i]); i+=1
            if i>=n: err("unterminated string")
            i+=1
            toks.append(Token(T_STR,''.join(buf),line)); continue
        # punctuators (greedy: try 2-char then 1-char)
        two=src[i:i+2]
        if two in PUNCT2:
            toks.append(Token(T_PUNCT,two,line)); i+=2; continue
        if c in PUNCT1:
            toks.append(Token(T_PUNCT,c,line)); i+=1; continue
        err(f"unexpected character {c!r}")
    toks.append(Token(T_EOF,None,line))
    return toks


# ---------------------------------------------------------------------------
# AST  — flat node table. Each node is a dict {'op':..., ...children as indices}.
# Using integer handles (not nested objects) mirrors the self-hosted ZC version,
# which will store nodes in arrays and reference them by index.
# ---------------------------------------------------------------------------

class ParseError(Exception): pass

class Parser:
    def __init__(self, toks):
        self.toks=toks; self.p=0
        self.nodes=[]            # node table
        self.structs={}          # tag -> {'fields':[(name,type,off)], 'size':n}
        self.funcs=[]            # list of function node indices
        self.globals=[]          # list of (name, type, init) 

    # ---- node allocation ----
    def node(self, **kw):
        self.nodes.append(kw); return len(self.nodes)-1

    # ---- token helpers ----
    def cur(self): return self.toks[self.p]
    def at_end(self): return self.cur().kind==T_EOF
    def advance(self): t=self.toks[self.p]; self.p+=1; return t
    def is_punct(self,s): t=self.cur(); return t.kind==T_PUNCT and t.val==s
    def is_kw(self,s): t=self.cur(); return t.kind==T_KW and t.val==s
    def eat_punct(self,s):
        if not self.is_punct(s):
            self.err(f"expected '{s}'")
        return self.advance()
    def eat_kw(self,s):
        if not self.is_kw(s): self.err(f"expected '{s}'")
        return self.advance()
    def err(self,msg):
        t=self.cur(); raise ParseError(f"line {t.line}: {msg}, got {t.kind}:{t.val!r}")

    # ---- types ----
    # A type is represented as a dict: {'base':'int'|'char'|'unsigned'|'uchar'|'void'|('struct',tag),
    #                                   'ptr':N}  where ptr = pointer depth
    def parse_type(self):
        if self.is_kw('volatile'): self.advance()  # accepted, ignored
        if self.is_kw('unsigned'):
            self.advance()
            if self.is_kw('char'): self.advance(); base='uchar'
            else:
                if self.is_kw('int'): self.advance()
                base='unsigned'
        elif self.is_kw('int'): self.advance(); base='int'
        elif self.is_kw('char'): self.advance(); base='char'
        elif self.is_kw('void'): self.advance(); base='void'
        elif self.is_kw('struct'):
            self.advance()
            if self.cur().kind!=T_ID: self.err("expected struct tag")
            tag=self.advance().val
            base=('struct',tag)
        else:
            return None
        ptr=0
        while self.is_punct('*'): self.advance(); ptr+=1
        return {'base':base,'ptr':ptr}

    def looks_like_type(self):
        t=self.cur()
        return t.kind==T_KW and t.val in ('int','char','unsigned','void','struct','volatile')

    # ---- top level ----
    def parse_program(self):
        while not self.at_end():
            if self.is_kw('struct') and self.toks[self.p+2].kind==T_PUNCT and self.toks[self.p+2].val=='{':
                self.parse_struct_decl()
                continue
            self.parse_toplevel_decl()
        return self

    def parse_struct_decl(self):
        self.eat_kw('struct')
        tag=self.advance().val
        self.eat_punct('{')
        fields=[]; off=0
        while not self.is_punct('}'):
            ftype=self.parse_type()
            if ftype is None: self.err("expected field type")
            fname=self.advance().val
            arrlen=None
            if self.is_punct('['):
                self.advance(); arrlen=self.advance().val; self.eat_punct(']')
            self.eat_punct(';')
            sz=self.type_size(ftype) if arrlen is None else self.type_size(ftype)*arrlen
            # alignment: word-sized members on even offset
            if self.type_align(ftype)==2 and (off & 1): off+=1
            fields.append((fname,ftype,off,arrlen))
            off+=sz
        self.eat_punct('}'); self.eat_punct(';')
        if off & 1: off+=1   # pad struct to even size
        self.structs[tag]={'fields':fields,'size':off}

    def type_size(self,t):
        if t['ptr']>0: return 2
        b=t['base']
        if b in ('int','unsigned'): return 2
        if b in ('char','uchar'): return 1
        if isinstance(b,tuple) and b[0]=='struct':
            return self.structs[b[1]]['size']
        if b=='void': return 0
        self.err(f"unknown type size {b}")
    def type_align(self,t):
        if t['ptr']>0: return 2
        b=t['base']
        if b in ('char','uchar'): return 1
        return 2

    def parse_toplevel_decl(self):
        ty=self.parse_type()
        if ty is None: self.err("expected declaration")
        name=self.advance().val
        if self.is_punct('('):
            self.parse_function(ty,name)
        else:
            # global variable
            arrlen=None
            if self.is_punct('['):
                self.advance(); arrlen=self.advance().val; self.eat_punct(']')
            init=None
            if self.is_punct('='):
                self.advance(); init=self.advance().val  # constant scalar only
            self.eat_punct(';')
            self.globals.append((name,ty,arrlen,init))

    def parse_function(self,ret,name):
        self.eat_punct('(')
        params=[]
        if self.is_kw('void') and self.toks[self.p+1].kind==T_PUNCT and self.toks[self.p+1].val==')':
            self.advance()
        else:
            while not self.is_punct(')'):
                pty=self.parse_type()
                pname=self.advance().val
                params.append((pname,pty))
                if self.is_punct(','): self.advance()
                else: break
        self.eat_punct(')')
        body=self.parse_block()
        idx=self.node(op='func',name=name,ret=ret,params=params,body=body)
        self.funcs.append(idx)

    # ---- statements ----
    def parse_block(self):
        self.eat_punct('{')
        stmts=[]
        while not self.is_punct('}'):
            stmts.append(self.parse_stmt())
        self.eat_punct('}')
        return self.node(op='block',stmts=stmts)

    def parse_stmt(self):
        if self.is_punct('{'): return self.parse_block()
        if self.is_kw('if'):
            self.advance(); self.eat_punct('(')
            cond=self.parse_expr(); self.eat_punct(')')
            then=self.parse_stmt()
            els=None
            if self.is_kw('else'): self.advance(); els=self.parse_stmt()
            return self.node(op='if',cond=cond,then=then,els=els)
        if self.is_kw('while'):
            self.advance(); self.eat_punct('(')
            cond=self.parse_expr(); self.eat_punct(')')
            body=self.parse_stmt()
            return self.node(op='while',cond=cond,body=body)
        if self.is_kw('return'):
            self.advance()
            val=None
            if not self.is_punct(';'): val=self.parse_expr()
            self.eat_punct(';')
            return self.node(op='return',val=val)
        if self.is_kw('break'):
            self.advance(); self.eat_punct(';'); return self.node(op='break')
        if self.is_kw('continue'):
            self.advance(); self.eat_punct(';'); return self.node(op='continue')
        if self.is_kw('asm'):
            self.advance(); self.eat_punct('(')
            s=self.advance().val; self.eat_punct(')'); self.eat_punct(';')
            return self.node(op='asm',text=s)
        if self.looks_like_type():
            ty=self.parse_type()
            name=self.advance().val
            arrlen=None
            if self.is_punct('['):
                self.advance(); arrlen=self.advance().val; self.eat_punct(']')
            init=None
            if self.is_punct('='):
                self.advance(); init=self.parse_expr()
            self.eat_punct(';')
            return self.node(op='vardecl',name=name,vtype=ty,arrlen=arrlen,init=init)
        # expression statement
        e=self.parse_expr(); self.eat_punct(';')
        return self.node(op='exprstmt',expr=e)

    # ---- expressions (precedence climbing per SPEC) ----
    def parse_expr(self): return self.parse_assign()

    def parse_assign(self):
        left=self.parse_equality()
        if self.is_punct('='):
            self.advance()
            right=self.parse_assign()
            return self.node(op='assign',lhs=left,rhs=right)
        return left

    def _binlevel(self, sub, ops):
        left=sub()
        while self.cur().kind==T_PUNCT and self.cur().val in ops:
            op=self.advance().val
            right=sub()
            left=self.node(op='binop',bop=op,lhs=left,rhs=right)
        return left

    def parse_equality(self): return self._binlevel(self.parse_relational, ('==','!='))
    def parse_relational(self): return self._binlevel(self.parse_bor, ('<','<=','>','>='))
    def parse_bor(self): return self._binlevel(self.parse_bxor, ('|',))
    def parse_bxor(self): return self._binlevel(self.parse_band, ('^',))
    def parse_band(self): return self._binlevel(self.parse_shift, ('&',))
    def parse_shift(self): return self._binlevel(self.parse_add, ('<<','>>'))
    def parse_add(self): return self._binlevel(self.parse_mul, ('+','-'))
    def parse_mul(self): return self._binlevel(self.parse_unary, ('*','/','%'))

    def parse_unary(self):
        if self.cur().kind==T_PUNCT and self.cur().val in ('-','~','*','&'):
            op=self.advance().val
            operand=self.parse_unary()
            return self.node(op='unop',uop=op,operand=operand)
        # cast:  ( type ) unary
        if self.is_punct('(') and self._next_is_type():
            self.advance()
            ty=self.parse_type()
            self.eat_punct(')')
            operand=self.parse_unary()
            return self.node(op='cast',ctype=ty,operand=operand)
        return self.parse_postfix()

    def _next_is_type(self):
        t=self.toks[self.p+1]   # token after the '('
        return t.kind==T_KW and t.val in ('int','char','unsigned','void','struct','volatile')

    def parse_postfix(self):
        e=self.parse_primary()
        while True:
            if self.is_punct('['):
                self.advance(); idx=self.parse_expr(); self.eat_punct(']')
                e=self.node(op='index',base=e,idx=idx)
            elif self.is_punct('('):
                self.advance(); args=[]
                while not self.is_punct(')'):
                    args.append(self.parse_expr())
                    if self.is_punct(','): self.advance()
                    else: break
                self.eat_punct(')')
                e=self.node(op='call',fn=e,args=args)
            elif self.is_punct('.'):
                self.advance(); field=self.advance().val
                e=self.node(op='member',base=e,field=field,arrow=False)
            elif self.is_punct('->'):
                self.advance(); field=self.advance().val
                e=self.node(op='member',base=e,field=field,arrow=True)
            else:
                break
        return e

    def parse_primary(self):
        t=self.cur()
        if self.is_punct('('):
            self.advance(); e=self.parse_expr(); self.eat_punct(')'); return e
        if t.kind==T_INT: self.advance(); return self.node(op='intlit',val=t.val)
        if t.kind==T_CHAR: self.advance(); return self.node(op='charlit',val=t.val)
        if t.kind==T_STR: self.advance(); return self.node(op='strlit',val=t.val)
        if t.kind==T_ID: self.advance(); return self.node(op='ident',name=t.val)
        self.err("expected expression")


# ---------------------------------------------------------------------------
# Preprocessor: #include "file" (recursive, include-once) + object-like #define
# ---------------------------------------------------------------------------

class PreprocError(Exception): pass

def preprocess(text, base_dir='.'):
    """Resolve `#include "file"` (recursive; each file included at most once) and
    collect object-like `#define NAME value`. Returns (expanded_text, defines).
    Macro *expansion* is done at the token level in parse(). Only `#include "..."`
    and object-like `#define` are supported (no <system> headers, no function-like
    macros, no conditionals)."""
    defines = {}
    included = set()
    out = []
    def go(txt, cur_dir):
        for raw in txt.split('\n'):
            s = raw.strip()
            if s.startswith('#'):
                s = re.sub(r'\s*//.*$', '', s).rstrip()   # strip trailing comment on directives
            if s.startswith('#include'):
                m = re.match(r'#include\s+"([^"]+)"\s*$', s)
                if not m:
                    raise PreprocError(f'bad #include (use #include "file"): {s}')
                inc = m.group(1)
                cand = os.path.join(cur_dir, inc)
                if not os.path.exists(cand) and os.path.exists(inc):
                    cand = inc                          # fall back to cwd-relative
                ap = os.path.abspath(cand)
                if ap in included:
                    continue                            # include-once
                if not os.path.exists(ap):
                    raise PreprocError(f'#include file not found: {inc}')
                included.add(ap)
                with open(ap) as f:
                    go(f.read(), os.path.dirname(ap))
            elif s.startswith('#define'):
                m = re.match(r'#define\s+([A-Za-z_]\w*)(\(?)(.*)$', s)
                if not m:
                    raise PreprocError(f'bad #define: {s}')
                if m.group(2) == '(':
                    raise PreprocError(f'function-like #define not supported: {s}')
                defines[m.group(1)] = m.group(3).strip()
            elif s.startswith('#'):
                raise PreprocError(f'unsupported preprocessor directive: {s}')
            else:
                out.append(raw)
    go(text, base_dir)
    return '\n'.join(out), defines

def expand_macros(tokens, defines):
    """Object-like macro expansion over a token stream. Supports nested macros; a
    macro never expands itself (prevents infinite recursion). Expanded tokens keep
    the use-site line number for error reporting."""
    if not defines:
        return tokens
    repl = {name: [t for t in lex(val) if t.kind != T_EOF] for name, val in defines.items()}
    out = []
    def emit(tok, active, line):
        if tok.kind == T_ID and tok.val in defines and tok.val not in active:
            for mt in repl[tok.val]:
                emit(mt, active | {tok.val}, line)
        else:
            out.append(Token(tok.kind, tok.val, line))
    for t in tokens:
        emit(t, frozenset(), t.line)
    return out

def parse(src, base_dir='.'):
    text, defines = preprocess(src, base_dir)
    toks = expand_macros(lex(text), defines)
    return Parser(toks).parse_program()


def dump_ast(p, idx, ind=0):
    n=p.nodes[idx]; pad='  '*ind
    op=n['op']
    if op=='func':
        print(f"{pad}func {n['name']} params={[x[0] for x in n['params']]}")
        dump_ast(p,n['body'],ind+1)
    elif op=='block':
        print(f"{pad}block")
        for s in n['stmts']: dump_ast(p,s,ind+1)
    elif op=='if':
        print(f"{pad}if"); dump_ast(p,n['cond'],ind+1); dump_ast(p,n['then'],ind+1)
        if n['els'] is not None: print(f"{pad}else"); dump_ast(p,n['els'],ind+1)
    elif op=='while':
        print(f"{pad}while"); dump_ast(p,n['cond'],ind+1); dump_ast(p,n['body'],ind+1)
    elif op=='return':
        print(f"{pad}return"); 
        if n['val'] is not None: dump_ast(p,n['val'],ind+1)
    elif op in ('break','continue'):
        print(f"{pad}{op}")
    elif op=='vardecl':
        print(f"{pad}vardecl {n['name']} : {n['vtype']} arr={n['arrlen']}")
        if n['init'] is not None: dump_ast(p,n['init'],ind+1)
    elif op=='exprstmt':
        print(f"{pad}exprstmt"); dump_ast(p,n['expr'],ind+1)
    elif op=='assign':
        print(f"{pad}assign"); dump_ast(p,n['lhs'],ind+1); dump_ast(p,n['rhs'],ind+1)
    elif op=='binop':
        print(f"{pad}binop {n['bop']}"); dump_ast(p,n['lhs'],ind+1); dump_ast(p,n['rhs'],ind+1)
    elif op=='unop':
        print(f"{pad}unop {n['uop']}"); dump_ast(p,n['operand'],ind+1)
    elif op=='cast':
        print(f"{pad}cast {n['ctype']}"); dump_ast(p,n['operand'],ind+1)
    elif op=='call':
        print(f"{pad}call"); dump_ast(p,n['fn'],ind+1)
        for a in n['args']: dump_ast(p,a,ind+1)
    elif op=='index':
        print(f"{pad}index"); dump_ast(p,n['base'],ind+1); dump_ast(p,n['idx'],ind+1)
    elif op=='member':
        print(f"{pad}member {'->' if n['arrow'] else '.'}{n['field']}"); dump_ast(p,n['base'],ind+1)
    elif op=='intlit': print(f"{pad}int {n['val']}")
    elif op=='charlit': print(f"{pad}char {n['val']}")
    elif op=='strlit': print(f"{pad}str {n['val']!r}")
    elif op=='ident': print(f"{pad}ident {n['name']}")
    elif op=='asm': print(f"{pad}asm {n['text']!r}")
    else: print(f"{pad}?{op}")


if __name__=='__main__':
    sample = r'''
    int g = 0x1F;
    struct Node { int kind; struct Node *next; };
    int add(int a, int b) {
        unsigned m;
        m = a & 0xFF;
        if (a < b) return b; else return a;
        while (a != 0) { a = a - 1; if (a == 3) break; }
        return m + (a << 2);
    }
    '''
    p=parse(sample)
    print("structs:", {k:(v['size'],[(f[0],f[2]) for f in v['fields']]) for k,v in p.structs.items()})
    print("globals:", p.globals)
    for f in p.funcs: dump_ast(p,f)

