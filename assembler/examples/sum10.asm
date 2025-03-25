.org 0x0000
.text
start:
    li   a0, 0          ; Initialize sum = 0
    li   a1, 1          ; Initialize counter = 1
    li   t1, 11         ; Limit = 11 (loop until counter equals 11)
loop:
    add  a0, a1         ; sum = sum + counter
    addi a1, 1         ; counter++
    bne  a1, t1, loop   ; If counter != 11, continue looping
    ecall 1             ; ecall 1: Print the integer in a0 (expected output: 55)
    ecall 3             ; ecall 3: Terminate the program
