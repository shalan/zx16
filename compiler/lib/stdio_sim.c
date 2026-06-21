// stdio_sim.c -- simulator/host-debug stdio.
// putchar(c)/putint(n) are compiler intrinsics (ECALL 0x001 / 0x000) decoded by the
// Python golden sim and the RTL testbenches; there is no FILE/printf/scanf (no OS, no
// varargs). For real-silicon UART output use stdio_si.c instead (and build with
// codegen.INTRINSIC_IO=False). Include via:  #include "stdio_sim.c"  (or "stdio.c").

// Write a NUL-terminated string, no newline.
void putstr(char *s){ int i; i = 0; while (s[i] != 0){ putchar(s[i]); i = i + 1; } }

// Standard puts: writes the string followed by a newline.
void puts(char *s){ putstr(s); putchar(10); }

// Write v as lowercase hex (minimal width), no "0x" prefix.
void puthex(unsigned v){
    char buf[5]; int i; int j; unsigned d;
    i = 0;
    if (v == 0){ buf[i] = '0'; i = i + 1; }
    while (v != 0){
        d = v & 15;
        if (d < 10) buf[i] = '0' + d; else buf[i] = 'a' + (d - 10);
        v = v >> 4; i = i + 1;
    }
    j = i;
    while (j > 0){ j = j - 1; putchar(buf[j]); }   // emit reversed
}
