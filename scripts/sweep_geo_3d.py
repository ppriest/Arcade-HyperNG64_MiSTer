#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Sweep one geometry stage's width at a time (scripts/render_3d_fx.py GEO), the rest ideal, and
print the 3D buffer's difference from the float model per width.

    python scripts/sweep_geo_3d.py sams64 2500 eye=10,12,14,16 rcp=8,10,12
"""
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import render_3d as r3          # noqa: E402
import render_3d_fx as fx       # noqa: E402


def buffer_diff(game, frame):
    d = r3.REPO / "debug" / f"{game}-f{frame}"
    wl = d / "wlog.trace"
    res = r3.run(game, [frame], trace=wl, capture=True) if wl.exists() else r3.run(game, [frame])
    c = res[frame][0].astype(np.int64)
    f = np.fromfile(d / "model3d.bin", dtype="<u2").astype(np.int64)
    return int((c != f).sum())


def main():
    game, frame = sys.argv[1], int(sys.argv[2])
    r3.Renderer = fx.FxRenderer
    r3.Machine = fx.FxMachine
    print(f"{game} {frame}, all ideal: {buffer_diff(game, frame)}")
    for spec in sys.argv[3:]:
        key, widths = spec.split("=")
        row = []
        for w in widths.split(","):
            fx.GEO[key] = int(w)
            row.append(f"{w}: {buffer_diff(game, frame)}")
        fx.GEO[key] = None
        print(f"  {key:6s} " + "  ".join(row))


if __name__ == "__main__":
    main()
