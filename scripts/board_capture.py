#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The board's video memories, read over JTAG, as a capture the benches and the model load.

    python scripts/board_capture.py sams64 hw1            # -> debug/sams64-hw1/
    python scripts/board_capture.py sams64 hw1 --only spriteram,spriteregs

Needs the stp revision (ISSP instance M, HyperNG64.sv). Reads go through the CPU's port of the
video bus between CPU requests, so the game keeps running: pause it (OSD) for a consistent set.
The files are big-endian dwords, as scripts/mame_capture.py writes them. VRAM is not on that bus:
videoram.bin is written as zeros so render_model.py runs; its tilemap layers mean nothing.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# name: (v_sel, dwords), hng64_vbus.sv
MEMS = {
    "spriteram":  (0, 12288),
    "spriteregs": (1, 5),
    "videoregs":  (2, 14),
    "palette":    (3, 4096),
    "tcram":      (4, 24),
    # the engine's copy (vbus u_spr_eng), taken at vblank: for comparing with spriteram
    "spriteram_eng": (5, 12288),
}


def dump(sel, count):
    r = subprocess.run([sys.executable, str(REPO / "scripts" / "read_issp.py"), "M", "dump",
                        "sel", str(sel), "from", "0", "count", str(count)],
                       cwd=REPO, capture_output=True, text=True)
    words = {}
    for ln in r.stdout.splitlines():
        m = re.fullmatch(r"([0-9A-F]{4}) ([0-9A-F]{8})", ln.strip())
        if m:
            words[int(m.group(1), 16)] = int(m.group(2), 16)
    if len(words) != count:
        sys.stdout.write(r.stdout[-1500:])
        sys.exit(f"sel {sel}: {len(words)} of {count} dwords read")
    return b"".join(words[k].to_bytes(4, "big") for k in range(count))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game")
    ap.add_argument("name")
    ap.add_argument("--only", help="comma-separated subset of " + ",".join(MEMS))
    a = ap.parse_args()
    out = REPO / "debug" / f"{a.game}-{a.name}"
    out.mkdir(parents=True, exist_ok=True)
    names = a.only.split(",") if a.only else list(MEMS)
    for n in names:
        sel, count = MEMS[n]
        (out / f"{n}.bin").write_bytes(dump(sel, count))
        print(f"{n}: {count} dwords")
    if not (out / "videoram.bin").exists():
        (out / "videoram.bin").write_bytes(bytes(0x80000))
    (out / "manifest.txt").write_text(f"set {a.game}\nboard capture (ISSP M)\nscreen 512x448\n")
    print(f"-> {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
