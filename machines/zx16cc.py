#!/usr/bin/env python3
"""Multi-machine ZX16 C compiler driver (zcc + machine port).

  python3 -m machines.zx16cc --machine su26 foo.c -o foo
  # produces foo.s and foo.bin (if assembler found)
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path


def _find_zcc_root(repo: Path) -> Path:
    candidates = [
        repo / "compiler",
        repo / "tools" / "zx16-src" / "compiler",
    ]
    for c in candidates:
        if (c / "codegen.py").is_file():
            return c
    raise FileNotFoundError(
        "cannot find zcc (compiler/codegen.py); clone zx16 compiler next to machines/"
    )


def _find_assembler(repo: Path) -> Path | None:
    for c in (
        repo / "assembler" / "zx16asm.py",
        repo / "tools" / "zx16asm.py",
        repo / "tools" / "zx16-src" / "assembler" / "zx16asm.py",
    ):
        if c.is_file():
            return c
    return None


def main(argv: list[str] | None = None) -> int:
    repo = Path(__file__).resolve().parents[1]
    if str(repo) not in sys.path:
        sys.path.insert(0, str(repo))

    from machines.registry import list_machines, load_cc_target, resolve

    p = argparse.ArgumentParser(prog="zx16cc", description="ZX16 multi-machine C compiler")
    p.add_argument(
        "--machine",
        "-m",
        default="su26",
        help=f"machine port ({', '.join(list_machines())})",
    )
    p.add_argument("source", help="C source file")
    p.add_argument("-o", "--output", required=True, help="output prefix (writes .s and .bin)")
    p.add_argument("--no-bin", action="store_true", help="only emit assembly")
    args = p.parse_args(argv)

    src_path = Path(args.source)
    if not src_path.is_file():
        print(f"zx16cc: cannot open {src_path}", file=sys.stderr)
        return 1

    info = resolve(args.machine)
    target = load_cc_target(args.machine)
    zcc_root = _find_zcc_root(repo)
    sys.path.insert(0, str(zcc_root))
    import codegen  # type: ignore

    # machine wants ecall intrinsics for putchar/putint
    codegen.INTRINSIC_IO = True

    src = src_path.read_text()
    # include path: machine lib + source dir
    base_dir = str(src_path.parent)
    try:
        asm = codegen.compile_src(src, base_dir=base_dir)
    except Exception as e:
        print(f"zx16cc: compile failed: {e}", file=sys.stderr)
        return 2

    asm = target.postprocess_asm(asm)
    out_prefix = Path(args.output)
    asm_path = out_prefix.with_suffix(".s") if out_prefix.suffix != ".s" else out_prefix
    if out_prefix.suffix in (".bin", ".s"):
        asm_path = out_prefix.with_suffix(".s")
        bin_path = out_prefix.with_suffix(".bin")
    else:
        asm_path = Path(str(out_prefix) + ".s")
        bin_path = Path(str(out_prefix) + ".bin")

    asm_path.write_text(asm)
    print(f"[zx16cc] machine={info.name}  asm={asm_path}")

    if args.no_bin:
        return 0

    asm_tool = _find_assembler(repo)
    if not asm_tool:
        print("zx16cc: assembler not found; kept .s only", file=sys.stderr)
        return 0

    r = subprocess.run(
        [sys.executable, str(asm_tool), str(asm_path), "-o", str(bin_path), "-f", "bin"],
        capture_output=True,
        text=True,
    )
    if r.returncode != 0 or "fail" in r.stdout.lower():
        print(r.stdout, r.stderr, file=sys.stderr)
        print("zx16cc: assemble failed", file=sys.stderr)
        return 3
    print(f"[zx16cc] bin={bin_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
