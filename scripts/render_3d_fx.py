#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The 3D rasteriser in fixed point: how far from MAME's float frames a hardware one would land.

    python scripts/render_3d_fx.py sams64 600 2500 5000

scripts/render_3d.py's machine and geometry, float as MAME's, feed a rasteriser that keeps MAME's
structure (poly.h: scanline extents with round_coordinate, parameters from the plane through the
three vertices, one pixel at a time) but in integers, in the formats SpinalVoodoo's rasteriser uses
(docs/ROADMAP.md, 3D open items):

    vertex x, y     12.XY_F, rounded from MAME's float window coordinates (Voodoo: 12.4)
    z               z * 2^28: Voodoo's 20.12 with z scaled by 2^16
    1/w             (1/w) / 16 in 2.30, so 1/w * 2^26: 1/w reaches 49 (scripts/ranges_3d.py)
    u/w, v/w        14.18 of (u/w) * 64, the same 1/16 scaling in texels: * 2^24
    light/w         12.12 of (light/w) / 16: * 2^8

Each parameter's gradients are rounded to the parameter's own format, the value at a pixel centre
is the one at vertex 1 plus the gradients times the offset (floored), and each pixel adds dP/dx.
The per-pixel divides (texel = (u/w) / (1/w)) are exact: the best a hardware divider could do, so
the frames measure the formats and not a reciprocal table.
"""
import argparse
import sys
from fractions import Fraction
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import render_3d as r3  # noqa: E402

REPO = Path(__file__).resolve().parent.parent

XY_F = 12                                         # vertex fraction bits: 4 is Voodoo's, too few (phase3_3d.md)
SCALE = {0: 1 << 28, 1: 1 << 26, 2: 1 << 8, 5: 1 << 24, 6: 1 << 24}   # by MAME parameter index
DEPTH_CLEAR = 100 << 28                           # clear3d's 100.0 in the z format
PIX_RCP = None      # per-pixel reciprocal of 1/w, mantissa bits; None divides exactly


# Geometry widths, fraction bits (absolute) or mantissa bits (relative, for the reciprocal and
# the normalise); None leaves that stage in float64, the ideal the widths are measured against.
GEO = {
    "mv": None,         # model-view entries (camera x object products)
    "proj": None,       # projection matrix entries, from the 0x0012 packet
    "eye": None,        # eye coordinates
    "clip": None,       # clip coordinates
    "t": None,          # the clipper's interpolation factor
    "rcp": None,        # 1/w, mantissa bits: x/w, y/w, z/w and the texture parameters multiply by it
    "rsq": None,        # 1/|n| for the normalise, mantissa bits
    "light": None,      # the per-vertex light, 0-255
}


def qa(v, bits):
    """To `bits` fraction bits, nearest; None leaves it."""
    if bits is None:
        return float(v)
    return float(np.floor(float(v) * (1 << bits) + 0.5)) / (1 << bits)


def qm(v, bits):
    """To `bits` mantissa bits, nearest: a reciprocal or root unit's output."""
    v = float(v)
    if bits is None or v == 0.0 or not np.isfinite(v):
        return v
    m, e = np.frexp(v)
    return float(np.ldexp(np.floor(m * (1 << bits) + 0.5) / (1 << bits), e))


def _lg(v):
    return v.bit_length() - 1


def q(v, scale):
    """Round to nearest, as a setup unit converting MAME's float would."""
    return int(np.floor(float(v) * scale + 0.5))


def round_coord(v):
    """poly.h round_coordinate on an exact value in pixels."""
    ip = v.numerator // v.denominator
    return ip + (1 if v - ip > Fraction(1, 2) else 0)


