// 08_md5.c — MD5 of "abc"  (expect 900150983cd24fb0d6963f7d28e17f72)
// Generated: exercises 32-bit emulation (struct u32), variable rotates, arrays,
// __mul, and a 64-iteration while loop with a 4-way if/else ladder.
struct u32 { unsigned lo; unsigned hi; };
void set32(struct u32 *r, unsigned hi, unsigned lo){ r->hi=hi; r->lo=lo; }
void and32(struct u32 *r, struct u32 *a, struct u32 *b){ r->lo=a->lo&b->lo; r->hi=a->hi&b->hi; }
void or32 (struct u32 *r, struct u32 *a, struct u32 *b){ r->lo=a->lo|b->lo; r->hi=a->hi|b->hi; }
void xor32(struct u32 *r, struct u32 *a, struct u32 *b){ r->lo=a->lo^b->lo; r->hi=a->hi^b->hi; }
void not32(struct u32 *r, struct u32 *a){ r->lo=~a->lo; r->hi=~a->hi; }
void add32(struct u32 *r, struct u32 *a, struct u32 *b){
    unsigned lo; unsigned carry; lo=a->lo+b->lo; carry=0; if (lo<a->lo) carry=1;
    r->lo=lo; r->hi=a->hi+b->hi+carry; }
void rol32(struct u32 *r, struct u32 *a, unsigned c){
    unsigned hi; unsigned lo; unsigned t; hi=a->hi; lo=a->lo;
    if (c>=16){ t=hi; hi=lo; lo=t; c=c-16; }
    if (c==0){ r->hi=hi; r->lo=lo; }
    else { r->hi=(hi<<c)|(lo>>(16-c)); r->lo=(lo<<c)|(hi>>(16-c)); } }
void md5F(struct u32 *r, struct u32 *x, struct u32 *y, struct u32 *z){
    struct u32 t1; struct u32 t2; struct u32 nx; and32(&t1,x,y); not32(&nx,x); and32(&t2,&nx,z); or32(r,&t1,&t2); }
void md5G(struct u32 *r, struct u32 *x, struct u32 *y, struct u32 *z){
    struct u32 t1; struct u32 t2; struct u32 nz; and32(&t1,x,z); not32(&nz,z); and32(&t2,y,&nz); or32(r,&t1,&t2); }
void md5H(struct u32 *r, struct u32 *x, struct u32 *y, struct u32 *z){
    struct u32 t1; xor32(&t1,x,y); xor32(r,&t1,z); }
void md5I(struct u32 *r, struct u32 *x, struct u32 *y, struct u32 *z){
    struct u32 t1; struct u32 nz; not32(&nz,z); or32(&t1,x,&nz); xor32(r,y,&t1); }
