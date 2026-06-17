// XOR checksum over a byte buffer — typical for serial/packet code.
unsigned char xorsum(unsigned char *buf, int n){
    unsigned char c;
    int i;
    c = 0;
    i = 0;
    while (i < n){
        c = c ^ buf[i];
        i = i + 1;
    }
    return c;
}
int main(void){
    unsigned char data[4];
    data[0] = 0x12;
    data[1] = 0x34;
    data[2] = 0x56;
    data[3] = 0x78;
    putint( xorsum(data, 4) );   // 0x12^0x34^0x56^0x78 = 0x58 = 88
    return 0;
}
