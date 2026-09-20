#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Find frames that use a given video feature, by sampling the registers every frame.

    python scripts/scan_video.py buriki --frames 3600
    python scripts/scan_video.py buriki --report        # re-read an existing scan

Writes debug/scan/<set>.csv and prints, per feature, the frames where it is active. The point
is to pick capture frames for paths no frame in hand exercises, rather than guessing from
MAME's comments (docs/phase1_video.md).
"""
import argparse
import os
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
from mame_capture import mame_paths, mame_cmd, NO_WINDOW  # noqa: E402

# name -> (needs, test on a row dict)
FEATURES = {
    "split screen":        lambda r: r["v"][0x00] & 1,
    "split screen bit 1":  lambda r: r["v"][0x00] & 2,
    "alt dimensions":      lambda r: (r["v"][0x00] >> 24) & 3,
    "alt scroll (rotate)": lambda r: r["v"][0x00] & 0x04000000,
    "zoom disable":        lambda r: r["v"][0x00] & 0x00010000,
    "auto-animation":      lambda r: r["v"][0x01] & 0x00010000,
    "tilemap additive L1": lambda r: r["tc0c"] & (1 << 2),
    "tilemap additive L0": lambda r: r["tc0c"] & (1 << 26),
    "sprite alpha (not add)": lambda r: r["tc4c"] & (1 << 16),
    "palette output off":  lambda r: r["tc24"] & (1 << 17),
    "sprite blend bits":   lambda r: r["spr"][0],
    "no 3D blit (fb0.0)":  lambda r: r["fb"] & 0x01000000,
    "sprite checkerboard": lambda r: r["spr"][1],
    "sprite mosaic":       lambda r: r["spr"][2],
}


def tilereg(v, tm):
    w = v[0x02 + (tm >> 1)]
    return (w & 0xFFFF) if (tm & 1) else (w >> 16)


def parse(path):
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        p = line.split(",")
        if len(p) < 22:
            continue
        r = {
            "frame": int(p[0]),
            "v": [int(x, 16) for x in p[1:15]],
            "tc0c": int(p[15], 16),
            "tc24": int(p[16], 16),
            "tc4c": int(p[17], 16),
            "sr": [int(p[18], 16), int(p[19], 16)],
            "fb": int(p[20], 16),
            "spr": [int(x) if x else 0 for x in p[21:25]],
        }
        rows.append(r)
    return rows


def spans(frames):
    """[1,2,3,9,10] -> "1-3, 9-10"."""
    out, start, prev = [], None, None
    for f in frames:
        if start is None:
            start, prev = f, f
        elif f - prev > 2:
            out.append((start, prev))
            start = f
        prev = f
    if start is not None:
        out.append((start, prev))
    return ", ".join(f"{a}-{b}" if a != b else str(a) for a, b in out[:8]) + \
           (" ..." if len(out) > 8 else "")


def report(rows):
    for name, test in FEATURES.items():
        hits = [r["frame"] for r in rows if test(r)]
        if hits:
            print(f"  {name:24s} {len(hits):5d} frames: {spans(hits)}")
    mos = [r["frame"] for r in rows
           if any(tilereg(r["v"], tm) >> 12 and (tilereg(r["v"], tm) >> 6) & 1 for tm in range(4))]
    if mos:
        print(f"  {'tilemap mosaic':24s} {len(mos):5d} frames: {spans(mos)}")
    for tm in range(4):
        en = [r["frame"] for r in rows if (tilereg(r["v"], tm) >> 6) & 1]
        if en:
            regs = sorted({tilereg(r["v"], tm) for r in rows if (tilereg(r["v"], tm) >> 6) & 1})
            print(f"  tm{tm} enabled {len(en):5d} frames, tileregs seen: "
                  + " ".join(f"{x:04x}" for x in regs[:12]))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("set")
    ap.add_argument("--frames", type=int, default=3600)
    ap.add_argument("--sprite-step", type=int, default=30)
    ap.add_argument("--report", action="store_true", help="do not re-run MAME")
    a = ap.parse_args()

    out = REPO / "debug" / "scan" / f"{a.set}.csv"
    out.parent.mkdir(parents=True, exist_ok=True)

    if not a.report:
        mame_dir, exe = mame_paths()
        seconds = a.frames // 60 + 10
        cmd = mame_cmd(exe, a.set, "scanvideo.lua", mame_dir, ["-seconds_to_run", str(seconds)])
        env = dict(os.environ, CORE_OUT=out.as_posix(), CORE_FRAMES=str(a.frames),
                   CORE_SPRSTEP=str(a.sprite_step))
        print(f"{a.set}: scanning {a.frames} frames -> {out}")
        p = subprocess.run(cmd, cwd=mame_dir, env=env, capture_output=True, text=True, **NO_WINDOW)
        if "CORE_SCAN_OK" not in (p.stdout + p.stderr) and not out.exists():
            sys.exit("scan did not complete:\n" + (p.stdout + p.stderr)[-1500:])

    rows = parse(out)
    print(f"{a.set}: {len(rows)} frames")
    report(rows)
    return 0


if __name__ == "__main__":
    sys.exit(main())