unsigned Khi[64]; unsigned Klo[64]; unsigned Sv[64]; unsigned Mhi[16]; unsigned Mlo[16];
struct u32 wa; struct u32 wb; struct u32 wc; struct u32 wd;
struct u32 A; struct u32 B; struct u32 C; struct u32 D;
struct u32 f; struct u32 rot; struct u32 mw; struct u32 kk;
void md5_init_tables(void){
    int i;
    Khi[0]=0xD76A; Klo[0]=0xA478;
    Khi[1]=0xE8C7; Klo[1]=0xB756;
    Khi[2]=0x2420; Klo[2]=0x70DB;
    Khi[3]=0xC1BD; Klo[3]=0xCEEE;
    Khi[4]=0xF57C; Klo[4]=0x0FAF;
    Khi[5]=0x4787; Klo[5]=0xC62A;
    Khi[6]=0xA830; Klo[6]=0x4613;
    Khi[7]=0xFD46; Klo[7]=0x9501;
    Khi[8]=0x6980; Klo[8]=0x98D8;
    Khi[9]=0x8B44; Klo[9]=0xF7AF;
    Khi[10]=0xFFFF; Klo[10]=0x5BB1;
    Khi[11]=0x895C; Klo[11]=0xD7BE;
    Khi[12]=0x6B90; Klo[12]=0x1122;
    Khi[13]=0xFD98; Klo[13]=0x7193;
    Khi[14]=0xA679; Klo[14]=0x438E;
    Khi[15]=0x49B4; Klo[15]=0x0821;
    Khi[16]=0xF61E; Klo[16]=0x2562;
    Khi[17]=0xC040; Klo[17]=0xB340;
    Khi[18]=0x265E; Klo[18]=0x5A51;
    Khi[19]=0xE9B6; Klo[19]=0xC7AA;
    Khi[20]=0xD62F; Klo[20]=0x105D;
    Khi[21]=0x0244; Klo[21]=0x1453;
    Khi[22]=0xD8A1; Klo[22]=0xE681;
    Khi[23]=0xE7D3; Klo[23]=0xFBC8;
    Khi[24]=0x21E1; Klo[24]=0xCDE6;
    Khi[25]=0xC337; Klo[25]=0x07D6;
    Khi[26]=0xF4D5; Klo[26]=0x0D87;
    Khi[27]=0x455A; Klo[27]=0x14ED;
    Khi[28]=0xA9E3; Klo[28]=0xE905;
    Khi[29]=0xFCEF; Klo[29]=0xA3F8;
    Khi[30]=0x676F; Klo[30]=0x02D9;
    Khi[31]=0x8D2A; Klo[31]=0x4C8A;
    Khi[32]=0xFFFA; Klo[32]=0x3942;
    Khi[33]=0x8771; Klo[33]=0xF681;
    Khi[34]=0x6D9D; Klo[34]=0x6122;
    Khi[35]=0xFDE5; Klo[35]=0x380C;
    Khi[36]=0xA4BE; Klo[36]=0xEA44;
    Khi[37]=0x4BDE; Klo[37]=0xCFA9;
    Khi[38]=0xF6BB; Klo[38]=0x4B60;
    Khi[39]=0xBEBF; Klo[39]=0xBC70;
    Khi[40]=0x289B; Klo[40]=0x7EC6;
    Khi[41]=0xEAA1; Klo[41]=0x27FA;
    Khi[42]=0xD4EF; Klo[42]=0x3085;
    Khi[43]=0x0488; Klo[43]=0x1D05;
    Khi[44]=0xD9D4; Klo[44]=0xD039;
    Khi[45]=0xE6DB; Klo[45]=0x99E5;
    Khi[46]=0x1FA2; Klo[46]=0x7CF8;
    Khi[47]=0xC4AC; Klo[47]=0x5665;
    Khi[48]=0xF429; Klo[48]=0x2244;
    Khi[49]=0x432A; Klo[49]=0xFF97;
    Khi[50]=0xAB94; Klo[50]=0x23A7;
    Khi[51]=0xFC93; Klo[51]=0xA039;
    Khi[52]=0x655B; Klo[52]=0x59C3;
    Khi[53]=0x8F0C; Klo[53]=0xCC92;
    Khi[54]=0xFFEF; Klo[54]=0xF47D;
    Khi[55]=0x8584; Klo[55]=0x5DD1;
    Khi[56]=0x6FA8; Klo[56]=0x7E4F;
    Khi[57]=0xFE2C; Klo[57]=0xE6E0;
    Khi[58]=0xA301; Klo[58]=0x4314;
    Khi[59]=0x4E08; Klo[59]=0x11A1;
    Khi[60]=0xF753; Klo[60]=0x7E82;
    Khi[61]=0xBD3A; Klo[61]=0xF235;
    Khi[62]=0x2AD7; Klo[62]=0xD2BB;
    Khi[63]=0xEB86; Klo[63]=0xD391;
    Sv[0]=7;
    Sv[1]=12;
    Sv[2]=17;
    Sv[3]=22;
    Sv[4]=7;
    Sv[5]=12;
    Sv[6]=17;
    Sv[7]=22;
    Sv[8]=7;
    Sv[9]=12;
    Sv[10]=17;
    Sv[11]=22;
    Sv[12]=7;
    Sv[13]=12;
    Sv[14]=17;
    Sv[15]=22;
    Sv[16]=5;
    Sv[17]=9;
    Sv[18]=14;
    Sv[19]=20;
    Sv[20]=5;
    Sv[21]=9;
    Sv[22]=14;
    Sv[23]=20;
    Sv[24]=5;
    Sv[25]=9;
    Sv[26]=14;
    Sv[27]=20;
    Sv[28]=5;
    Sv[29]=9;
    Sv[30]=14;
    Sv[31]=20;
    Sv[32]=4;
    Sv[33]=11;
    Sv[34]=16;
    Sv[35]=23;
    Sv[36]=4;
    Sv[37]=11;
    Sv[38]=16;
    Sv[39]=23;
    Sv[40]=4;
    Sv[41]=11;
    Sv[42]=16;
    Sv[43]=23;
    Sv[44]=4;
    Sv[45]=11;
    Sv[46]=16;
    Sv[47]=23;
    Sv[48]=6;
    Sv[49]=10;
    Sv[50]=15;
    Sv[51]=21;
    Sv[52]=6;
    Sv[53]=10;
    Sv[54]=15;
    Sv[55]=21;
    Sv[56]=6;
    Sv[57]=10;
    Sv[58]=15;
    Sv[59]=21;
    Sv[60]=6;
    Sv[61]=10;
    Sv[62]=15;
    Sv[63]=21;
    i=0; while(i<16){ Mhi[i]=0; Mlo[i]=0; i=i+1; }
    Mhi[0]=0x8063; Mlo[0]=0x6261;
    Mlo[14]=0x0018;
}
void md5_run(void){
    int i; int group; int g;
    set32(&A,0x6745,0x2301); set32(&B,0xEFCD,0xAB89); set32(&C,0x98BA,0xDCFE); set32(&D,0x1032,0x5476);
    wa.lo=A.lo; wa.hi=A.hi; wb.lo=B.lo; wb.hi=B.hi; wc.lo=C.lo; wc.hi=C.hi; wd.lo=D.lo; wd.hi=D.hi;
    i=0;
    while (i < 64){
        group = i >> 4;
        if (group == 0){ md5F(&f,&wb,&wc,&wd); g = i & 15; }
        else { if (group == 1){ md5G(&f,&wb,&wc,&wd); g = (5*i+1) & 15; }
               else { if (group == 2){ md5H(&f,&wb,&wc,&wd); g = (3*i+5) & 15; }
                      else { md5I(&f,&wb,&wc,&wd); g = (7*i) & 15; } } }
        set32(&mw, Mhi[g], Mlo[g]); set32(&kk, Khi[i], Klo[i]);
        add32(&f,&f,&wa); add32(&f,&f,&mw); add32(&f,&f,&kk);
        rol32(&rot,&f,Sv[i]);
        wa.lo=wd.lo; wa.hi=wd.hi; wd.lo=wc.lo; wd.hi=wc.hi; wc.lo=wb.lo; wc.hi=wb.hi;
        add32(&wb,&wb,&rot);
        i = i + 1;
    }
    add32(&A,&A,&wa); add32(&B,&B,&wb); add32(&C,&C,&wc); add32(&D,&D,&wd);
}
int main(void){
    md5_init_tables(); md5_run();
    putint(A.hi); putint(A.lo); putint(B.hi); putint(B.lo);
    putint(C.hi); putint(C.lo); putint(D.hi); putint(D.lo);
    return 0;
}
