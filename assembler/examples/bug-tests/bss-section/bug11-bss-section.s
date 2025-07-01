# Bug 11 Test: BSS Section Not Written to Output
# Issue: .bss section is collected but never written to output
# Expected: Uninitialized data should be zero-filled in output
# Actual: .bss section ignored, references point to wrong addresses

.text
.org 0x0020
main:
    # Load address of BSS variable
    la x1, bss_var1
    la x2, bss_var2
    la x3, bss_var3
    
    # Load values from BSS (should be zero)
    lw x4, 0(x1)    # Should load 0x0000
    lw x5, 0(x2)    # Should load 0x0000
    lw x6, 0(x3)    # Should load 0x0000
    
    # Store some values to BSS
    li x7, 0x1234
    sw x7, 0(x1)    # Store to bss_var1
    
    li x0, 0x5678
    sw x0, 0(x2)    # Store to bss_var2
    
    li x1, 0x9ABC
    sw x1, 0(x3)    # Store to bss_var3
    
    # Load back to verify
    lw x2, 0(x1)   # Should load 0x1234
    lw x3, 0(x2)   # Should load 0x5678
    lw x4, 0(x3)   # Should load 0x9ABC
    
    ecall 0x00A     # Exit

.data
.org 0x8000
data_var: .word 0xDEAD

.bss
.org 0x9000
bss_var1: .space 4    # 4 bytes of uninitialized data
bss_var2: .space 8    # 8 bytes of uninitialized data  
bss_var3: .space 16   # 16 bytes of uninitialized data 