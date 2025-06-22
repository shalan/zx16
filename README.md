# ZX16 RISC ISA Specification – Complete Version

## Overview
The ZX16 RISC ISA is a 16-bit reduced-instruction-set architecture designed for simplicity, efficiency, and educational use. It features:
- **16-bit fixed-width** instructions and data  
- **8 general-purpose registers** (x0–x7) plus a 16-bit PC  
- **64 KB flat address space** for code, data, MMIO, and interrupt vectors  
- **8 instruction formats** selected by bits [2:0]  
- **50+ real & pseudo-instructions** covering ALU, branches, loads/stores, jumps, upper-immediates, and syscalls  
- **Smart immediates**: any immediate < 16 bits is sign-extended  
- **PC-relative control flow**: all branches, J and JAL use PC-relative offsets  
- **Memory-mapped I/O** at 0xF000–0xFFFF  
- **16 interrupt vectors** at 0x0000–0x001E (2 bytes each; reset at 0x0000)

---

## Key Features
- Compact 16-bit instructions  
- Two-operand ALU (rd/rs1 is both destination & first source)  
- Smart assembler handles large constants via pseudo-ops  
- Rich syscall interface for I/O, graphics, audio  
- Little-endian byte order
- Aligned memory access required for word operations
- Byte-addressable memory

---

## Register Architecture

### General-Purpose Registers

| Register | ABI | Role                    | Notes                       |
|:--------:|:---:|:-----------------------:|:----------------------------|
| x0       | t0  | Temporary               | Caller-saved scratch        |
| x1       | ra  | Return address          | Used by JAL/JALR            |
| x2       | sp  | Stack pointer           | Initialized to 0xEFFE       |
| x3       | s0  | Saved / Frame pointer   | Callee-saved                |
| x4       | s1  | Saved                   | Callee-saved                |
| x5       | t1  | Temporary               | Caller-saved scratch        |
| x6       | a0  | Arg0 / Return value     |                             |
| x7       | a1  | Arg1                    | Further args spill to stack |

### Special Registers
- **PC**: 16-bit program counter  

### Reset Behavior
- **PC**: Initialized to 0x0000 on reset
- **x0-x7**: Undefined values on reset (not initialized)

---

## Memory Map

| Range         | Usage                                        |
|:-------------:|:---------------------------------------------|
| 0x0000–0x001E | Interrupt vector table (16 entries × 2 bytes)|
| 0x0020–0xEFFF | RAM & ROM                                    |
| 0xF000–0xFFFF | MMIO (I/O registers start at 0xF000)         |

### Memory Properties
- **Endianness**: Little-endian
- **Addressing**: Byte-addressable
- **Alignment**: Word accesses (SW/LW) must be aligned to even addresses
- **Stack**: Grows downward from 0xEFFE

## Interrupt Vector Table
- 16 fixed entries at 0x0000–0x001E (2 bytes each)  
- Reset handler at 0x0000; others at 0x0002, 0x0004, …, 0x001E  

---

## Instruction Formats

Every instruction is 16 bits, with bits [2:0] as primary opcode:

| opcode ([2:0]) | Format    |
|:--------------:|:----------|
| 000            | R-Type    |
| 001            | I-Type    |
| 010            | B-Type    |
| 011            | S-Type    |
| 100            | L-Type    |
| 101            | J-Type    |
| 110            | U-Type    |
| 111            | SYS-Type  |

---

## ZX16 Instruction Format Field Layouts

All instructions are 16 bits. Bits [2:0] select the format/opcode.

### R-Type (opcode = `000`)
- **[15:12]** funct4  
- **[11:9]** rs2  
- **[8:6]** rd/rs1 (two‐operand: dest & first source)  
- **[5:3]** func3  
- **[2:0]** 000  

### I-Type (opcode = `001`)
- **[15:9]** imm7 (7-bit signed immediate, sign-extended)  
- **[8:6]** rd/rs1  
- **[5:3]** func3  
- **[2:0]** 001  

### B-Type (opcode = `010`)
- **[15:12]** imm[4:1] (high 4 bits of 5-bit signed offset, imm[0] = 0)  
- **[11:9]** rs2 (ignored for BZ/BNZ)  
- **[8:6]** rs1  
- **[5:3]** func3  
- **[2:0]** 010  

### S-Type (opcode = `011`)
- **[15:12]** imm[3:0] (4-bit signed store offset)  
- **[11:9]** rs2 (data register)  
- **[8:6]** rs1 (base register)  
- **[5:3]** func3  
- **[2:0]** 011  

### L-Type (opcode = `100`)
- **[15:12]** imm[3:0] (4-bit signed load offset)  
- **[11:9]** rs2 (base register)  
- **[8:6]** rd (destination register)  
- **[5:3]** func3  
- **[2:0]** 100  

