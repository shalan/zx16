# Issue #40 Test: Constant 64KB binary file size
# Issue: get_binary_output() always allocated a bytearray(65536) and
#        returned it in full, so even a tiny program produced a 64KB
#        .bin file padded with zeros.
# Expected: The .bin output should be trimmed to the highest address
#        actually used by .text/.data/.bss (a few dozen bytes for this
#        program), not a constant 65536 bytes.
# Actual (before fix): output was always exactly 65536 bytes regardless
#        of program size.
#
# To verify:
#   python zx16asm.py examples/issue40_binary_size.s -o test.bin
#   dir test.bin
   # should be well under 65536 bytes

# Old behavior can still be requested explicitly with --pad-full:
#   python zx16asm.py examples/issue40_binary_size.s -o test_full.bin --pad-full
#   dir test_full.bin # should be exactly 65536 bytes

.text
.org 0x0020
main:
    li a0, 5
    ecall 0x3FF