#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build sim/boot_tb inputs from the MAME ROMs and a MAME system trace.

    python scripts/mame_sys_trace.py hng64 120      # I/O reference (once)
    python scripts/prep_boot_tb.py [--set hng64] [--bios brom1.bin] [--reads 400000]

Writes, for $readmemh from the repository root:
  sim/boot_tb/bios.hex      512 KB BIOS as 64-bit beats, bytes in address order, byte k at
                            [8k+7:8k] (docs/HARDWARE_NOTES.md, byte order)
  sim/boot_tb/io_replay.hex the first --reads I/O reads MAME's CPU made, in order:
                            one 64-bit word per read: word address (63:32), big-endian data
                            as MAME's tap saw it (31:0)
"""
import argparse
import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
from mame_capture import load_env  # noqa: E402


def find_zip(name):
    import os
    paths = [REPO / "roms"] + [Path(p) for p in
             os.environ.get("MAME_ROMPATH", load_env().get("MAME_ROMPATH", "")).split(";") if p]
    for d in paths:
        z = d / f"{name}.zip"
        if z.exists():
            return z
    sys.exit(f"{name}.zip not found in roms/ or MAME_ROMPATH")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--set", default="hng64", help="set whose system trace is replayed")
    ap.add_argument("--bios", default="brom1.bin", help="BIOS file in hng64.zip (brom1.bin = Japan)")
    ap.add_argument("--reads", type=int, default=400000)
    a = ap.parse_args()
    out = REPO / "sim" / "boot_tb"
    out.mkdir(parents=True, exist_ok=True)

    bios = zipfile.ZipFile(find_zip("hng64")).read(a.bios)
    assert len(bios) == 0x80000, len(bios)
    with open(out / "bios.hex", "w") as f:
        for i in range(0, len(bios), 8):
            f.write(int.from_bytes(bios[i:i + 8], "little").to_bytes(8, "big").hex() + "\n")

    trace = REPO / "debug" / f"{a.set}-sys" / f"{a.set}_sys.trace"
    if not trace.exists():
        sys.exit(f"{trace} missing: run scripts/mame_sys_trace.py {a.set} 120 first")
    n = 0
    with open(trace) as src, open(out / "io_replay.hex", "w") as dst:
        for line in src:
            if line[0] == "#":
                continue
            p = line.split("\t")
            if p[1] != "r":
                continue
            dst.write(f"{int(p[2], 16) & ~3:08x}{int(p[4], 16):08x}\n")
            n += 1
            if n >= a.reads:
                break
    print(f"bios.hex: {len(bios) // 8} beats; io_replay.hex: {n} reads from {trace.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
