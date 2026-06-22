// ctype.c -- ZX16 ZC minimal <ctype.h> (ASCII). Each returns 0/1 (is*) or the
// converted character (to*). Include via:  #include "ctype.c"

int isdigit(int c){ if (c < '0') return 0; if (c > '9') return 0; return 1; }
int isupper(int c){ if (c < 'A') return 0; if (c > 'Z') return 0; return 1; }
int islower(int c){ if (c < 'a') return 0; if (c > 'z') return 0; return 1; }

int isalpha(int c){ if (isupper(c)) return 1; return islower(c); }
int isalnum(int c){ if (isalpha(c)) return 1; return isdigit(c); }

int isspace(int c){
    if (c == ' ') return 1;     // 0x20
    if (c == 9)   return 1;     // \t
    if (c == 10)  return 1;     // \n
    if (c == 11)  return 1;     // \v
    if (c == 12)  return 1;     // \f
    if (c == 13)  return 1;     // \r
    return 0;
}

int toupper(int c){ if (islower(c)) return c - 32; return c; }
int tolower(int c){ if (isupper(c)) return c + 32; return c; }
