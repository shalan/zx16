// Fixed-size ring buffer head/tail logic, as in an interrupt-driven UART driver.
int buf[8];
int head;
int tail;

int rb_push(int v){
    int next;
    next = (head + 1) & 7;          // wrap at 8 via mask
    if (next == tail) return 0;     // full
    buf[head] = v;
    head = next;
    return 1;
}
int rb_pop(void){
    int v;
    if (head == tail) return -1;    // empty
    v = buf[tail];
    tail = (tail + 1) & 7;
    return v;
}
int main(void){
    head = 0; tail = 0;
    rb_push(10);
    rb_push(20);
    rb_push(30);
    putint( rb_pop() );   // 10
    putint( rb_pop() );   // 20
    rb_push(40);
    putint( rb_pop() );   // 30
    putint( rb_pop() );   // 40
    putint( rb_pop() );   // -1 empty
    return 0;
}
