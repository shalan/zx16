// u32.c -- 32-bit integer library for ZC on the 16-bit ZX16.
//
// ZC has no `long`; a 32-bit value is held as two 16-bit halves:
//     struct u32 { unsigned lo; unsigned hi; };     value = (hi << 16) | lo
// ZC passes/returns structs only by pointer, so every op takes `struct u32 *`
// and writes its result through the destination `r` (r may alias the inputs).
// Shift / rotate amounts are taken mod 32.
//
// ZC has no preprocessor / linker: to use this, concatenate u32.c ahead of your
// program (the functions are defined before any caller).

struct u32 { unsigned lo; unsigned hi; };

// ---- constructors / move ----
void set32(struct u32 *r, unsigned hi, unsigned lo){ r->hi = hi; r->lo = lo; }
void mov32(struct u32 *r, struct u32 *a){ r->hi = a->hi; r->lo = a->lo; }

// sign-extend a 16-bit signed int into a 32-bit value
void fromint(struct u32 *r, int v){
    r->lo = v;
    if (v < 0) r->hi = 0xFFFF; else r->hi = 0;
}

// ---- bitwise (per half) ----
void and32(struct u32 *r, struct u32 *a, struct u32 *b){ r->lo = a->lo & b->lo; r->hi = a->hi & b->hi; }
void or32 (struct u32 *r, struct u32 *a, struct u32 *b){ r->lo = a->lo | b->lo; r->hi = a->hi | b->hi; }
void xor32(struct u32 *r, struct u32 *a, struct u32 *b){ r->lo = a->lo ^ b->lo; r->hi = a->hi ^ b->hi; }
void not32(struct u32 *r, struct u32 *a){ r->lo = ~a->lo; r->hi = ~a->hi; }

// ---- add / subtract / negate ----
void add32(struct u32 *r, struct u32 *a, struct u32 *b){
    unsigned lo; unsigned carry;
    lo = a->lo + b->lo;
    carry = 0; if (lo < a->lo) carry = 1;       // carry out of the low half
    r->lo = lo;
    r->hi = a->hi + b->hi + carry;
}
void sub32(struct u32 *r, struct u32 *a, struct u32 *b){
    unsigned lo; unsigned borrow;
    lo = a->lo - b->lo;
    borrow = 0; if (a->lo < b->lo) borrow = 1;   // borrow into the high half
    r->lo = lo;
    r->hi = a->hi - b->hi - borrow;
}
void neg32(struct u32 *r, struct u32 *a){        // r = -a = ~a + 1
    struct u32 t; struct u32 one;
    t.lo = ~a->lo; t.hi = ~a->hi;
    one.lo = 1; one.hi = 0;
    add32(r, &t, &one);
}

// ---- shifts (amount mod 32) ----
void shl32(struct u32 *r, struct u32 *a, unsigned n){
    unsigned hi; unsigned lo;
    n = n & 31;
    if (n == 0){ r->hi = a->hi; r->lo = a->lo; }
    else {
        if (n < 16){ hi = (a->hi << n) | (a->lo >> (16 - n)); lo = a->lo << n; }
        else       { hi = a->lo << (n - 16);                  lo = 0; }
        r->hi = hi; r->lo = lo;
    }
}
void shr32(struct u32 *r, struct u32 *a, unsigned n){        // logical
    unsigned hi; unsigned lo;
    n = n & 31;
    if (n == 0){ r->hi = a->hi; r->lo = a->lo; }
    else {
        if (n < 16){ lo = (a->lo >> n) | (a->hi << (16 - n)); hi = a->hi >> n; }
        else       { lo = a->hi >> (n - 16);                  hi = 0; }
        r->hi = hi; r->lo = lo;
    }
}
void sar32(struct u32 *r, struct u32 *a, unsigned n){        // arithmetic
    int shi; unsigned fill; unsigned hi; unsigned lo;
    n = n & 31;
    shi = a->hi;                                  // signed view of the high half
    if (a->hi & 0x8000) fill = 0xFFFF; else fill = 0;
    if (n == 0){ r->hi = a->hi; r->lo = a->lo; }
    else {
        if (n < 16){ lo = (a->lo >> n) | (a->hi << (16 - n)); hi = shi >> n; }
        else       { lo = shi >> (n - 16);                    hi = fill; }
        r->hi = hi; r->lo = lo;
    }
}

