# z16
A 16-bit RISC-V Inspired ISA

## Highlights
- Registers: 8 general-purpose registers (x0–x7), each 16 bits wide.
- Memory: Byte-addressable, up to 64 KB (16-bit addressing).
- Instruction length: 16 bits fixed.
- The machine word size: 16 bits
- Uses 2-registers format, the first register in data processing instructions is the first source and the destination

## RV32I vs. Z16
||RV32I|Z16|
|-|-----|---|
|Architecture |32-bit RISC ISA| 16-bit RISC ISA|
|Memory|Byte addressable 4 Gbytes| Byte addressable 64 Kbytes|
Registers|32 x 32-bit registers| 8 x 16-bit registers|
|`x0`|`zero`| `t0`|
| `li`, `bz`, `bnz`, `jr` and `j`| pseudo instructions | true instructions|
|immediate |signed 12 bits|signed 7 bits|
|L/S Offset| signed 12 bits| signed 4 bits|



## The registers
|Register| ABI Name| Usage|
| --- | --- | --- |
|x0 |t0 |Temporary register|
|x1 |ra |Return address|
|x2 |sp |Stack pointer|
|x3 |s0 |Saved register|
|x4 |s1 |Saved register|
|x5 |t1 |Temporary register|
|x6 |a0 |Argument/return value|
|x7 |a1 |Argument|

## The Instructions
<img src="docs/instr.png" alt="z16 Instructions Table" style="width:65%; height:auto;">