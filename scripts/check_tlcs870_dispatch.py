#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compare scripts/tlcs870_ucode.py's decode with MAME's TLCS-870 dispatch, opcode by opcode.

    python scripts/check_tlcs870_dispatch.py [path/to/mame/src/devices/cpu/tlcs870]

For each family (no prefix, register prefix e8-ef, source prefix e0-e7, destination prefix f0-f7)
and each opcode byte: MAME's `switch` either calls a handler or falls to its illegal-opcode one,
and our decode either names a program or a NOP. A byte one side executes and the other ignores is
reported. The `switch` is read, not the comment tables beside it: the destination family's table
says LD (dst),r is 0101 1rrr, the dispatch takes 0x50-0x57, and the firmware uses the latter
(docs/LESSONS_LEARNED.md). Presence only: which program an opcode maps to is not compared.
"""
import importlib.util
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
MAME = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("E:/mame/src/devices/cpu/tlcs870")


def mame_table(fname, start_pat):
    src = (MAME / fname).read_text(encoding="utf-8")
    j = src.index("{", src.index(start_pat))
    depth, k = 0, j
    while True:
        if src[k] == "{":
            depth += 1
        elif src[k] == "}":
            depth -= 1
            if depth == 0:
                break
        k += 1
    table, pending = {}, []
    for line in src[j:k].splitlines():
        pending += [int(c, 16) for c in re.findall(r"case\s+0x([0-9a-fA-F]+)\s*:", line)]
        m = re.search(r"\b(do_\w+)\s*\(", line)
        if m and pending:
            for c in pending:
                table[c] = m.group(1)
            pending = []
    return table


def main():
    spec = importlib.util.spec_from_file_location("ucode", REPO / "scripts" / "tlcs870_ucode.py")
    u = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(u)
    families = [
        ("no prefix", mame_table("tlcs870_ops.cpp", "switch (opbyte0)"), u.d_base),
        ("register prefix", mame_table("tlcs870_ops_reg.cpp", "switch (opbyte1)"), u.d_reg),
        ("source prefix", mame_table("tlcs870_ops_src.cpp", "switch (opbyte1)"), u.d_src),
        ("destination prefix", mame_table("tlcs870_ops_dst.cpp", "switch (opbyte1)"), u.d_dst),
    ]
    bad = 0
    for name, mt, ours in families:
        for o in range(256):
            if name == "no prefix" and 0xe0 <= o <= 0xf7:
                continue                                    # the prefixes themselves
            prog = ours(o)[0]
            ours_runs = prog not in (u.NOP, "unimpl") or o == 0x00 and name == "no prefix"
            mh = mt.get(o)
            mame_runs = mh is not None and "illegal" not in mh
            if ours_runs != mame_runs:
                print(f"{name} {o:02x}: MAME {mh or 'illegal'}, ours {prog}")
                bad += 1
    print(f"{bad} opcode(s) differ")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