// ---- rotates (amount mod 32) ----
void rol32(struct u32 *r, struct u32 *a, unsigned c){
    unsigned hi; unsigned lo; unsigned t;
    c = c & 31;
    hi = a->hi; lo = a->lo;
    if (c >= 16){ t = hi; hi = lo; lo = t; c = c - 16; }    // rotate-by-16 = swap halves
    if (c == 0){ r->hi = hi; r->lo = lo; }
    else {
        r->hi = (hi << c) | (lo >> (16 - c));
        r->lo = (lo << c) | (hi >> (16 - c));
    }
}
void ror32(struct u32 *r, struct u32 *a, unsigned c){
    c = c & 31;
    rol32(r, a, 32 - c);                           // ror c == rol (32 - c); rol masks &31
}

// ---- compares (return 0/1) ----
int ult32(struct u32 *a, struct u32 *b){           // unsigned a < b
    if (a->hi < b->hi) return 1;
    if (a->hi > b->hi) return 0;
    if (a->lo < b->lo) return 1;                    // high halves equal -> low (unsigned)
    return 0;
}
int slt32(struct u32 *a, struct u32 *b){           // signed a < b
    int ah; int bh;
    ah = a->hi; bh = b->hi;                          // signed view of the high halves
    if (ah < bh) return 1;
    if (ah > bh) return 0;
    if (a->lo < b->lo) return 1;                    // high halves equal -> low (unsigned)
    return 0;
}
int eq32(struct u32 *a, struct u32 *b){
    if (a->lo != b->lo) return 0;
    if (a->hi != b->hi) return 0;
    return 1;
}

// ---- multiply: r = a * b  (low 32 bits), shift-and-add, 32 iterations ----
void mul32(struct u32 *r, struct u32 *a, struct u32 *b){
    struct u32 acc; struct u32 addend; struct u32 mul;
    int i;
    acc.lo = 0; acc.hi = 0;
    addend.lo = a->lo; addend.hi = a->hi;           // a << i
    mul.lo = b->lo; mul.hi = b->hi;                 // remaining bits of b
    i = 0;
    while (i < 32){
        if (mul.lo & 1) add32(&acc, &acc, &addend);
        shl32(&addend, &addend, 1);
        shr32(&mul, &mul, 1);
        i = i + 1;
    }
    r->lo = acc.lo; r->hi = acc.hi;
}

// ---- unsigned divide: q = a / b, rem = a % b  (binary long division) ----
// b == 0 yields q = 0xFFFFFFFF, rem = a (a defined, no trap).
void udivmod32(struct u32 *q, struct u32 *rem, struct u32 *a, struct u32 *b){
    struct u32 quo; struct u32 r0; struct u32 aa;
    unsigned topbit; int i;
    if (b->lo == 0){ if (b->hi == 0){
        q->lo = 0xFFFF; q->hi = 0xFFFF; rem->lo = a->lo; rem->hi = a->hi; return;
    }}
    quo.lo = 0; quo.hi = 0;
    r0.lo = 0; r0.hi = 0;
    aa.lo = a->lo; aa.hi = a->hi;
    i = 0;
    while (i < 32){
        topbit = (aa.hi >> 15) & 1;                 // MSB of the running dividend
        shl32(&r0, &r0, 1); r0.lo = r0.lo | topbit; // rem = (rem << 1) | topbit
        shl32(&aa, &aa, 1);
        shl32(&quo, &quo, 1);
        if (ult32(&r0, b) == 0){                     // rem >= b ?
            sub32(&r0, &r0, b);
            quo.lo = quo.lo | 1;
        }
        i = i + 1;
    }
    q->lo = quo.lo; q->hi = quo.hi;
    rem->lo = r0.lo; rem->hi = r0.hi;
}
