// string.c -- ZX16 ZC minimal <string.h>.
// Byte/ASCII strings; counts and indices are 16-bit int. Comparisons return the
// unsigned-char difference (a[i]&255)-(b[i]&255), matching the C standard even for
// bytes >127 (ZC `char` is signed). Include via:  #include "string.c"
// With dead-function elimination, unused functions here are not emitted.

int strlen(char *s){
    int i; i = 0;
    while (s[i] != 0) i = i + 1;
    return i;
}

char *strcpy(char *d, char *s){
    int i; i = 0;
    while (s[i] != 0){ d[i] = s[i]; i = i + 1; }
    d[i] = 0;
    return d;
}

// Copies at most n bytes; if s is shorter than n, the remainder of d is zero-filled
// (standard strncpy). Does not necessarily NUL-terminate when strlen(s) >= n.
char *strncpy(char *d, char *s, int n){
    int i; int end;
    i = 0; end = 0;
    while (i < n){
        if (end == 0){ if (s[i] == 0) end = 1; }
        if (end) d[i] = 0; else d[i] = s[i];
        i = i + 1;
    }
    return d;
}

char *strcat(char *d, char *s){
    int i; int j;
    i = 0; while (d[i] != 0) i = i + 1;     // seek end of d
    j = 0; while (s[j] != 0){ d[i] = s[j]; i = i + 1; j = j + 1; }
    d[i] = 0;
    return d;
}

int strcmp(char *a, char *b){
    int i; i = 0;
    while (1){
        if (a[i] != b[i]) return (a[i] & 255) - (b[i] & 255);
        if (a[i] == 0) return 0;
        i = i + 1;
    }
}

int strncmp(char *a, char *b, int n){
    int i; i = 0;
    while (i < n){
        if (a[i] != b[i]) return (a[i] & 255) - (b[i] & 255);
        if (a[i] == 0) return 0;
        i = i + 1;
    }
    return 0;
}

// Returns a pointer to the first byte equal to (char)c, or 0 if not found.
// Matches the terminating NUL when c == 0 (standard).
char *strchr(char *s, int c){
    int i; int ch;
    ch = c & 255; i = 0;
    while (1){
        if ((s[i] & 255) == ch) return s + i;
        if (s[i] == 0) return 0;
        i = i + 1;
    }
}

char *memcpy(char *d, char *s, int n){
    int i; i = 0;
    while (i < n){ d[i] = s[i]; i = i + 1; }
    return d;
}

char *memset(char *d, int c, int n){
    int i; i = 0;
    while (i < n){ d[i] = c; i = i + 1; }
    return d;
}

int memcmp(char *a, char *b, int n){
    int i; i = 0;
    while (i < n){
        if (a[i] != b[i]) return (a[i] & 255) - (b[i] & 255);
        i = i + 1;
    }
    return 0;
}

// Overlap-safe copy: choose direction from the unsigned address order (pointers
// near 0xF000 would compare wrong as signed, so cast to unsigned).
char *memmove(char *d, char *s, int n){
    int i; unsigned ud; unsigned us;
    ud = (unsigned)d; us = (unsigned)s;
    if (ud < us){
        i = 0; while (i < n){ d[i] = s[i]; i = i + 1; }      // copy forward
    } else {
        i = n; while (i > 0){ i = i - 1; d[i] = s[i]; }      // copy backward
    }
    return d;
}
