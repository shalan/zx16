.text
    .org    0
main:
    lui     a0, %hi(0x100)
    ecall   5               # service 5 to print a string
exit:
    ecall   3


    .data
    .org    0x100

str:   
    .asciiz "hello world"