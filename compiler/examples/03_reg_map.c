// Timer peripheral modeled as a struct register map at 0xF030.
struct Timer {
    unsigned ctrl;     // +0
    unsigned reload;   // +2
    unsigned count;    // +4
    unsigned status;   // +6
};
int main(void){
    struct Timer *t;
    t = (struct Timer *)0xF030;
    t->reload = 1000;
    t->ctrl   = (1 << 0) | (1 << 2);   // ENABLE | AUTORELOAD = 0x05
    t->count  = t->reload;
    putint( t->ctrl );
    putint( t->count );
    return 0;
}
