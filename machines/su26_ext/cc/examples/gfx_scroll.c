// su26-ext: wait vblank, bump scroll, print frame
// Build: python3 -m machines.zx16cc --machine su26-ext gfx_scroll.c -o gs

void putstr(char *s) {
    int i;
    i = 0;
    while (s[i] != 0) {
        putchar(s[i]);
        i = i + 1;
    }
}

void wait_vbl(void) { asm("ecall 0x070"); }
int get_frame(void) { asm("ecall 0x071"); }

int scroll_x;
int scroll_y;

void set_scroll(void) {
    asm("la x5, g_scroll_x");
    asm("lw x6, 0(x5)");
    asm("la x5, g_scroll_y");
    asm("lw x7, 0(x5)");
    asm("ecall 0x072");
}

int main(void) {
    int i;
    scroll_x = 0;
    scroll_y = 0;
    i = 0;
    while (i < 5) {
        wait_vbl();
        scroll_x = scroll_x + 2;
        set_scroll();
        i = i + 1;
    }
    putstr("frame=");
    putint(get_frame());
    putchar(10);
    return 0;
}
