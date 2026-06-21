// dhrystone.c -- a Dhrystone-FLAVORED integer benchmark for ZX16 / ZC.
// NOT an official Dhrystone (ZC is 16-bit int, no long/stdlib/for/switch, structs
// via pointers only) -- a representative integer-workload proxy for CPI/MIPS:
// procedure calls, record + pointer manipulation, record copy, array fill/reduce,
// string compare/hash, if-ladders (switch proxy), and small multiply/divide.
// Runs RUNS iterations and prints a checksum (so RTL and the golden sim agree).

struct Rec { struct Rec *next; int key; int val; };
struct Rec Rec_A;
struct Rec Rec_B;
struct Rec *Ptr_Glob;
int arr[64];
char buf[24];
int Int_Glob;

void rec_copy(struct Rec *d, struct Rec *s){ d->key = s->key; d->val = s->val; d->next = s->next; }
void proc7(int a, int b, int *c){ *c = a + b + 2; }

int str_eq(char *a, char *b){
    int i; i = 0;
    while (a[i] != 0){ if (a[i] != b[i]) return 0; i = i + 1; }
    if (b[i] != 0) return 0;
    return 1;
}
void str_set(char *d, char *s){
    int i; i = 0;
    while (s[i] != 0){ d[i] = s[i]; i = i + 1; }
    d[i] = 0;
}
int hashstr(char *s){
    int h; int i; h = 0; i = 0;
    while (s[i] != 0){ h = (h << 3) ^ s[i]; i = i + 1; }
    return h;
}
int classify(int x){                 // switch-style ladder
    if (x < 0) return 0;
    if (x < 10) return 1;
    if (x < 100) return 2;
    return 3;
}

int work(int seed){
    int i; int acc; int q; struct Rec *p;
    // build two linked records
    Rec_A.key = seed & 63; Rec_A.val = seed;       Rec_A.next = &Rec_B;
    Rec_B.key = (seed + 1) & 63; Rec_B.val = seed + 7; Rec_B.next = 0;
    // traverse the list, copy a record, mutate via pointer-arg
    acc = 0; p = &Rec_A;
    while (p != 0){ acc = acc + p->val; p = p->next; }
    rec_copy(&Rec_B, &Rec_A);
    proc7(Rec_B.val, 10, &Rec_B.val);
    // string set / compare / hash
    str_set(buf, "DHRYSTONE STYLE KERNEL");
    if (str_eq(buf, "DHRYSTONE STYLE KERNEL")) q = 1; else q = 0;
    q = q + hashstr(buf);
    // array fill then classify-reduce
    i = 0; while (i < 64){ arr[i] = (i ^ seed) + acc; i = i + 1; }
    i = 0; while (i < 64){ q = q + classify(arr[i]); i = i + 1; }
    // small multiply / divide arithmetic
    acc = acc * 5;
    if (Rec_B.val != 0) acc = acc / 3;
    acc = 7 * (acc - q) - i;
    Int_Glob = acc & 255;
    return acc + q + Rec_B.val;
}

int main(void){
    int runs; int sum; int i;
    Ptr_Glob = &Rec_A; Int_Glob = 0;
    runs = 50; sum = 0; i = 0;
    while (i < runs){ sum = sum + work(i); i = i + 1; }
    putint(sum); putint(Int_Glob);
    return 0;
}
