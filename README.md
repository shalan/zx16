# ZX16 RISC ISA Specification

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

## Contribution
Please refer to the contribution guide [here](docs/contribute.md).
