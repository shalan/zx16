// stdio_si.c -- real-silicon stdio over the nc_uart (APB slot 0).
//
// Compile SoC firmware with codegen.INTRINSIC_IO=False so putchar/putint resolve to
// these MMIO functions instead of the simulator print ECALLs (see stdio_sim.c for
// the ECALL version). With the "small high window" map the UART (SoC 0x4000_0000)
// is visible to the 16-bit ZX16 at 0xC000.
#include "stdlib.c"                  // itoa / itohex for putint / puthex

#define UART_CR  0xC000              // bit0 EN, bit8 TXEN, bit9 RXEN
#define UART_SR  0xC004              // bit0 TXE (ok to write), bit1 RXNE (rx avail)
#define UART_DR  0xC008
#define UART_BRR 0xC100

void uart_init(void){
    *(volatile unsigned *)UART_BRR = 0;          // divisor 0 -> 16 clocks/bit (sim)
    *(volatile unsigned *)UART_CR  = 0x301;      // EN | TXEN | RXEN
}

int putchar(int c){
    while ((*(volatile unsigned *)UART_SR & 1) == 0) { }   // wait TXE
    *(volatile unsigned *)UART_DR = c;
    return c;
}

int uart_haschar(void){ return (*(volatile unsigned *)UART_SR & 2) != 0; }  // RXNE
int uart_getc(void){
    while ((*(volatile unsigned *)UART_SR & 2) == 0) { }   // wait RXNE
    return *(volatile unsigned *)UART_DR & 255;
}

void putstr(char *s){ int i; i = 0; while (s[i] != 0){ putchar(s[i]); i = i + 1; } }
void puts(char *s){ putstr(s); putchar(10); }
void putint(int v){ char b[7]; putstr(itoa(v, b)); }       // decimal, signed
void puthex(unsigned v){ char b[5]; putstr(itohex(v, b)); }
