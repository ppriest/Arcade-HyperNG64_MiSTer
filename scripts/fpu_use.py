#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Does a game use the VR4300's FPU, and its TLB, in attract and in play?

    python scripts/fpu_use.py sams64 [fatfurwa ...] [--frames 4000] [--coin 1500] [--rerun]

Runs MAME with scripts/mame/fpuuse.lua (debug/fpuuse-<set>.txt), then counts the frames in which
any FPU register changed and the frames in which Status or the TLB-facing COP0 registers changed:
before the coin, and from Start (coin + 96, when play input begins).
"""
import argparse
import os
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import mame_capture as mc  # noqa: E402

REPO = Path(__file__).resolve().parent.parent


def run(game, frames, coin):
    mame_dir, exe = mc.mame_paths()
    out = (REPO / "debug" / f"fpuuse-{game}.txt").as_posix()
    cmd = mc.mame_cmd(exe, game, "fpuuse.lua", mame_dir, ["-seconds_to_run", str(frames // 20 + 30)])
    env = dict(os.environ, FU_OUT=out, FU_FRAMES=str(frames), FU_COIN=str(coin))
    subprocess.run(cmd, cwd=mame_dir, env=env, capture_output=True, text=True, **mc.NO_WINDOW)


def summarise(game, coin):
    path = REPO / "debug" / f"fpuuse-{game}.txt"
    lines = path.read_text().splitlines()
    fpu_names = cop0_names = None
    prev_f = prev_c = None
    fpu_frames = {"attract": 0, "play": 0}
    cop0_frames = {"attract": 0, "play": 0}
    last = 0
    done = False
    for ln in lines:
        w = ln.split()
        if w[0] == "fpu":
            fpu_names = w[1:]
        elif w[0] == "cop0":
            cop0_names = w[1:]
        elif w[0] == "frame":
            n, cs, fs = int(w[1]), w[3], w[5]
            phase = "play" if coin and n >= coin + 96 else "attract"
            if prev_f is not None and fs != prev_f:
                fpu_frames[phase] += 1
            if prev_c is not None and cs != prev_c:
                cop0_frames[phase] += 1
            prev_f, prev_c, last = fs, cs, n
        elif w[0] == "done":
            done = True
    print(f"{game}: {last} frames{'' if done else ' (did not finish)'}; frames with an FPU register "
          f"changed: {fpu_frames['attract']} before play, {fpu_frames['play']} in play; "
          f"COP0 ({','.join(cop0_names or [])}) changed: {cop0_frames['attract']} / {cop0_frames['play']}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sets", nargs="+")
    ap.add_argument("--frames", type=int, default=4000)
    ap.add_argument("--coin", type=int, default=1500)
    ap.add_argument("--rerun", action="store_true")
    a = ap.parse_args()
    for g in a.sets:
        if a.rerun or not (REPO / "debug" / f"fpuuse-{g}.txt").exists():
            run(g, a.frames, a.coin)
        summarise(g, a.coin)


if __name__ == "__main__":
    main()