### J-Type (opcode = `101`)
- **[15]** link flag (0 = J, 1 = JAL)  
- **[14:9]** imm[9:4] (high 6 bits of 10-bit signed offset, imm[0] = 0)  
- **[8:6]** rd (link register for JAL)  
- **[5:3]** imm[3:1] (low 3 bits of offset)  
- **[2:0]** 101  

### U-Type (opcode = `110`)
- **[15]** flag (0 = LUI, 1 = AUIPC)  
- **[14:9]** imm[15:10] (high 6 bits of immediate)  
- **[8:6]** rd  
- **[5:3]** imm[9:7] (mid 3 bits of immediate)  
- **[2:0]** 110  

### SYS-Type (opcode = `111`)
- **[15:6]** svc (10-bit system-call number)  
- **[5:3]** 000  
- **[2:0]** 111  

---

## Instruction Set Reference

### R-Type Instructions
| Mnemonic | Description                               |
|:--------:|:------------------------------------------|
| **ADD**  | rd ← rd + rs2                             |
| **SUB**  | rd ← rd – rs2                             |
| **SLT**  | rd ← (rd < rs2) ? 1 : 0                   |
| **SLTU** | rd ← (unsigned rd < unsigned rs2) ? 1 : 0 |
| **SLL**  | rd ← rd << (rs2 & 0xF)                    |
| **SRL**  | rd ← rd >> (rs2 & 0xF) (logical)          |
| **SRA**  | rd ← rd >> (rs2 & 0xF) (arithmetic)       |
| **OR**   | rd ← rd ∣ rs2                             |
| **AND**  | rd ← rd ∧ rs2                             |
| **XOR**  | rd ← rd ⊕ rs2                             |
| **MV**   | rd ← rs2                                  |
| **JR**   | PC ← rd                                   |
| **JALR** | rd ← PC + 2; PC ← rs2                     |

### I-Type Instructions
| Mnemonic  | Description                                     |
|:---------:|:------------------------------------------------|
| **ADDI**  | rd ← rd + sext(imm7)                            |
| **SLTI**  | rd ← (rd < sext(imm7)) ? 1 : 0                  |
| **SLTUI** | rd ← (unsigned rd < unsigned sext(imm7)) ? 1 : 0|
| **SLLI**  | rd ← rd << imm[3:0]                             |
| **SRLI**  | rd ← rd >> imm[3:0] (logical)                   |
| **SRAI**  | rd ← rd >> imm[3:0] (arithmetic)                |
| **ORI**   | rd ← rd ∣ sext(imm7)                            |
| **ANDI**  | rd ← rd ∧ sext(imm7)                            |
| **XORI**  | rd ← rd ⊕ sext(imm7)                            |
| **LI**    | rd ← sext(imm7)                                 |

### B-Type Instructions
| Mnemonic | Description                                          |
|:--------:|:-----------------------------------------------------|
| **BEQ**  | PC ← PC + offset if x[rs1] == x[rs2]                 |
| **BNE**  | PC ← PC + offset if x[rs1] != x[rs2]                 |
| **BZ**   | PC ← PC + offset if x[rs1] == 0                     |
| **BNZ**  | PC ← PC + offset if x[rs1] != 0                     |
| **BLT**  | PC ← PC + offset if x[rs1] < x[rs2]                  |
| **BGE**  | PC ← PC + offset if x[rs1] ≥ x[rs2]                  |
| **BLTU** | PC ← PC + offset if unsigned x[rs1] < unsigned x[rs2]|
| **BGEU** | PC ← PC + offset if unsigned x[rs1] ≥ unsigned x[rs2]|

### S-Type Instructions
| Mnemonic | Description                                                      |
|:--------:|:-----------------------------------------------------------------|
| **SB**   | Mem[x[rs1] + sext(imm4)] ← least-significant byte of x[rs2]     |
| **SW**   | Mem[x[rs1] + sext(imm4)] ← x[rs2] (16 bits)                     |

### L-Type Instructions
| Mnemonic | Description                                                   |
|:--------:|:--------------------------------------------------------------|
| **LB**   | rd ← sign-extended byte at Mem[x[rs2] + sext(imm4)]          |
| **LW**   | rd ← word at Mem[x[rs2] + sext(imm4)] (16 bits)              |
| **LBU**  | rd ← zero-extended byte at Mem[x[rs2] + sext(imm4)]          |

### J-Type Instructions
| Mnemonic | Description                           |
|:--------:|:--------------------------------------|
| **J**    | PC ← PC + offset                      |
| **JAL**  | x[rd] ← PC + 2; PC ← PC + offset      |

### U-Type Instructions
| Mnemonic  | Description                      |
|:---------:|:---------------------------------|
| **LUI**   | rd ← (imm[15:7] << 7)            |
| **AUIPC** | rd ← PC + (imm[15:7] << 7)       |

