// timer_si.c -- minimal nc_tmr (APB slot 1) driver. Timer visible at ZX16 0xD000.
// Periodic up-counter: counts at PCLK/(PSC+1), 0..ARR, wraps -> sets UIF.
// (16-bit ZX16 writes the low half of each 32-bit register, so keep PSC/ARR < 65536.)
#define TMR_CR  0xD000     // bit0 CEN (counter enable)
#define TMR_RIS 0xD024     // bit0 UIF (raw update/overflow flag)
#define TMR_ICR 0xD02C     // write bit0=1 to clear UIF
#define TMR_CNT 0xD100
#define TMR_PSC 0xD104
#define TMR_ARR 0xD108

void timer_start(unsigned psc, unsigned arr){
    *(volatile unsigned *)TMR_PSC = psc;
    *(volatile unsigned *)TMR_ARR = arr;
    *(volatile unsigned *)TMR_CR  = 1;            // CEN
}
unsigned timer_count(void){ return *(volatile unsigned *)TMR_CNT; }
int  timer_expired(void){ return *(volatile unsigned *)TMR_RIS & 1; }   // UIF
void timer_clear(void){ *(volatile unsigned *)TMR_ICR = 1; }
