// stdio for su26 — thin wrappers around putchar/putint intrinsics
// (or pure ecall if INTRINSIC_IO is disabled and these are linked).

void putstr(char *s) {
    int i;
    i = 0;
    while (s[i] != 0) {
        putchar(s[i]);
        i = i + 1;
    }
}

void puts(char *s) {
    putstr(s);
    putchar(10);
}