### SYS-Type Instructions
| Mnemonic | Description                              |
|:--------:|:-----------------------------------------|
| **ECALL**| Trap to service number in bits [15:6]   |

---

## Instruction Identification Table

This table shows, for each instruction, the key fields used to distinguish it: the primary opcode (bits [2:0]), plus any `funct4`, `func3`, `link` or `flag` bits, or immediate‐pattern conditions.

| Mnemonic | Format | opcode [2:0] | funct4 [15:12] | func3 [5:3] | link/flag (bit15)      | imm‐pattern/notes             |
|:--------:|:------:|:------------:|:--------------:|:-----------:|:-----------------------:|:------------------------------|
| **R-Type** |||||||
| ADD      | R      | `000`        | `0000`         | `000`       | —                       | two‐operand                    |
| SUB      | R      | `000`        | `0001`         | `000`       | —                       |                                |
| SLT      | R      | `000`        | `0010`         | `001`       | —                       |                                |
| SLTU     | R      | `000`        | `0011`         | `010`       | —                       |                                |
| SLL      | R      | `000`        | `0100`         | `011`       | —                       | logical left shift            |
| SRL      | R      | `000`        | `0101`         | `011`       | —                       | logical right shift           |
| SRA      | R      | `000`        | `0110`         | `011`       | —                       | arithmetic right shift        |
| OR       | R      | `000`        | `0111`         | `100`       | —                       |                                |
| AND      | R      | `000`        | `1000`         | `101`       | —                       |                                |
| XOR      | R      | `000`        | `1001`         | `110`       | —                       |                                |
| MV       | R      | `000`        | `1010`         | `111`       | —                       | move                           |
| JR       | R      | `000`        | `1011`         | `000`       | —                       | PC ← rd                        |
| JALR     | R      | `000`        | `1100`         | `000`       | —                       | link in rd, then PC ← rs2     |
| **I-Type** |||||||
| ADDI     | I      | `001`        | —              | `000`       | —                       | imm7 signed                   |
| SLTI     | I      | `001`        | —              | `001`       | —                       | imm7 signed                   |
| SLTUI    | I      | `001`        | —              | `010`       | —                       | imm7 unsigned compare         |
| SLLI     | I      | `001`        | —              | `011`       | —                       | shift left logical, imm7[6:4]=`001` |
| SRLI     | I      | `001`        | —              | `011`       | —                       | shift right logical, imm7[6:4]=`010` |
| SRAI     | I      | `001`        | —              | `011`       | —                       | shift right arithmetic, imm7[6:4]=`100` |
| ORI      | I      | `001`        | —              | `100`       | —                       |                                |
| ANDI     | I      | `001`        | —              | `101`       | —                       |                                |
| XORI     | I      | `001`        | —              | `110`       | —                       |                                |
| LI       | I      | `001`        | —              | `111`       | —                       | load imm7                     |
| **B-Type** |||||||
| BEQ      | B      | `010`        | —              | `000`       | —                       | offset = sext(imm[4:1]∥0)     |
| BNE      | B      | `010`        | —              | `001`       | —                       |                                |
| BZ       | B      | `010`        | —              | `010`       | —                       | ignore rs2                    |
| BNZ      | B      | `010`        | —              | `011`       | —                       | ignore rs2                    |
| BLT      | B      | `010`        | —              | `100`       | —                       |                                |
| BGE      | B      | `010`        | —              | `101`       | —                       |                                |
| BLTU     | B      | `010`        | —              | `110`       | —                       | unsigned compare              |
| BGEU     | B      | `010`        | —              | `111`       | —                       | unsigned compare              |
| **S-Type** |||||||
| SB       | S      | `011`        | —              | `000`       | —                       | store byte, offset=sext(imm[3:0]) |
| SW       | S      | `011`        | —              | `001`       | —                       | store word                    |
| **L-Type** |||||||
| LB       | L      | `100`        | —              | `000`       | —                       | load byte                     |
| LW       | L      | `100`        | —              | `001`       | —                       | load word                     |
| LBU      | L      | `100`        | —              | `100`       | —                       | load byte unsigned            |
| **J-Type** |||||||
| J        | J      | `101`        | —              | —           | link=0                  | offset = sext({imm[9:4],imm[3:1],0}) |
| JAL      | J      | `101`        | —              | —           | link=1                  | link in rd, then PC-relative  |
| **U-Type** |||||||
| LUI      | U      | `110`        | —              | —           | flag=0                  | imm from bits [15:7]<<7      |
| AUIPC    | U      | `110`        | —              | —           | flag=1                  | PC + (imm<<7)                |
| **SYS-Type** |||||||
| ECALL    | SYS    | `111`        | —              | —           | —                       | trap to service number [15:6] |

---

## Pseudo-Instructions

ZX16 supports several pseudo-instructions that expand to one or more real instructions:

