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
.org 0x0000
reset:
    J    main    # Reset

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
.org 0x0000
reset:
    J    main

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