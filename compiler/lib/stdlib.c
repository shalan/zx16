// stdlib.c -- ZX16 ZC minimal <stdlib.h>: string <-> number conversion.
// ZX16 has no printf (no varargs), so itoa/utoa/itohex are how you format numbers
// for output (then putstr/putchar them). 16-bit int/unsigned only.
// Include via:  #include "stdlib.c"

// Parse an optional sign and decimal digits, skipping leading whitespace. Stops at
// the first non-digit. (16-bit; no overflow checking, like C's atoi.)
int atoi(char *s){
    int i; int sign; int val; int c;
    i = 0; sign = 1; val = 0;
    while (1){                              // skip leading whitespace
        c = s[i];
        if (c == ' ')      i = i + 1;
        else if (c == 9)   i = i + 1;       // \t
        else if (c == 10)  i = i + 1;       // \n
        else if (c == 13)  i = i + 1;       // \r
        else break;
    }
    if (c == '-'){ sign = -1; i = i + 1; }
    else if (c == '+'){ i = i + 1; }
    while (1){
        c = s[i];
        if (c < '0') break;
        if (c > '9') break;
        val = val * 10 + (c - '0');
        i = i + 1;
    }
    return sign * val;
}

// Unsigned to decimal. buf must hold >= 6 bytes (5 digits + NUL). Returns buf.
char *utoa(unsigned v, char *buf){
    char tmp[6]; int i; int j;
    i = 0;
    if (v == 0){ tmp[i] = '0'; i = i + 1; }
    while (v != 0){ tmp[i] = '0' + (v % 10); v = v / 10; i = i + 1; }
    j = 0;
    while (i > 0){ i = i - 1; buf[j] = tmp[i]; j = j + 1; }   // reverse
    buf[j] = 0;
    return buf;
}

// Signed to decimal. buf must hold >= 7 bytes ('-' + 5 digits + NUL). Returns buf.
// Works for INT_MIN: (unsigned)(0 - v) yields 32768 for v = -32768.
char *itoa(int v, char *buf){
    char tmp[6]; int i; int j; int neg; unsigned u;
    neg = 0;
    if (v < 0){ neg = 1; u = (unsigned)(0 - v); } else { u = (unsigned)v; }
    i = 0;
    if (u == 0){ tmp[i] = '0'; i = i + 1; }
    while (u != 0){ tmp[i] = '0' + (u % 10); u = u / 10; i = i + 1; }
    j = 0;
    if (neg){ buf[j] = '-'; j = j + 1; }
    while (i > 0){ i = i - 1; buf[j] = tmp[i]; j = j + 1; }
    buf[j] = 0;
    return buf;
}

// Unsigned to lowercase hex, minimal width. buf must hold >= 5 bytes. Returns buf.
char *itohex(unsigned v, char *buf){
    char tmp[5]; int i; int j; unsigned d;
    i = 0;
    if (v == 0){ tmp[i] = '0'; i = i + 1; }
    while (v != 0){
        d = v & 15;
        if (d < 10) tmp[i] = '0' + d; else tmp[i] = 'a' + (d - 10);
        v = v >> 4;                         // v is unsigned -> logical shift
        i = i + 1;
    }
    j = 0;
    while (i > 0){ i = i - 1; buf[j] = tmp[i]; j = j + 1; }
    buf[j] = 0;
    return buf;
}