### **LI16 rd, imm16** - Load 16-bit immediate
```assembly
LI16 x1, 0x1234
# Expands to:
LUI  x1, 0x24      # Load upper 9 bits (0x1234 >> 7 = 0x24)
ORI  x1, 0x34      # OR in lower 7 bits (0x1234 & 0x7F = 0x34)
```

### **LA rd, label** - Load address
```assembly
LA x1, data_label
# Expands to:
AUIPC x1, ((label - PC) >> 7)    # PC + upper bits of relative offset
ADDI  x1, ((label - PC) & 0x7F)  # Add lower 7 bits of relative offset
```

### **PUSH rd** - Push register to stack
```assembly
PUSH x1
# Expands to:
ADDI x2, -2        # SP -= 2 (decrement stack pointer)
SW   x1, 0(x2)     # Store register at new SP
```

### **POP rd** - Pop from stack to register
```assembly
POP x1
# Expands to:
LW   x1, 0(x2)     # Load from current SP
ADDI x2, 2         # SP += 2 (increment stack pointer)
```

### **CALL label** - Call function
```assembly
CALL func_name
# Expands to:
JAL x1, offset     # Jump and link (return address in x1/ra)
```

### **RET** - Return from function
```assembly
RET
# Expands to:
JR x1              # Jump to return address (x1/ra)
```

### **INC rd** - Increment register
```assembly
INC x1
# Expands to:
ADDI x1, 1         # rd = rd + 1
```

### **DEC rd** - Decrement register
```assembly
DEC x1
# Expands to:
ADDI x1, -1        # rd = rd - 1
```

### **NEG rd** - Negate register (two's complement)
```assembly
NEG x1
# Expands to:
XORI x1, -1        # Invert all bits (XOR with 0x7F sign-extended)
ADDI x1, 1         # Add 1 to complete two's complement
```

### **NOT rd** - Bitwise NOT
```assembly
NOT x1
# Expands to:
XORI x1, -1        # XOR with all 1s (0x7F sign-extended to 0xFFFF)
```

### **CLR rd** - Clear register to zero
```assembly
CLR x1
# Expands to:
XOR x1, x1         # x1 = x1 XOR x1 = 0
```

### **NOP** - No operation
```assembly
NOP
# Expands to:
ADD x0, x0         # x0 = x0 + x0 (does nothing useful)
```

---

## Calling Convention

### Function Calls
- **Arguments**: x6 (a0), x7 (a1); additional arguments spill to stack
- **Return value**: x6 (a0)
- **Return address**: x1 (ra) - set by JAL/JALR, used by RET
- **Stack pointer**: x2 (sp) - points to top of stack

### Register Usage
- **Caller-saved**: x0 (t0), x5 (t1), x6 (a0), x7 (a1)
- **Callee-saved**: x3 (s0), x4 (s1)
- **Special**: x1 (ra), x2 (sp)

### Stack Management
- Stack grows downward (toward lower addresses)
- Callee must restore stack pointer before returning
- Word-aligned stack operations recommended

---

## Implementation Notes

### Immediate Ranges
- **I-Type**: -64 to +63 (7-bit signed)
- **S-Type/L-Type**: -8 to +7 (4-bit signed)
- **B-Type**: -32 to +28 bytes (5-bit signed, word-aligned)
- **J-Type**: -1024 to +1020 bytes (10-bit signed, word-aligned)
- **U-Type**: 0 to 511 (9-bit unsigned, shifted left 7 bits)

### Shift Operations
- **Shift amount**: Limited to 0-15 (4 bits)
- **R-Type shifts**: Use `rs2 & 0xF` as shift amount
- **I-Type shifts**: Use `imm[3:0]` as shift amount, `imm[6:4]` selects operation

### Memory Access
- **Byte operations**: SB, LB, LBU - no alignment required
- **Word operations**: SW, LW - must be aligned to even addresses
- **Endianness**: Little-endian (LSB at lower address)

### Control Flow
- **Branches**: PC-relative, word-aligned targets
- **Jumps**: PC-relative, word-aligned targets  
- **Register jumps**: JR, JALR - absolute addressing

---

# ZX16 Assembler 

## Overview

The ZX16 Assembler is a two-pass assembler for the ZX16 RISC architecture that supports all base instructions, pseudo-instructions, essential directives, and multiple output formats including Verilog integration.

### Key Features
- **Two-pass assembly**: First pass builds symbol table, second pass generates code
- **Complete instruction support**: All ZX16 base and pseudo-instructions
- **Multiple output formats**: Binary, Intel HEX, Verilog HEX, memory files
- **Error reporting**: Detailed error messages with line numbers
- **Expression evaluation**: Constant expressions and label arithmetic
- **Conditional assembly**: Preprocessor-style conditionals
- **Case-insensitive**: Instruction mnemonics and register names
- **Comment support**: `#` for line comments, `/* */` for block comments

---

## Supported Instructions

### Base Instructions

