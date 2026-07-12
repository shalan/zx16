"""zx16cc port: su26-ext (UART + timer)."""

from __future__ import annotations

import re
from pathlib import Path

MACHINE = "su26-ext"
CRT0_SP = 0xEFFE
LIB_DIR = Path(__file__).resolve().parent / "lib"


def postprocess_asm(asm: str) -> str:
    asm2, n = re.subn(r"li16\s+x2,\s*0xF000", f"li16 x2, 0x{CRT0_SP:04X}", asm)
    if n == 0:
        asm2, n = re.subn(
            r"(li16\s+x2,\s*)0x[fF]000", rf"\g<1>0x{CRT0_SP:04X}", asm
        )
    banner = (
        f"# machine: {MACHINE}  (SP 0x{CRT0_SP:04X}, UART@C000 timer@D000)\n"
        f"# zx16cc port postprocess patches={n}\n"
    )
    return banner + asm2


def include_paths() -> list[Path]:
    return [LIB_DIR]


def default_prelude() -> str:
    return ""