class FxRenderer(r3.Renderer):
    def __init__(self, textures):
        super().__init__(textures)
        self.depth = np.zeros(512 * 512, dtype=np.int64)

    def clear(self):
        self.depth[:] = DEPTH_CLEAR
        self.color[:] = 0

    def triangle(self, v1, v2, v3, nparams, scan):
        params = [k for k in (0, 1, 2, 5, 6) if k < nparams]
        vs = []
        for v in (v1, v2, v3):
            vs.append((q(v[0], 1 << XY_F), q(v[1], 1 << XY_F),
                       {k: q(v[2][k], SCALE[k]) for k in params}))
        vs.sort(key=lambda t: t[1])                      # by y, stable, as MAME's swaps order it
        (x1, y1, p1), (x2, y2, p2), (x3, y3, p3) = vs
        one = 1 << XY_F
        v1y = round_coord(Fraction(y1, one))
        v3y = round_coord(Fraction(y3, one))
        v1yclip = max(v1y, 0)
        v3yclip = min(v3y, 513)
        if v3yclip - v1yclip <= 0:
            self.stats.add("triangles_empty")
            return
        self.stats.add("triangles")

        # plane through the three vertices, in vertex units; gradients per pixel, in each format
        a00, a10, a20 = y2 - y3, y3 - y1, y1 - y2
        a01, a11, a21 = x3 - x2, x1 - x3, x2 - x1
        det = x1 * (y2 - y3) + x2 * (y3 - y1) + x3 * (y1 - y2)
        dpdx, dpdy = {}, {}
        for k in params:
            if det == 0:
                dpdx[k] = dpdy[k] = 0
            else:
                dpdx[k] = round(Fraction(one * (p1[k] * a00 + p2[k] * a10 + p3[k] * a20), det))
                dpdy[k] = round(Fraction(one * (p1[k] * a01 + p2[k] * a11 + p3[k] * a21), det))

        for cur in range(v1yclip, v3yclip):
            fy = cur * one + one // 2                     # the scanline's centre, in vertex units
            sx = Fraction(x1) + Fraction((fy - y1) * (x3 - x1), (y3 - y1)) if y3 != y1 else Fraction(x1)
            if fy < y2:
                ex = Fraction(x1) + Fraction((fy - y1) * (x2 - x1), (y2 - y1)) if y2 != y1 else Fraction(x1)
            else:
                ex = Fraction(x2) + Fraction((fy - y2) * (x3 - x2), (y3 - y2)) if y3 != y2 else Fraction(x2)
            ix0 = round_coord(sx / one)
            ix1 = round_coord(ex / one)
            if ix0 > ix1:
                ix0, ix1 = ix1, ix0
            ix0 = max(ix0, 0)
            ix1 = min(ix1, 513)
            if ix0 >= ix1:
                ix0 = ix1 = 0
            fx = ix0 * one + one // 2
            start = {k: p1[k] + (((fx - x1) * dpdx[k] + (fy - y1) * dpdy[k]) >> XY_F) for k in params}
            scan(cur, ix0, ix1, start, dpdx)

    @staticmethod
    def _walk_i(start, d, n):
        return start + np.arange(n, dtype=np.int64) * d

    def flat_scan(self, rd):
        def scan(y, x0, x1, start, dpdx):
            if y > 511 or y < 0 or x0 >= x1:
                return
            z = self._walk_i(start[0], dpdx[0], x1 - x0)
            color = (rd.pal_offset + rd.color_index) & 0xFFFF
            self._plot(y, x0, x1, z, np.full(x1 - x0, color, dtype=np.uint16),
                       np.ones(x1 - x0, dtype=bool))
        return scan

    def texture_scan(self, rd):
        base = rd.tex_index * 1024 * 1024
        sub = (rd.tex_page_small & 0xC000) >> 14
        hoff = (rd.tex_page_small & 0x3F80) >> 7
        voff = rd.tex_page_small & 0x007F
        sy = (rd.texscrolly & 0x3FFF) >> 5
        sx = (rd.texscrollx & 0x3FFF) >> 5

        def scaled_div(a, b, sh):
            """C's (int) of a * 2^sh / b, toward zero, the shift put on whichever side keeps
            64 bits; b > 0 in practice (w > 0 after clipping)."""
            a = np.asarray(a, dtype=np.int64)
            b = np.asarray(b, dtype=np.int64)
            if sh >= 0:
                a = a << sh
            else:
                b = b << -sh
            qn = np.abs(a) // np.maximum(np.abs(b), 1)
            return np.where((a < 0) != (b < 0), -qn, qn)

        def scan(y, x0, x1, start, dpdx):
            if y > 511 or y < 0 or x0 >= x1:
                return
            n = x1 - x0
            z = self._walk_i(start[0], dpdx[0], n)
            w = self._walk_i(start[1], dpdx[1], n)
            light = self._walk_i(start[2], dpdx[2], n)
            s = self._walk_i(start[5], dpdx[5], n)
            t = self._walk_i(start[6], dpdx[6], n)
            # texel = (u/w) / (1/w) * 1024 = (S / Ss) / (W / Ws) * 2^10
            if PIX_RCP is None:
                ts = scaled_div(s, w, _lg(SCALE[1]) + 10 - _lg(SCALE[5])) + sy
                tt = scaled_div(t, w, _lg(SCALE[1]) + 10 - _lg(SCALE[6])) + sx
            else:
                # w reciprocal to PIX_RCP mantissa bits, then a multiply, truncated as (int)
                m, e = np.frexp(1.0 / np.maximum(w, 1).astype(np.float64))
                rw = np.ldexp(np.floor(m * (1 << PIX_RCP) + 0.5) / (1 << PIX_RCP), e)
                ts = np.trunc(s * rw * 2.0 ** (_lg(SCALE[1]) + 10 - _lg(SCALE[5]))).astype(np.int64) + sy
                tt = np.trunc(t * rw * 2.0 ** (_lg(SCALE[1]) + 10 - _lg(SCALE[6]))).astype(np.int64) + sx
            if sub & 2:
                tt = np.fmod(tt, rd.tex_mask_x) + 8 * hoff
                ts = np.fmod(ts, rd.tex_mask_y) + 8 * voff
            ti = tt & 1023
            si = ts & 1023
            if rd.tex4bpp:
                b = self.tex[base + si * 512 + (ti >> 1)]
                pen = np.where(ti & 1, (b >> 4) & 0x0F, b & 0x0F)
            else:
                pen = self.tex[base + si * 1024 + ti]
            # light = (L / Ls) / (W / Ws); MAME keeps light / 16
            lightval = scaled_div(light, w, _lg(SCALE[1]) - 4 - _lg(SCALE[2])) & 0xFF
            color = (((rd.pal_offset + pen.astype(np.int64)) & 0x7FF) | (lightval << 12)) & 0xFFFF
            if rd.blend:
                color |= 0x800
            self._plot(y, x0, x1, z, color.astype(np.uint16), pen != 0)
        return scan


