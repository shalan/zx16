
// 09_fft.c — radix-2 DIT FFT, N=8, fixed-point twiddles (Q6, cos/-sin * 64).
// Stresses: int arrays, nested while loops, __mul/__div, and a deep
// multi-__mul butterfly subexpression with an arithmetic shift.
int re[8]; int im[8];
int W8c[4]; int W8s[4];
void fft8(void){
    int L; int half; int step; int j; int k; int i2; int idx;
    int ar; int ai; int br; int bi; int tr; int ti; int tmp;
    tmp=re[1]; re[1]=re[4]; re[4]=tmp; tmp=im[1]; im[1]=im[4]; im[4]=tmp;
    tmp=re[3]; re[3]=re[6]; re[6]=tmp; tmp=im[3]; im[3]=im[6]; im[6]=tmp;
    L = 2;
    while (L <= 8){
        half = L >> 1; step = 8 / L; j = 0;
        while (j < half){
            k = j * step; i2 = j;
            while (i2 < 8){
                idx = i2 + half;
                ar = re[i2]; ai = im[i2]; br = re[idx]; bi = im[idx];
                tr = (br * W8c[k] - bi * W8s[k]) >> 6;
                ti = (br * W8s[k] + bi * W8c[k]) >> 6;
                re[i2] = ar + tr; im[i2] = ai + ti;
                re[idx] = ar - tr; im[idx] = ai - ti;
                i2 = i2 + L;
            }
            j = j + 1;
        }
        L = L << 1;
    }
}
int main(void){
    int i;
    i=0; while(i<8){ re[i]=i; im[i]=0; i=i+1; }
    W8c[0]=64; W8c[1]=45; W8c[2]=0; W8c[3]=-45;
    W8s[0]=0; W8s[1]=-45; W8s[2]=-64; W8s[3]=-45;
    fft8();
    i=0; while(i<8){ putint(re[i]); putint(im[i]); i=i+1; }
    return 0;
}
