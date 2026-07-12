// putchar via UART MMIO (su26-ext). For ecall path use putchar intrinsic instead.

void uart_init(void) {
    *(volatile unsigned *)0xC100 = 0;       // BRR
    *(volatile unsigned *)0xC000 = 0x301;   // CR EN|TXEN|RXEN
}

int putchar(int c) {
    // wait TXE
    while ((*(volatile unsigned *)0xC004 & 1) == 0) {
    }
    *(volatile unsigned *)0xC008 = c;
    return c;
}

void putstr(char *s) {
    int i;
    i = 0;
    while (s[i] != 0) {
        putchar(s[i]);
        i = i + 1;
    }
}