#### R-Type Instructions
```assembly
ADD x1, x2          # rd ← rd + rs2
SUB x1, x2          # rd ← rd - rs2
SLT x1, x2          # rd ← (rd < rs2) ? 1 : 0
SLTU x1, x2         # rd ← (unsigned rd < unsigned rs2) ? 1 : 0
SLL x1, x2          # rd ← rd << (rs2 & 0xF)
SRL x1, x2          # rd ← rd >> (rs2 & 0xF) (logical)
SRA x1, x2          # rd ← rd >> (rs2 & 0xF) (arithmetic)
OR x1, x2           # rd ← rd | rs2
AND x1, x2          # rd ← rd & rs2
XOR x1, x2          # rd ← rd ^ rs2
MV x1, x2           # rd ← rs2
JR x1               # PC ← rd
JALR x1, x2         # rd ← PC + 2; PC ← rs2
```

#### I-Type Instructions
```assembly
ADDI x1, -42        # rd ← rd + sext(imm7)
SLTI x1, 10         # rd ← (rd < sext(imm7)) ? 1 : 0
SLTUI x1, 10        # rd ← (unsigned rd < unsigned sext(imm7)) ? 1 : 0
SLLI x1, 3          # rd ← rd << imm[3:0]
SRLI x1, 3          # rd ← rd >> imm[3:0] (logical)
SRAI x1, 3          # rd ← rd >> imm[3:0] (arithmetic)
ORI x1, 0x0F        # rd ← rd | sext(imm7)
ANDI x1, 0x0F       # rd ← rd & sext(imm7)
XORI x1, 0x0F       # rd ← rd ^ sext(imm7)
LI x1, 42           # rd ← sext(imm7)
```

#### B-Type Instructions
```assembly
BEQ x1, x2, label   # if rs1 == rs2: PC ← PC + offset
BNE x1, x2, label   # if rs1 != rs2: PC ← PC + offset
BZ x1, label        # if rs1 == 0: PC ← PC + offset
BNZ x1, label       # if rs1 != 0: PC ← PC + offset
BLT x1, x2, label   # if rs1 < rs2: PC ← PC + offset (signed)
BGE x1, x2, label   # if rs1 >= rs2: PC ← PC + offset (signed)
BLTU x1, x2, label  # if rs1 < rs2: PC ← PC + offset (unsigned)
BGEU x1, x2, label  # if rs1 >= rs2: PC ← PC + offset (unsigned)
```

#### S-Type Instructions
```assembly
SB x1, 4(x2)        # mem[rs1 + sext(imm)] ← rs2[7:0]
SW x1, -2(x2)       # mem[rs1 + sext(imm)] ← rs2[15:0]
```

#### L-Type Instructions
```assembly
LB x1, 4(x2)        # rd ← sext(mem[rs2 + sext(imm)][7:0])
LW x1, -2(x2)       # rd ← mem[rs2 + sext(imm)][15:0]
LBU x1, 4(x2)       # rd ← zext(mem[rs2 + sext(imm)][7:0])
```

#### J-Type Instructions
```assembly
J label             # PC ← PC + offset
JAL x1, function    # rd ← PC + 2; PC ← PC + offset
```

#### U-Type Instructions
```assembly
LUI x1, 0x1000      # rd ← (imm[15:7] << 7)
AUIPC x1, 0x1000    # rd ← PC + (imm[15:7] << 7)
```

#### SYS-Type Instructions
```assembly
ECALL 0x002         # trap to service number [15:6]
```

### Pseudo-Instructions

```assembly
LI16 x1, 0x1234     # Load 16-bit immediate
# Expands to: LUI x1, 0x24; ORI x1, 0x34

LA x1, data_label   # Load address
# Expands to: AUIPC x1, ((label-PC)>>7); ADDI x1, ((label-PC)&0x7F)

PUSH x1             # Push register to stack
# Expands to: ADDI x2, -2; SW x1, 0(x2)

POP x1              # Pop from stack to register
# Expands to: LW x1, 0(x2); ADDI x2, 2

CALL function       # Call function
# Expands to: JAL x1, offset

RET                 # Return from function
# Expands to: JR x1

INC x1              # Increment register
# Expands to: ADDI x1, 1

DEC x1              # Decrement register
# Expands to: ADDI x1, -1

NEG x1              # Negate register (two's complement)
# Expands to: XORI x1, -1; ADDI x1, 1

NOT x1              # Bitwise NOT
# Expands to: XORI x1, -1

CLR x1              # Clear register to zero
# Expands to: XOR x1, x1

NOP                 # No operation
# Expands to: ADD x0, x0
```

---

## Register Syntax

### Numeric Form (Required)
```assembly
x0, x1, x2, x3, x4, x5, x6, x7
```

