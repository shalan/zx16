// su26-ext: wait on timer UIF via ecall 0x052, then print
// Build: python3 -m machines.zx16cc --machine su26-ext timer_beep.c -o tb

void putstr(char *s) {
    int i;
    i = 0;
    while (s[i] != 0) {
        putchar(s[i]);
        i = i + 1;
    }
}

void timer_wait(void) {
    asm("ecall 0x052");
}

int match_val;

void set_match(void) {
    asm("la x5, g_match_val");
    asm("lw x6, 0(x5)");
    asm("ecall 0x051");
}

int main(void) {
    putstr("timer start\n");
    match_val = 100;   // small ARR for quick overflow in sim
    set_match();
    timer_wait();
    putstr("timer tick!\n");
    return 0;
}