class FxMachine(r3.Machine):
    """recoverPolygonBlock's geometry with each stage's result rounded to GEO's widths. The
    arithmetic between roundings is float64, standing for exact fixed-point products and sums."""

    def set_projection(self, pk):
        super().set_projection(pk)
        self.projection = [qa(v, GEO["proj"]) for v in self.projection]

    def transform(self, p, pk, obj):
        def mat(a, b):
            return [qa(v, GEO["mv"]) for v in _mm(a, b)]
        mv = [float(v) for v in r3.identity()]
        if not self.samsho_hack:
            mv = mat(mv, [float(v) for v in self.camera])
        mv = mat(mv, [float(v) for v in obj])
        self.modelview = mv

        def normalize(x):
            n = qm(1.0 / np.sqrt(x[0] * x[0] + x[1] * x[1] + x[2] * x[2]), GEO["rsq"])
            return [x[0] * n, x[1] * n, x[2] * n]

        if pk[1] & 0x0008 and self.light_strength > 0.0:
            self.r.stats.add("lit")
            lv = normalize([float(v) for v in self.light_vec])
            for v in range(3):
                tn = normalize(_vm([float(x) for x in obj], [float(x) for x in p.vert[v].normal]))
                inten = -(tn[0] * lv[0] + tn[1] * lv[1] + tn[2] * lv[2])
                inten = max(inten, 0.0) * float(self.light_strength) * 128.0 * 128.0
                p.vert[v].light = r3.F(qa(min(inten, 255.0), GEO["light"]))
        else:
            for v in range(3):
                p.vert[v].light = r3.F(0.0)

        world = lambda m: [float(x) for x in p.vert[m].world]
        ray = _vm(mv, world(0))
        nrm = _vm(mv, [float(x) for x in p.face])
        if pk[1] & 0x0010:
            p.visible = (ray[0] * nrm[0] + ray[1] * nrm[1] + ray[2] * nrm[2]) < 0.0
            if not p.visible:
                self.r.stats.add("culled_back")
        if ray[2] > 0.0:
            if p.visible:
                self.r.stats.add("culled_behind")
            p.visible = False
        if not p.visible:
            return

        proj = [float(v) for v in self.projection]
        cv = []
        for m in range(p.n):
            eye = [qa(v, GEO["eye"]) for v in _vm(mv, world(m))]
            c = [qa(v, GEO["clip"]) for v in _vm(proj, eye)]
            cv.append(c + [float(p.vert[m].tex[0]), float(p.vert[m].tex[1]),
                           float(p.vert[m].light), 0.0, 0.0])
        cv = _clip_all(cv)
        p.n = len(cv)
        for m, c in enumerate(cv):
            v = p.vert[m]
            v.tex = [r3.F(c[4]), r3.F(c[5])]
            v.light = r3.F(c[6])
            rw = qm(1.0 / c[3], GEO["rcp"])
            wx = (c[0] * rw + 1.0) * 256.0
            wy = (c[1] * rw + 1.0) * 256.0
            wz = (c[2] * rw + 1.0) * 0.5
            v.clip = [r3.F(wx), r3.F(512.0 - wy), r3.F(wz), r3.F(c[3])]


