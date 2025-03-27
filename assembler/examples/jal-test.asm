# Add some comments to describe the program

# the TEXT Section
    .text
    .org    0
main:

    li a0, 21      # A sample instruction
    jal x3, L1     # jump to L1
    addi a0, 2     # This instruction should be skipped

L1:
    ecall 1        # should print 21

exit:
    ecall 3

    .data
    .org    0x100
