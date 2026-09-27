#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The ranges MAME's float 3D values take on captured frames: the input to the fixed-point design.

    python scripts/ranges_3d.py sams64 600 2500 5000

Runs scripts/render_3d.py's float model with its arithmetic observed at each stage, and prints,
per quantity, the smallest and largest magnitude seen (zeros aside), so a fixed-point format can be
chosen with its integer bits from the maximum and its fraction bits from the minimum that matters.
"""
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import render_3d as r3  # noqa: E402

REPO = Path(__file__).resolve().parent.parent


class Range:
    def __init__(self):
        self.lo = math.inf
        self.hi = 0.0
        self.n = 0
        self.neg = False

    def add(self, v):
        v = np.asarray(v, dtype=np.float64).ravel()
        v = v[np.isfinite(v)]
        if not v.size:
            return
        a = np.abs(v)
        nz = a[a > 0]
        self.n += v.size
        self.neg |= bool((v < 0).any())
        self.hi = max(self.hi, float(a.max()))
        if nz.size:
            self.lo = min(self.lo, float(nz.min()))

    def fmt(self):
        ib = math.ceil(math.log2(self.hi)) + 1 if self.hi > 0 else 0
        fb = -math.floor(math.log2(self.lo)) if self.lo < math.inf else 0
        return (f"|x| {self.lo:.3g} .. {self.hi:.6g}  (sign {'yes' if self.neg else 'no '}, "
                f"integer bits {max(ib, 0)}, fraction bits to the smallest {fb})  n={self.n}")


R = {}


def rec(name, v):
    R.setdefault(name, Range()).add(v)


def instrument():
    orig_proj = r3.Machine.set_projection

    def set_projection(self, pk):
        orig_proj(self, pk)
        rec("projection matrix", [self.projection[i] for i in (0, 5, 8, 9, 10, 14)])
    r3.Machine.set_projection = set_projection

    orig_tf = r3.Machine.transform

    def transform(self, p, pk, obj):
        rec("object matrix", obj)
        if not self.samsho_hack:
            rec("camera matrix", self.camera)
        orig_tf(self, p, pk, obj)
        mv = self.modelview
        for m in range(3):
            eye = r3.vecmatmul4(mv, p.vert[m].world)
            rec("eye xyz", eye[:3])
            clip = r3.vecmatmul4(self.projection, eye)
            rec("clip xyzw", clip)
            rec("clip w", clip[3])
            rec("light (per vertex)", p.vert[m].light)
        if p.visible:
            for m in range(p.n):
                v = p.vert[m]
                rec("screen x", v.clip[0])
                rec("screen y", v.clip[1])
                rec("screen z (0-1)", v.clip[2])
                rec("w after clip", v.clip[3])
    r3.Machine.transform = transform

    orig_ds = r3.Renderer.draw_shaded

    def draw_shaded(self, p):
        orig_ds(self, p)
        if not p.flat:
            for m in range(p.n):
                v = p.vert[m]
                rec("1/w", v.clip[3])
                rec("u/w, v/w", v.tex)
                rec("light/w", v.light)
    r3.Renderer.draw_shaded = draw_shaded

    orig_tri = r3.Renderer.triangle

    def triangle(self, v1, v2, v3, nparams, scan):
        def wrapped(y, x0, x1, start, dpdx):
            if nparams == 7 and x1 > x0:
                rec("dz/dx", dpdx[0])
                rec("d(1/w)/dx", dpdx[1])
                rec("d(u/w)/dx", dpdx[5:7])
                rec("span length", x1 - x0)
            scan(y, x0, x1, start, dpdx)
        orig_tri(self, v1, v2, v3, nparams, wrapped)
    r3.Renderer.triangle = triangle


def main():
    game = sys.argv[1]
    frames = [int(f) for f in sys.argv[2:]]
    instrument()
    for f in frames:
        d = REPO / "debug" / f"{game}-f{f}"
        wl = d / "wlog.trace"
        if wl.exists():
            r3.run(game, [f], trace=wl, capture=True)
        else:
            r3.run(game, [f])
    for k in R:
        print(f"{k:20s} {R[k].fmt()}")


if __name__ == "__main__":
    main()
