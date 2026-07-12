// su26 RNG demo — ecall seed_rng / random via asm
// Build: python3 -m machines.zx16cc --machine su26 rng_demo.c -o rng

int seed_val;

void seed_rng(void) {
    asm("la x5, g_seed_val");
    asm("lw x6, 0(x5)");
    asm("ecall 0x031");
}

int random16(void) {
    asm("ecall 0x032");
}

int main(void) {
    int i;
    seed_val = 1;
    seed_rng();
    i = 0;
    while (i < 3) {
        putint(random16());
        putchar(10);
        i = i + 1;
    }
    return 0;
}
