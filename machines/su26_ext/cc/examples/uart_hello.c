// su26-ext: hello over UART ecall (0x060) — works without MMIO putchar
// Build: python3 -m machines.zx16cc --machine su26-ext uart_hello.c -o uh

void uart_putc(int c) {
    // a0 = c: use global + asm
    // simpler: ecall with value already in expression path — use putchar intrinsic
    putchar(c);
}

void putstr(char *s) {
    int i;
    i = 0;
    while (s[i] != 0) {
        putchar(s[i]);
        i = i + 1;
    }
}

int main(void) {
    putstr("uart-hello su26-ext\n");
    putint(1234);
    putchar(10);
    return 0;
}
