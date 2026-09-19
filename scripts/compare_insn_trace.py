#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Diff the RTL CPU's instruction trace against MAME's.

    python scripts/compare_insn_trace.py hng64 [--context 4]

Inputs, one line per instruction, r1..r31 then `PC: ...`:
  debug/<set>-insn/<set>.tr   MAME (scripts/mame_insn_trace.py --regs all): registers BEFORE
                              the instruction executes
  debug/<set>-insn/rtl.tr     the boot bench (sim/boot_tb): registers as the export reports them

Leading RTL lines with PC 0 (export before the first retire) are dropped. Whether the RTL export
is the state before or after its instruction is measured on the first lines, not assumed; the
comparison uses whichever alignment matches. Reports the first PC or register divergence.
"""
import argparse
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ABI = ["at", "v0", "v1", "a0", "a1", "a2", "a3", "t0", "t1", "t2", "t3", "t4", "t5", "t6", "t7",
       "s0", "s1", "s2", "s3", "s4", "s5", "s6", "s7", "t8", "t9", "k0", "k1", "gp", "sp", "fp", "ra"]


def load(path):
    rows = []
    for line in open(path, encoding="utf-8", errors="replace"):
        p = line.split()
        if len(p) < 32 or not p[31].endswith(":"):
            continue
        regs = [int(x, 16) for x in p[:31]]
        pc = int(p[31][:-1], 16) & 0xFFFFFFFF
        rows.append((pc, regs, " ".join(p[32:])))
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("set")
    ap.add_argument("--context", type=int, default=4)
    a = ap.parse_args()
    d = REPO / "debug" / f"{a.set}-insn"
    mame, rtl = load(d / f"{a.set}.tr"), load(d / "rtl.tr")
    while rtl and rtl[0][0] == 0:
        rtl.pop(0)
    if not rtl:
        sys.exit("empty RTL trace")

    # Align on the RTL's first PC (the export of the very first instruction may carry PC 0).
    off = next((j for j in range(min(len(mame), 64)) if mame[j][0] == rtl[0][0]), None)
    if off is None:
        sys.exit(f"RTL's first PC {rtl[0][0]:08X} not in MAME's first 64 instructions")
    mame = mame[off:]
    if off:
        print(f"skipped {off} MAME instruction(s) before the RTL's first exported PC")

    # before-state: rtl[i].regs == mame[i].regs; after-state: rtl[i].regs == mame[i+1].regs
    probe = min(200, len(rtl), len(mame) - 1)
    before = sum(rtl[i][1] == mame[i][1] for i in range(probe))
    after = sum(rtl[i][1] == mame[i + 1][1] for i in range(probe))
    shift = 1 if after > before else 0
    print(f"export is the state {'after' if shift else 'before'} its instruction "
          f"(matched {max(before, after)} of {probe} probe lines)")

    n = min(len(rtl), len(mame) - shift)
    for i in range(n):
        pc_ok = rtl[i][0] == mame[i][0]
        regs_m = mame[i + shift][1]
        bad = [k for k in range(31) if rtl[i][1][k] != regs_m[k]]
        if pc_ok and not bad:
            continue
        print(f"DIVERGENCE at instruction {i + 1}:")
        for j in range(max(0, i - a.context), min(n, i + 2)):
            flag = "  <--" if j == i else ""
            print(f"  #{j + 1:<7} MAME {mame[j][0]:08X} {mame[j][2]:<28} RTL {rtl[j][0]:08X}{flag}")
        if not pc_ok:
            print(f"  PC: MAME {mame[i][0]:08X}, RTL {rtl[i][0]:08X}")
        for k in bad:
            print(f"  {ABI[k]:>2}: MAME {regs_m[k]:016X}, RTL {rtl[i][1][k]:016X}")
        return 1
    print(f"MATCH: {n} of {n} instructions agree in PC and all 31 registers")
    return 0


if __name__ == "__main__":
    sys.exit(main())