### ABI Names (Optional)
```assembly
t0  # x0 - Temporary
ra  # x1 - Return address
sp  # x2 - Stack pointer
s0  # x3 - Saved/Frame pointer
s1  # x4 - Saved
t1  # x5 - Temporary
a0  # x6 - Argument 0/Return value
a1  # x7 - Argument 1
```

---

## Assembler Directives

### Memory Layout Directives
```assembly
.text                   # Code section (default)
.data                   # Data section
.bss                    # Uninitialized data section
.org 0x1000             # Set current address
.align 2                # Align to 2-byte boundary (word alignment)
```

### Data Definition Directives
```assembly
.byte 0x42, 65, 'A'    # Define bytes
.word 0x1234, 4660     # Define 16-bit words
.string "Hello\n"      # Null-terminated string
.ascii "Hello"         # String without null terminator
.space 10              # Reserve 10 bytes (zero-filled)
.fill 5, 2, 0xFFFF     # Fill 5 items, 2 bytes each, with 0xFFFF
```

### Symbol Definition Directives
```assembly
.equ STACK_SIZE, 0x400     # Define constant
.set MAX_COUNT, 100        # Define constant (same as .equ)
.global main               # Export symbol
.extern external_func      # Import external symbol
```

### Conditional Assembly Directives
```assembly
.ifdef DEBUG
    ECALL 0x3FC           # Print registers if DEBUG defined
.endif

.ifndef RELEASE
    .byte 0xFF            # Debug marker
.endif

.if STACK_SIZE > 0x200
    .word STACK_SIZE
.else
    .word 0x200
.endif
```

### File Inclusion Directives
```assembly
.include "constants.asm"   # Include another file
.incbin "data.bin"         # Include binary file
```

---

## Immediate Value Formats

### Numeric Literals
```assembly
42              # Decimal
0x2A            # Hexadecimal
0X2A            # Hexadecimal (uppercase)
0b00101010      # Binary
0B00101010      # Binary (uppercase)
0o52            # Octal
0O52            # Octal (uppercase)
'A'             # Character (ASCII 65)
'\n'            # Escape sequences: \n \r \t \\ \'
```

### Expression Support
```assembly
ADDI x1, STACK_SIZE + 16    # Constant expression
LW x2, (buffer + 4)(x1)     # Address calculation
.word end_label - start_label # Label arithmetic
.word ~0x0F                 # Bitwise NOT
.word (value << 2) | 0x03   # Shift and OR
```

### Supported Operators (by precedence)
```assembly
()              # Parentheses
~               # Bitwise NOT
* / %           # Multiply, divide, modulo
+ -             # Add, subtract
<< >>           # Shift left, shift right
&               # Bitwise AND
^               # Bitwise XOR
|               # Bitwise OR
```

---

## Label and Symbol Rules

### Label Definition
```assembly
main:                  # Global label
.local_label:          # Local label (file scope)
loop:                  # Loop label
    ADD x1, x2
    BNZ x1, loop       # Branch to local label
    RET

data_section:          # Section label
buffer: .space 64      # Data label with allocation
```

### Symbol Resolution
- **Forward references**: Supported (two-pass assembly)
- **Scope**: Global by default, local with `.` prefix
- **Case sensitivity**: Case-insensitive
- **Naming rules**: `[a-zA-Z_][a-zA-Z0-9_]*`
- **Reserved names**: Instruction mnemonics, register names, directive names

---

## Output Formats

### Binary Format (.bin)
Raw binary machine code, directly loadable into memory.

### Intel HEX Format (.hex)
```
:10002000C2000000C20008004120000842000010D4
:10003000C200001043200020C20000004320002074
:00000001FF
```

### Verilog HEX Format (.v)
```verilog
// ZX16 Program Memory Initialization
// Generated from: hello.asm
// Entry point: 0x0020
// Code size: 12 bytes
// Data size: 6 bytes

module program_memory(
    input [15:0] addr,
    output reg [15:0] data
);

always @(*) begin
    case (addr)
        16'h0020: data = 16'h2009;  // main: ADDI x1, 9
        16'h0022: data = 16'h1149;  //       SLTI x2, 9
        16'h0024: data = 16'h0000;  //       NOP
        16'h0026: data = 16'hA5F5;  //       JAL x1, function
        16'h8000: data = 16'h4865;  // msg:  "He"
        16'h8002: data = 16'h6C6C;  //       "ll"
        16'h8004: data = 16'h6F00;  //       "o\0"
        default:  data = 16'h0000;  // Uninitialized memory
    endcase
end

endmodule
```

### Memory File Format (.mem)
```
# ZX16 Memory File - Use with $readmemh
# Each line contains one 16-bit word in hex
2009
1149
0000
A5F5
4865
6C6C
6F00
```

### Sparse Memory File (.mem with --mem-sparse)
```
# ZX16 Sparse Memory File
@0020 2009  # main: ADDI x1, 9
@0022 1149  #       SLTI x2, 9
@0024 0000  #       NOP
@0026 A5F5  #       JAL x1, function
@8000 4865  # msg:  "He"
@8002 6C6C  #       "ll"
@8004 6F00  #       "o\0"
```

