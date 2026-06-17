// TEA (Tiny Encryption Algorithm) on a 16-bit machine, using a 32-bit emulation
// layer (struct u32 = {lo, hi}). Encrypts one 64-bit block (v0,v1) with a 128-bit key.
struct u32 { unsigned lo; unsigned hi; };

void set32(struct u32 *r, unsigned hi, unsigned lo){ r->hi = hi; r->lo = lo; }

void add32(struct u32 *r, struct u32 *a, struct u32 *b){
    unsigned lo; unsigned carry;
    lo = a->lo + b->lo;
    carry = 0;
    if (lo < a->lo) carry = 1;
    r->lo = lo;
    r->hi = a->hi + b->hi + carry;
}
void xor32(struct u32 *r, struct u32 *a, struct u32 *b){
    r->lo = a->lo ^ b->lo;
    r->hi = a->hi ^ b->hi;
}
// shift left by n (n < 16) across 32 bits
void shl32(struct u32 *r, struct u32 *a, unsigned n){
    unsigned hi; unsigned lo;
    lo = a->lo << n;
    hi = (a->hi << n) | (a->lo >> (16 - n));
    r->lo = lo; r->hi = hi;
}
// shift right (logical) by n (n < 16) across 32 bits
void shr32(struct u32 *r, struct u32 *a, unsigned n){
    unsigned hi; unsigned lo;
    hi = a->hi >> n;
    lo = (a->lo >> n) | (a->hi << (16 - n));
    r->lo = lo; r->hi = hi;
}

// one TEA feistel term: ((y<<4)+k0) ^ (y+sum) ^ ((y>>5)+k1)  -> into out
void feistel(struct u32 *out, struct u32 *y, struct u32 *sum,
             struct u32 *k0, struct u32 *k1){
    struct u32 t1; struct u32 t2; struct u32 t3; struct u32 tmp;
    shl32(&tmp, y, 4);  add32(&t1, &tmp, k0);   // (y<<4)+k0
    add32(&t2, y, sum);                          // y+sum
    shr32(&tmp, y, 5);  add32(&t3, &tmp, k1);   // (y>>5)+k1
    xor32(&tmp, &t1, &t2);
    xor32(out, &tmp, &t3);
}

struct u32 v0; struct u32 v1; struct u32 sum;
struct u32 k0; struct u32 k1; struct u32 k2; struct u32 k3;
struct u32 delta;

void tea_encrypt(void){
    int i; struct u32 f; struct u32 nv;
    set32(&sum, 0, 0);
    set32(&delta, 0x9E37, 0x79B9);   // 0x9E3779B9
    i = 0;
    while (i < 32){
        add32(&sum, &sum, &delta);
        // v0 += feistel(v1, sum, k0, k1)
        feistel(&f, &v1, &sum, &k0, &k1);
        add32(&nv, &v0, &f); v0.lo = nv.lo; v0.hi = nv.hi;
        // v1 += feistel(v0, sum, k2, k3)
        feistel(&f, &v0, &sum, &k2, &k3);
        add32(&nv, &v1, &f); v1.lo = nv.lo; v1.hi = nv.hi;
        i = i + 1;
    }
}

int main(void){
    // key = {0,1,2,3} (each 32-bit, here small values), plaintext v0=1,v1=2
    set32(&k0, 0, 0); set32(&k1, 0, 1); set32(&k2, 0, 2); set32(&k3, 0, 3);
    set32(&v0, 0, 1); set32(&v1, 0, 2);
    tea_encrypt();
    putint(v0.hi); putint(v0.lo);
    putint(v1.hi); putint(v1.lo);
    return 0;
}
