// Poll a status register until its READY bit (bit 0) is set, then read data.
// STATUS at 0xF020 (byte), DATA at 0xF021 (byte).
int main(void){
    unsigned char *status;
    unsigned char *data;
    unsigned char s;
    status = (unsigned char *)0xF020;
    data   = (unsigned char *)0xF021;
    s = *status;
    while ((s & 1) == 0){       // wait for READY
        s = *status;
    }
    putint( *data );            // read the data byte
    return 0;
}
