#!/usr/bin/env python3

import sys
sys.path.append('assembler')
from zx16asm import ZX16Assembler

# Test the BSS section fix
assembler = ZX16Assembler()

with open('assembler/examples/bug-tests/bug11-bss-section.s', 'r') as f:
    source = f.read()

success = assembler.assemble(source, 'bug11-bss-section.s')

print("Assembly success:", success)
print("BSS section size:", len(assembler.sections['.bss']))
print("BSS section content:", assembler.sections['.bss'].hex())
print("BSS section address:", assembler.section_addresses['.bss'])

# Generate binary output
binary_output = assembler.get_binary_output()
print("Binary output size:", len(binary_output))
print("BSS section in binary (0x9000-0x901C):", binary_output[0x9000:0x901C].hex()) 