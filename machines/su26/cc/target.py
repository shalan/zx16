"""
zx16cc port: su26

Hooks applied after generic zcc codegen:
  - CRT0 SP = 0xEFFE
  - entry at 0x0020 (codegen already emits .org 0x0020)
  - putint/putchar remain ecall intrinsics (INTRINSIC_IO=True)
"""

from __future__ import annotations

import re
from pathlib import Path

MACHINE = "su26"
CRT0_SP = 0xEFFE
LIB_DIR = Path(__file__).resolve().parent / "lib"


def postprocess_asm(asm: str) -> str:
    """Patch Green-Card-style crt0 SP to Su26 handout value."""
    asm2, n = re.subn(r"li16\s+x2,\s*0xF000", f"li16 x2, 0x{CRT0_SP:04X}", asm)
    if n == 0:
        asm2, n = re.subn(
            r"(li16\s+x2,\s*)0x[fF]000", rf"\g<1>0x{CRT0_SP:04X}", asm
        )
    banner = (
        f"# machine: {MACHINE}  (SP reset 0x{CRT0_SP:04X}, ecall I/O)\n"
        f"# zx16cc port postprocess patches={n}\n"
    )
    return banner + asm2


def include_paths() -> list[Path]:
    return [LIB_DIR]


def default_prelude() -> str:
    """Optional text prepended to user C (empty — users #include su26 headers)."""
    return ""
