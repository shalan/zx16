// monitor.c -- ZX16 UART debug monitor (runs on the SoC, talks over nc_uart).
// Commands (hex args, whitespace/newline separated):
//   r <addr>            read a 16-bit word, print it (hex)
//   w <addr> <val>      write a 16-bit word, print "ok"
//   d <addr> <n>        dump n 16-bit words from addr
//   L <addr> <n>        load n raw bytes (streamed right after the newline) to addr
//   g <addr>            jump to addr / execute (does not return)
//   q                   quit -> halt
// Note: a loaded image must be position-independent or assembled for its load address.
// Build for the SoC (codegen.INTRINSIC_IO=False); see rtl/soc/soc_run.py.
#include "stdio_si.c"

int go_target;                         // set by 'g', read by the asm jump below

int hexval(int c){                     // hex digit -> 0..15, else -1
    if (c < '0') return -1;
    if (c <= '9') return c - '0';
    if (c < 'A') return -1;
    if (c <= 'F') return c - 'A' + 10;
    if (c < 'a') return -1;
    if (c <= 'f') return c - 'a' + 10;
    return -1;
}

unsigned gethex(void){                 // skip spaces, read hex, consume terminator
    int c; int d; unsigned v;
    c = uart_getc();
    while (c == ' ') c = uart_getc();
    v = 0; d = hexval(c);
    while (d >= 0){ v = (v << 4) | d; c = uart_getc(); d = hexval(c); }
    return v;
}

int getcmd(void){                      // next non-blank command character
    int c;
    c = uart_getc();
    while (1){
        if (c == ' ')      c = uart_getc();
        else if (c == 10)  c = uart_getc();
        else if (c == 13)  c = uart_getc();
        else return c;
    }
}

int main(void){
    int cmd; unsigned a; unsigned v; unsigned n; unsigned i;
    uart_init();
    puts("ZX16MON");
    while (1){
        putchar('>');
        cmd = getcmd();
        if (cmd == 'q'){ puts("bye"); return 0; }                  // -> crt0 halts
        else if (cmd == 'r'){ a = gethex(); puthex(*(volatile unsigned *)a); putchar(10); }
        else if (cmd == 'w'){ a = gethex(); v = gethex();
                              *(volatile unsigned *)a = v; puts("ok"); }
        else if (cmd == 'd'){ a = gethex(); n = gethex(); i = 0;
                              while (i < n){ puthex(*(volatile unsigned *)(a + i * 2));
                                             putchar(32); i = i + 1; }
                              putchar(10); }
        else if (cmd == 'L'){ a = gethex(); n = gethex(); i = 0;   // load: L <addr> <nbytes> <raw bytes>
                              while (i < n){ *(volatile char *)(a + i) = uart_getc(); i = i + 1; }
                              puts("ok"); }
        else if (cmd == 'g'){ a = gethex(); go_target = a;        // go: execute from <addr>
                              asm("la x5, g_go_target");
                              asm("lw x5, 0(x5)");
                              asm("jr x5"); }
        else { puts("?"); }
    }
}
