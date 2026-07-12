// su26-ext — UART + timer extensions
#define UART_BASE  0xC000
#define UART_CR    0xC000
#define UART_SR    0xC004
#define UART_DR    0xC008
#define UART_BRR   0xC100

#define TMR_BASE   0xD000
#define TMR_CR     0xD000
#define TMR_RIS    0xD024
#define TMR_ICR    0xD02C
#define TMR_CNT    0xD100
#define TMR_PSC    0xD104
#define TMR_ARR    0xD108

// Extra ecalls
#define ECALL_TIMER_MILLIS  0x050
#define ECALL_TIMER_MATCH   0x051
#define ECALL_TIMER_WAIT    0x052
#define ECALL_UART_PUTC     0x060
#define ECALL_UART_GETC     0x061
#define ECALL_UART_HASCHAR  0x062
