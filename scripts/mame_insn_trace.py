#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The first N main-CPU instructions from reset, from MAME's debugger trace.

    python scripts/mame_insn_trace.py <set> 200000 [--regs all | --regs sp,ra]
    -> debug/<set>-insn/<set>.tr

One line per instruction: `PC: disassembly`, prefixed with the listed registers when
--regs is given. MAME names MIPS registers by ABI name (`ra`, not `R31`); an unknown name
drops the prefix silently (r30 is `fp`, not `s8`). `all` is r1..r31 in index order, matching
`cpu_export.regs`. The
values are the state BEFORE the traced instruction executes. The reference the RTL CPU's per-instruction export (`cpu_export`) is
compared against.

Why not the bus taps (mame_boot_trace.py): hng64 maps main RAM, game ROM and BIOS
through the MIPS core's fastram (hng64.cpp:2170-2172), which bypasses Lua taps, so a tap
trace sees only I/O. The debugger trace sees every instruction.

MAME is run with -debug -debugger none; the trace is armed from an autoboot Lua script
(a -debugscript is not executed without a debugger UI). The trace runs far slower than
real time, so the run is stopped by line count, not emulated time.
"""
import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ABI = ["at", "v0", "v1", "a0", "a1", "a2", "a3", "t0", "t1", "t2", "t3", "t4", "t5", "t6", "t7",
       "s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7", "t8", "t9", "k0", "k1", "gp", "sp", "fp", "ra"]
sys.path.insert(0, str(REPO / "scripts"))
from mame_capture import NO_WINDOW, mame_paths, rompath  # noqa: E402


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("game")
    ap.add_argument("n", type=int, help="instructions to keep")
    ap.add_argument("--regs", default="", help="'all', or ABI register names, e.g. sp,ra")
    ap.add_argument("--cpu", default="maincpu")
    ap.add_argument("--timeout", type=int, default=1800, help="seconds before giving up")
    a = ap.parse_args()

    mame_dir, exe = mame_paths()
    out = REPO / "debug" / f"{a.game}-insn"
    out.mkdir(parents=True, exist_ok=True)
    tr = out / f"{a.game}.tr"
    raw = out / f"{a.game}.raw.tr"
    for f in (tr, raw):
        f.unlink(missing_ok=True)

    action = ""
    if a.regs:
        regs = ABI if a.regs == "all" else [r.strip() for r in a.regs.split(",") if r.strip()]
        fmt = " ".join("%016X" for _ in regs)
        action = ',{tracelog "' + fmt + ' ",' + ",".join(regs) + "}"
    lua = out / "arm.lua"
    lua.write_text(
        "local dbg = manager.machine.debugger\n"
        "if not dbg then print('INSN_NO_DEBUGGER') return end\n"
        f"dbg:command('trace {raw.as_posix()},{a.cpu},noloop{action}')\n"
        "dbg:command('go')\n"
        "print('INSN_ARMED')\n", encoding="utf-8")

    cmd = [str(exe), a.game, "-debug", "-debugger", "none", "-nowindow", "-video", "none",
           "-sound", "none", "-skip_gameinfo", "-nothrottle", "-autoboot_delay", "0",
           "-autoboot_script", str(lua), "-rompath", rompath(mame_dir)]
    p = subprocess.Popen(cmd, cwd=mame_dir, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, **NO_WINDOW)

    # Stop once the raw trace holds N lines. Bytes per line vary; poll a line count.
    t0, have = time.time(), 0
    while p.poll() is None and time.time() - t0 < a.timeout:
        time.sleep(2)
        if raw.exists():
            with open(raw, "rb") as f:
                have = sum(1 for _ in f)
            if have >= a.n:
                break
    if p.poll() is None:
        p.kill()
        p.wait()
    if not raw.exists():
        sys.exit("no trace written:\n" + p.stdout.read().decode(errors="replace")[-2000:])

    kept = 0
    with open(raw, encoding="utf-8", errors="replace") as src, open(tr, "w", encoding="utf-8") as dst:
        for line in src:
            if kept >= a.n:
                break
            dst.write(line)
            kept += 1
    raw.unlink()
    print(f"{kept} instructions -> {tr}")
    if kept < a.n:
        print(f"warning: MAME stopped or timed out after {kept} of {a.n}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