### Listing File Format (.lst)
```
ZX16 Assembler Listing                    Page 1
Source: hello.asm
Generated: 2025-06-17 14:30:25

     1                          # ZX16 Hello World Program
     2                          .text
     3                          .org 0x0020
     4                  
     5  0020  2009      main:   ADDI x1, 9
     6  0022  1149              SLTI x2, 9  
     7  0024  0000              ADD x0, x0     # NOP
     8  0026  A5F5              JAL x1, function
     9                  
    10                          .data
    11  8000  4865      msg:    .string "He"
    12  8002  6C6C      
    13  8004  6F00      

Symbol Table:
main     = 0x0020  (global)
msg      = 0x8000  (global)
function = 0x0100  (extern)

Statistics:
  Code size:    8 bytes
  Data size:    6 bytes
  Total size:   14 bytes
  Symbols:      3
  Lines:        13
```

---

## Command Line Interface

### Basic Usage
```bash
zx16asm input.asm                           # Default binary output
zx16asm input.asm -o output.bin            # Specify output file
zx16asm input.asm -f hex -o output.hex     # Intel HEX format
zx16asm input.asm -f verilog -o output.v   # Verilog module
zx16asm input.asm -f mem -o output.mem     # Memory file
```

### Command Line Options

#### Basic Options
```bash
-o, --output FILE           Output file name
-f, --format FORMAT         Output format: bin, hex, verilog, mem
-l, --listing FILE          Generate listing file
-h, --help                  Show help message
-V, --version               Show version information
```

#### Preprocessor Options
```bash
-D, --define SYM[=VAL]      Define preprocessor symbol
-U, --undefine SYM          Undefine preprocessor symbol
-I, --include PATH          Add include search path
```

#### Assembly Options
```bash
-v, --verbose               Verbose output
-w, --warnings              Enable all warnings
-W, --warning TYPE          Enable specific warning type
-E, --preprocess-only       Stop after preprocessing
--no-pseudo                 Disable pseudo-instruction expansion
--case-sensitive            Enable case-sensitive symbols
```

#### Output Format Options
```bash
--entry ADDRESS             Set entry point address (default: 0x0020)
--base-address ADDRESS      Set base address for relative addressing
--fill-value VALUE          Fill uninitialized memory with value
```

#### Verilog-Specific Options
```bash
--verilog-module NAME       Generate Verilog module with specified name
--verilog-width N           Memory width in bits (default: 16)
--verilog-depth N           Memory depth in words (default: 32768)
--verilog-comments          Include comments in Verilog output
--verilog-case-stmt         Use case statement (default: memory array)
```

#### Memory File Options
```bash
--mem-size SIZE             Memory size for .mem format
--mem-sparse                Only output non-zero addresses
--mem-word-size N           Words per line in memory file (default: 1)
--mem-byte-order ORDER      Byte order: little, big (default: little)
```

### Examples
```bash
# Basic assembly with listing
zx16asm program.asm -l program.lst

# Generate Verilog module for FPGA
zx16asm firmware.asm -f verilog -o firmware.v --verilog-module rom_memory

# Create memory file for simulation
zx16asm test.asm -f mem -o test.mem --mem-sparse

# Assembly with preprocessor defines
zx16asm main.asm -D DEBUG=1 -D VERSION=0x0100 -I include/

# Verbose assembly with all warnings
zx16asm complex.asm -v -w -l complex.lst
```

---

## Error Handling

### Error Categories

#### Syntax Errors
```assembly
ADD x1              # Error: Missing second operand
BEQ x1, x2          # Error: Missing branch target
.word               # Error: Missing data value
INVALID x1, x2      # Error: Unknown instruction 'INVALID'
```

#### Range Errors
```assembly
ADDI x1, 128        # Error: Immediate out of range (-64 to +63)
SB x1, 16(x2)       # Error: Offset out of range (-8 to +7)
SLLI x1, 16         # Error: Shift amount out of range (0 to 15)
.byte 256           # Error: Byte value out of range (0 to 255)
```

#### Symbol Errors
```assembly
JMP undefined_label # Error: Undefined symbol 'undefined_label'
ADD x8, x1          # Error: Invalid register 'x8' (valid: x0-x7)
.equ dup, 1         # Error: Symbol 'dup' already defined
.equ x1, 5          # Error: Cannot redefine register name
```

#### Type Errors
```assembly
ADD "string", x1    # Error: Invalid operand type
.word label         # Warning: Address used as immediate value
BEQ x1, 42, loop    # Error: Immediate not allowed in register field
```

#### Alignment Errors
```assembly
.org 0x1001         # Warning: Odd address for word-aligned code
SW x1, 1(x2)        # Error: Unaligned word access
.align 3            # Error: Invalid alignment (must be power of 2)
```

