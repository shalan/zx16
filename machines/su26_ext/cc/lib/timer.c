// timer helpers — MMIO

void timer_start(unsigned psc, unsigned arr) {
    *(volatile unsigned *)0xD104 = psc;
    *(volatile unsigned *)0xD108 = arr;
    *(volatile unsigned *)0xD000 = 1;   // CEN
}

unsigned timer_count(void) {
    return *(volatile unsigned *)0xD100;
}

int timer_expired(void) {
    return (*(volatile unsigned *)0xD024) & 1;
}

void timer_clear(void) {
    *(volatile unsigned *)0xD02C = 1;
}
