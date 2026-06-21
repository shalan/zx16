#include "stdio_si.c"
#include "timer_si.c"
int main(void){
    int n;
    uart_init();
    timer_start(0, 99);                       // wrap every 100 PCLK ticks
    n = 0;
    while (n < 5){
        while (timer_expired() == 0) { }      // wait for an overflow
        timer_clear();
        n = n + 1;
    }
    puts("timer: 5 overflows");
    return 0;
}
