#!/usr/bin/env python3
"""Multi-machine ZX16 simulator CLI.

  python3 -m machines.zx16sim --machine su26 prog.bin
  python3 -m machines.zx16sim --machine su26-ext prog.bin --gui
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def main(argv: list[str] | None = None) -> int:
    root = Path(__file__).resolve().parents[1]
    if str(root) not in sys.path:
        sys.path.insert(0, str(root))

    from machines.registry import list_machines, load_sim_class, resolve

    p = argparse.ArgumentParser(prog="zx16sim", description="ZX16 multi-machine ISS")
    p.add_argument(
        "--machine",
        "-m",
        default="su26",
        help=f"machine profile ({', '.join(list_machines())})",
    )
    p.add_argument("binary", help=".bin image (64KB or raw @0x0020)")
    p.add_argument("-t", "--trace", action="store_true")
    p.add_argument("-n", "--max-cycles", type=int, default=50_000_000)
    p.add_argument(
        "--gui",
        action="store_true",
        help="interactive browser debugger (uses enhanced gfx for su26-ext)",
    )
    p.add_argument("--port", type=int, default=8765, help="GUI HTTP port")
    p.add_argument(
        "--scale",
        type=int,
        default=1,
        help="display pixel scale (default 1 for live speed; try 2 for sharper)",
    )
    p.add_argument(
        "--no-browser",
        action="store_true",
        help="do not auto-open browser for --gui",
    )
    args = p.parse_args(argv)

    info = resolve(args.machine)
    Sim = load_sim_class(args.machine)
    sim = Sim()
    sim.trace = args.trace
    sim.max_cycles = args.max_cycles
    path = Path(args.binary)
    if not path.is_file():
        print(f"zx16sim: cannot open {path}", file=sys.stderr)
        return 1
    sim.load_bin_file(str(path))
    print(f"[zx16sim] machine={info.name}  file={path}", flush=True)

    if args.gui:
        # Browser debugger (self-contained under machines/)
        try:
            from machines.gui_debug import run_gui_until_exit, start_gui
        except ImportError as e:
            print(
                "zx16sim: GUI debugger unavailable "
                f"({e}). Install a browser-capable Python and retry.",
                file=sys.stderr,
            )
            return 1

        session = start_gui(
            sim,
            str(path.resolve()),
            port=args.port,
            scale=args.scale,
            open_browser=not args.no_browser,
            title=info.name,
        )
        run_gui_until_exit(session)
        return 0

    try:
        sim.run(args.max_cycles)
    except Exception as e:
        print(f"zx16sim: {e}", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
