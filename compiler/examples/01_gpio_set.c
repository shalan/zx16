// GPIO: set and clear individual bits in a memory-mapped output register.
// GPIO_OUT is a 16-bit register at 0xF010.
int main(void){
    unsigned *gpio;
    gpio = (unsigned *)0xF010;
    *gpio = 0;              // clear all
    *gpio = *gpio | (1 << 3);   // set bit 3
    *gpio = *gpio | (1 << 5);   // set bit 5
    *gpio = *gpio & ~(1 << 3);  // clear bit 3  -> only bit 5 set = 0x20
    return 0;
}