def _mm(a, b):
    """matmul4's layout, exact."""
    p = [0.0] * 16
    for i in range(4):
        for j in range(4):
            p[4 * j + i] = sum(a[4 * k + i] * b[4 * j + k] for k in range(4))
    return p


def _vm(a, b):
    return [sum(b[k] * a[4 * k + i] for k in range(4)) for i in range(4)]


def _clip_all(v):
    """poly.h's clipper, in float64, with the interpolation factor rounded to GEO['t']."""
    def lerp(a, b, t):
        t = qa(t, GEO["t"])
        return [a[k] + (b[k] - a[k]) * t for k in range(len(a))]

    def clip(v, test, tval):
        if not v:
            return []
        out, prev = [], len(v) - 1
        for i in range(len(v)):
            s1, s2 = test(v[i]), test(v[prev])
            if s1 != s2:
                t = tval(v[prev], v[i])
                if t is None:
                    return []
                out.append(lerp(v[prev], v[i], t))
            if s1:
                out.append(list(v[i]))
            prev = i
        return out

    W = 0.000001
    def tw(a, b):
        d = a[3] - b[3]
        return None if d == 0.0 else abs((W - a[3]) / d)
    v = clip(v, lambda x: x[3] >= W, tw)
    for axis in (0, 1, 2):
        for sign in (0, 1):
            ax = (lambda x, axis=axis, sign=sign: x[axis] if sign else -x[axis])
            def ta(a, b, ax=ax):
                d = (a[3] - ax(a)) - (b[3] - ax(b))
                return None if d == 0.0 else abs((a[3] - ax(a)) / d)
            v = clip(v, lambda x, ax=ax: ax(x) <= x[3], ta)
    return v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game")
    ap.add_argument("frames", type=int, nargs="+")
    ap.add_argument("--xy-bits", type=int, default=XY_F, help="vertex fraction bits")
    ap.add_argument("--geometry", default=None,
                    help="fixed-point geometry: 'mv=24,eye=20,...' (GEO's keys; 'float' leaves one); "
                         "empty for all float64")
    a = ap.parse_args()
    globals()["XY_F"] = a.xy_bits
    from PIL import Image
    import render_model as rm
    import rom_regions
    r3.Renderer = FxRenderer
    if a.geometry is not None:
        r3.Machine = FxMachine
        for kv in a.geometry.split(","):
            if kv:
                k, v = kv.split("=")
                GEO[k] = None if v == "float" else int(v)
    for f in a.frames:
        d = REPO / "debug" / f"{a.game}-f{f}"
        wl = d / "wlog.trace"
        res = r3.run(a.game, [f], trace=wl, capture=True) if wl.exists() else r3.run(a.game, [f])
        color, st, stats = res[f]
        cap = rm.Capture(d)
        gfx = rm.Gfx(rm.reorder_scrtile(rom_regions.region(a.game, "scrtile")))
        spr = rm.Gfx(rom_regions.region(a.game, "sprtile"))
        min_y, vis_h = r3.visible_area(cap)
        st["vis"] = (min_y, vis_h)
        img = r3.render_in_parts(rm, cap, gfx, spr, color, st)[min_y:min_y + vis_h]
        Image.fromarray(img).save(d / "model_fx.png")
        ref = np.asarray(Image.open(d / "reference.png").convert("RGB"))
        bad = (ref != img).any(axis=-1)
        flt = np.fromfile(d / "model3d.bin", dtype="<u2") if (d / "model3d.bin").exists() else None
        extra = ""
        if flt is not None:
            c, fl = color.astype(np.int64), flt.astype(np.int64)
            dif = c != fl
            cov = ((c & 0x7FF) != 0) != ((fl & 0x7FF) != 0)
            both = dif & ~cov
            idx = both & ((c & 0x7FF) != (fl & 0x7FF))
            lig = both & ~idx & ((c >> 12) != (fl >> 12))
            extra = (f"; 3D buffer against the float model: {int(dif.sum())} of "
                     f"{int(((fl & 0x7FF) != 0).sum())} drawn pixels - coverage {int(cov.sum())}, "
                     f"texel {int(idx.sum())}, light only {int(lig.sum())}")
        print(f"frame {f}: fixed point {int(bad.sum())} of {bad.size} pixels differ from MAME{extra}")


if __name__ == "__main__":
    main()
