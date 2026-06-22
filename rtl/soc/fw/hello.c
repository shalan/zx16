#include "stdio_si.c"
int main(void){
    uart_init();
    puts("Hello, ZX16 SoC!");
    putint(1234);
    putchar(10);
    puthex(48879);          // 0xBEEF
    putchar(10);
    return 0;
}