### Error Output Format
```
hello.asm:15:23: Error: Undefined symbol 'undefined_label'
    JMP undefined_label
                  ^~~~~
hello.asm:23:12: Warning: Immediate value 0x80 truncated to 7 bits
    ADDI x1, 128
           ^~~~
hello.asm:31:5: Error: Invalid register 'x8' (valid range: x0-x7)
    ADD x8, x1
        ^~

Assembly failed with 2 errors, 1 warning.
Total lines processed: 45
```

### Warning Types
```bash
-Wtruncate          # Warn about truncated immediate values
-Walign             # Warn about alignment issues
-Wunused            # Warn about unused symbols
-Wdeprecated        # Warn about deprecated syntax
-Wextra             # Enable extra warnings
-Wall               # Enable all warnings
-Werror             # Treat warnings as errors
```

---

## Built-in Symbols and Constants

### Predefined Symbols
```assembly
# Assembler identification
__ZX16__        = 1
__ASSEMBLER__   = "zx16asm"
__VERSION__     = 0x0100        # Version 1.0
__DATE__        = "2025-06-17"  # Assembly date
__TIME__        = "14:30:25"    # Assembly time
__FILE__        = "main.asm"    # Current filename
__LINE__        = 42            # Current line number

# Architecture constants
__WORD_SIZE__   = 2             # Bytes per word
__ADDR_SIZE__   = 16            # Address bus width
__DATA_SIZE__   = 16            # Data bus width
```

### Register Aliases
```assembly
# Numeric aliases (always available)
T0 = 0, RA = 1, SP = 2, S0 = 3
S1 = 4, T1 = 5, A0 = 6, A1 = 7

# Memory map constants
RESET_VECTOR    = 0x0000
INT_VECTORS     = 0x0000        # Interrupt vector table start
CODE_START      = 0x0020        # Default code start
MMIO_BASE       = 0xF000        # Memory-mapped I/O base
MMIO_SIZE       = 0x1000        # MMIO region size
STACK_TOP       = 0xEFFE        # Default stack top
MEM_SIZE        = 0x10000       # Total memory size (64KB)
```

---

## Assembly Process

### Pass 1: Symbol Collection
1. **Scan source files**: Process all .include directives
2. **Handle preprocessor**: Process conditional assembly directives
3. **Collect symbols**: Build symbol table with addresses
4. **Calculate sizes**: Determine section sizes and layout
5. **Validate syntax**: Check instruction formats and operands

### Pass 2: Code Generation
1. **Resolve symbols**: Replace symbols with numeric values
2. **Expand pseudo-instructions**: Convert to base instructions
3. **Generate machine code**: Encode instructions to binary
4. **Apply relocations**: Handle address-dependent values
5. **Output generation**: Write final output in requested format

### Memory Layout
```
0x0000 ┌──────────────────┐
       │ Interrupt Vectors│  32 bytes (16 vectors × 2 bytes)
0x0020 ├──────────────────┤
       │                  │
       │   Code Section   │  (.text)
       │                  │
       ├──────────────────┤
       │                  │
       │   Data Section   │  (.data)
       │                  │
       ├──────────────────┤
       │                  │
       │   BSS Section    │  (.bss)
       │                  │
0xEFFE ├──────────────────┤
       │     Stack        │  (grows downward)
0xF000 ├──────────────────┤
       │      MMIO        │
0xFFFF └──────────────────┘
```

---

## Example Programs

### Hello World Program
```assembly
# ZX16 Hello World Program
# Demonstrates basic I/O and string handling

.text
.org 0x0020

main:
    # Initialize stack pointer
    LI16 sp, STACK_TOP
    
    # Print greeting message
    LA a0, hello_msg
    ECALL 0x002        # Print string syscall
    
    # Read a character from user
    ECALL 0x001        # Read char into a0
    
    # Echo the character back
    ECALL 0x000        # Print character syscall
    
    # Print newline
    LI a0, '\n'
    ECALL 0x000
    
    # Exit with success code
    CLR a0             # Exit code 0
    ECALL 0x3FF        # Exit program syscall

.data
hello_msg: .string "Hello, ZX16! Enter a character: "

# Constants
.equ STACK_TOP, 0xEFFE
```

### Function Call Example
```assembly
# ZX16 Function Call Example
# Demonstrates function calls, stack usage, and local variables

.text
.org 0x0020

main:
    # Initialize stack
    LI16 sp, STACK_TOP
    
    # Call factorial function
    LI a0, 5           # Calculate 5!
    CALL factorial
    
    # Print result
    MV a0, a0          # Result already in a0
    ECALL 0x003        # Print decimal
    
    # Exit
    CLR a0
    ECALL 0x3FF
```

------

## Contribution
Please refer to the contribution guide [here](docs/contribute.md).
