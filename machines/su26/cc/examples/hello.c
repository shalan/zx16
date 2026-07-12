// su26 hello — putstr + putint via ecall intrinsics
// Build: python3 -m machines.zx16cc --machine su26 hello.c -o hello

void putstr(char *s) {
    int i;
    i = 0;
    while (s[i] != 0) {
        putchar(s[i]);
        i = i + 1;
    }
}

int main(void) {
    putstr("hello su26 ");
    putint(42);
    putchar(10);
    return 0;
}
