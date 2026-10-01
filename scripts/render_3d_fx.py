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
Z_DROP = 4          # low z bits the depth buffer does not keep: 4 leaves 24 (a 32-bit word with an 8-bit tag)
GRAD_RCP = 20       # the setup's reciprocal of the determinant, mantissa bits; None divides exactly
PIX_RCP = None      # per-pixel reciprocal of 1/w, mantissa bits; None divides exactly
PIX_TABLE = 10      # the per-pixel reciprocal by table and one Newton step, table index bits
DUMP = None         # an open file: each triangle's setup input and its spans, for sim/raster_tb
FRAGS = None        # a list, in dump mode: per span, (texel byte addresses or None, pixels, draw, written)
DUMP_K = (0, 1, 2, 5, 6)                          # the rasteriser's channels: z, 1/w, light/w, u/w, v/w
DUMP_MAX = {}                                     # largest magnitude of each dumped quantity
COVERAGE = "edge"   # "mame": poly.h's scanline extents; "edge": SpinalVoodoo's edge functions


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


def rcp_newton(w, tbits):
    """The pixel unit's reciprocal of 1/w (an integer, SCALE[1]): w's top 21 bits wn (truncated,
    a mantissa 1.20), y0 from a table indexed by the tbits bits after the leading 1 (the reciprocal
    of the interval's midpoint to tbits + 2 fraction bits, rounded), one Newton step
    y1 = y0 (2 - wn y0), truncated to 21 fraction bits. Returns (y1, e): 1/w = y1 / 2^(21 + e)
    with e w's top bit index. w < 1 is taken as 1."""
    w = np.maximum(np.asarray(w, dtype=np.int64), 1)
    e = np.floor(np.log2(w.astype(np.float64))).astype(np.int64)
    e = np.where((np.int64(1) << e) > w, e - 1, e)        # exact, whatever float log2 rounds to
    e = np.where((np.int64(1) << (e + 1)) <= w, e + 1, e)
    wn = np.where(e >= 20, w >> np.maximum(e - 20, 0), w << np.maximum(20 - e, 0))
    p = tbits + 2
    i = (wn >> (20 - tbits)) & ((1 << tbits) - 1)
    table = np.array([((1 << (p + tbits + 2)) // ((1 << (tbits + 1)) + 2 * k + 1) + 1) >> 1
                      for k in range(1 << tbits)], dtype=np.int64)
    y0 = table[i]
    corr = (np.int64(1) << (21 + p)) - wn * y0
    y1 = (y0 * corr) >> (2 * p - 1)
    return y1, e


def _lg(v):
    return v.bit_length() - 1


def q(v, scale):
    """Round to nearest, as a setup unit converting MAME's float would."""
    return int(np.floor(float(v) * scale + 0.5))


def round_coord(v):
    """poly.h round_coordinate on an exact value in pixels."""
    ip = v.numerator // v.denominator
    return ip + (1 if v - ip > Fraction(1, 2) else 0)


def _dmax(name, *vals):
    DUMP_MAX[name] = max(DUMP_MAX.get(name, 0), *(abs(v) for v in vals))


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
        self._vs_in = list(vs)                           # as given, for the dump
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
        grad = self._grad_exact if GRAD_RCP is None or det == 0 else self._grad_rcp(det)
        for k in params:
            if det == 0:
                dpdx[k] = dpdy[k] = 0
            else:
                # the plane's numerators from differences to vertex 1: a00 + a10 + a20 = 0
                nx = (p2[k] - p1[k]) * a10 + (p3[k] - p1[k]) * a20
                ny = (p2[k] - p1[k]) * a11 + (p3[k] - p1[k]) * a21
                dpdx[k] = grad(nx, det)
                dpdy[k] = grad(ny, det)

        if COVERAGE == "edge":
            self._edge_spans(vs, params, dpdx, dpdy, scan)
            return
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
    def _grad_exact(n, det):
        return round(Fraction((1 << XY_F) * n, det))

    @staticmethod
    def _grad_rcp(det):
        """The setup unit's gradient: one reciprocal of |det| a triangle, its top GRAD_RCP + 1 bits
        (truncated) divided into 2^(2 GRAD_RCP + 1), a restoring divide of GRAD_RCP + 2 steps; then
        each numerator times it, rounded half up, sign restored."""
        m = GRAD_RCP
        d = abs(det)
        e = d.bit_length() - 1
        dn = d >> (e - m) if e >= m else d << (m - e)
        r = (1 << (2 * m + 1)) // dn                    # 1/d = r / 2^(m + 1 + e)
        sh = m + 1 + e - XY_F
        neg = det < 0

        def grad(n, _det):
            v = n * r
            v = (v + (1 << (sh - 1))) >> sh if sh > 0 else v << -sh
            return -v if neg else v
        return grad

    def _edge_spans(self, vs, params, dpdx, dpdy, scan):
        """SpinalVoodoo's coverage (TriangleSetup.scala, SpanWalker.scala): a pixel is drawn when
        its centre gives all three edge functions >= 0, the edges oriented by the triangle's winding
        and the constant of every edge but the top and left ones less one unit, so a centre exactly
        on a shared edge belongs to one triangle. Rows from roundHalfDown of the top vertex's y to
        that of the bottom's; each row's span solved exactly per edge."""
        one = 1 << XY_F
        (xa, ya, pa), (xb, yb, _), (xc, yc, _) = vs
        cross = (xb - xa) * (yc - ya) - (xc - xa) * (yb - ya)
        if cross == 0:
            return
        sign = -1 if cross < 0 else 1
        edges = []
        for (x0, y0), (x1, y1) in (((xa, ya), (xb, yb)), ((xb, yb), (xc, yc)), ((xc, yc), (xa, ya))):
            a, b, c = sign * (y0 - y1), sign * (x1 - x0), sign * (x0 * y1 - x1 * y0)
            if not (a > 0 or (a == 0 and b > 0)):
                c -= 1
            edges.append((a, b, c))

        def rhd(v):                                     # roundHalfDown, to pixels
            ip, fr = v >> XY_F, v & (one - 1)
            return ip + (1 if fr > one // 2 else 0)
        y0p, y1p = max(rhd(ya), 0), min(rhd(yc), 512 + 1)
        if DUMP:
            DUMP.write(("A %s" + chr(10)) % " ".join("%d" % v for v in self._attr))
            DUMP.write(("V %s" + chr(10)) % " ".join("%d %d %s" % (x, y, " ".join("%d" % p.get(k, 0) for k in DUMP_K))
                                         for x, y, p in self._vs_in))
            for x, y, p in self._vs_in:
                for k in DUMP_K:
                    _dmax(f"vertexp{k}", p.get(k, 0))
            _dmax("det", cross)
            chans = [(pa.get(k, 0), dpdx.get(k, 0), dpdy.get(k, 0)) for k in DUMP_K]
            DUMP.write("T %d %d %d %d %d %d %d %s\n" % (
                xa, ya, xb, yb, xc, yc, int(sign < 0), " ".join("%d %d %d" % t for t in chans)))
            _dmax("vertex", xa, ya, xb, yb, xc, yc)
            for k, (p0, dx, dy) in zip(DUMP_K, chans):
                _dmax(f"grad{k}", dx, dy)
        ax_pix, ay_pix = rhd(xa), rhd(ya)
        base = {k: pa[k] + ((((ax_pix * one + one // 2) - xa) * dpdx[k]
                             + ((ay_pix * one + one // 2) - ya) * dpdy[k]) >> XY_F) for k in params}
        for py in range(y0p, y1p):
            cy = py * one + one // 2
            lo, hi = 0, 513                              # centres px*one + one/2, px in [lo, hi)
            for a, b, c in edges:
                r = b * cy + c                           # a * (px*one + one/2) + r >= 0
                if a == 0:
                    if r < 0:
                        lo, hi = 1, 0
                    continue
                # a*one*px >= -r - a*one/2
                num = -r - a * (one // 2)
                den = a * one
                if a > 0:
                    lo = max(lo, -((-num) // den))       # ceil(num / den)
                else:
                    hi = min(hi, num // den + 1)         # px <= floor(num / den)
            if lo >= hi:
                continue
            start = {k: base[k] + (lo - ax_pix) * dpdx[k] + (py - ay_pix) * dpdy[k] for k in params}
            if DUMP and py < 512 and lo < 513:
                h = min(hi, 513)                         # x = 512 lands in column 0 (MAME_KLUDGES)
                DUMP.write("S %d %d %d %s\n" % (py, lo, h - 1, " ".join(
                    "%d" % start.get(k, 0) for k in DUMP_K)))
                for k in params:
                    _dmax(f"value{k}", start[k], start[k] + (h - 1 - lo) * dpdx[k])
            scan(py, lo, hi, start, dpdx)

    @staticmethod
    def _walk_i(start, d, n):
        return start + np.arange(n, dtype=np.int64) * d

    def draw_shaded(self, p):
        """drawShaded with geom_int.py's integer vertices, when the geometry left them: already in
        the rasteriser's formats, handed over as floats that q() turns back into the same integers."""
        iv = getattr(p, "iv", None)
        if iv is None:
            return super().draw_shaded(p)
        st = self.stats
        st.add("polys_drawn")
        one = float(1 << XY_F)
        sc = {k: float(v) for k, v in SCALE.items()}
        for j in range(1, len(iv) - 1):
            vs = [iv[0], iv[j], iv[j + 1]]
            if p.flat:
                tri = [[v["x"] / one, v["y"] / one, [v["z"] / sc[0], 0.0, 0.0, 0.0]] for v in vs]
                self.triangle(*tri, 4, self.flat_scan(p))
            else:
                tri = [[v["x"] / one, v["y"] / one,
                        [v["z"] / sc[0], v["rw"] / sc[1], v["l"] / sc[2], 0.0, 0.0,
                         v["u"] / sc[5], v["v"] / sc[6]]] for v in vs]
                self.triangle(*tri, 7, self.texture_scan(p))

    def _set_attr(self, rd):
        """The pixel unit's per-triangle fields, as dumped for sim/raster_tb (Pixel.scala Attr):
        flat, blend, 4bpp, texture index, sub-page, h and v page offsets, palette (the colour for
        a flat triangle), scroll x and y (texels), wrap exponents x and y (at most 31)."""
        wx = min(int(rd.tex_mask_x).bit_length() - 1, 31) if rd.tex_mask_x else 0
        wy = min(int(rd.tex_mask_y).bit_length() - 1, 31) if rd.tex_mask_y else 0
        pal = (rd.pal_offset + rd.color_index) & 0xFFFF if rd.flat else rd.pal_offset & 0xFFFF
        self._attr = (int(bool(rd.flat)), int(bool(rd.blend)), int(rd.tex4bpp), rd.tex_index & 15,
                      (rd.tex_page_small >> 14) & 3, (rd.tex_page_small >> 7) & 0x7F,
                      rd.tex_page_small & 0x7F, pal, (rd.texscrollx & 0x3FFF) >> 5,
                      (rd.texscrolly & 0x3FFF) >> 5, wx, wy)
        _dmax("wrap", int(rd.tex_mask_x).bit_length(), int(rd.tex_mask_y).bit_length())

    def _plot(self, y, x0, x1, z, color, draw):
        if Z_DROP:
            # the depth plane's z: 28 - Z_DROP fraction bits, 0 to 1 - 2^-(28 - Z_DROP)
            z = np.clip(np.asarray(z) >> Z_DROP, 0, (1 << (28 - Z_DROP)) - 1)
        if FRAGS is not None:
            # for the memory study (cache_3d.py): written is the depth test against the buffer
            # before the span, exact but for the rare pixel at x = 512 folded onto column 0
            idx = y * 512 + (np.arange(x0, x1) & 511)
            written = np.asarray(draw, dtype=bool) & (np.asarray(z) < self.depth[idx])
            FRAGS.append((self._span_addr, idx, np.asarray(draw, dtype=bool), written))
        super()._plot(y, x0, x1, z, color, draw)

    def flat_scan(self, rd):
        self._set_attr(rd)
        self._span_addr = None
        def scan(y, x0, x1, start, dpdx):
            if y > 511 or y < 0 or x0 >= x1:
                return
            z = self._walk_i(start[0], dpdx[0], x1 - x0)
            color = (rd.pal_offset + rd.color_index) & 0xFFFF
            self._plot(y, x0, x1, z, np.full(x1 - x0, color, dtype=np.uint16),
                       np.ones(x1 - x0, dtype=bool))
        return scan

    def texture_scan(self, rd):
        self._set_attr(rd)
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
            if PIX_TABLE is not None:
                # x * 2^k / w = x y1 / 2^(21 + e - k), truncated toward zero as C's (int)
                y1, e = rcp_newton(w, PIX_TABLE)

                def mulr(x, k):
                    m = (np.abs(x) * y1) >> (21 + e - k)
                    return np.where(x < 0, -m, m)
                ts = mulr(s, _lg(SCALE[1]) + 10 - _lg(SCALE[5])) + sy
                tt = mulr(t, _lg(SCALE[1]) + 10 - _lg(SCALE[6])) + sx
            elif PIX_RCP is None:
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
            self._span_addr = base + np.where(rd.tex4bpp, si * 512 + (ti >> 1), si * 1024 + ti)
            if rd.tex4bpp:
                b = self.tex[base + si * 512 + (ti >> 1)]
                pen = np.where(ti & 1, (b >> 4) & 0x0F, b & 0x0F)
            else:
                pen = self.tex[base + si * 1024 + ti]
            # light = (L / Ls) / (W / Ws); MAME keeps light / 16
            if PIX_TABLE is not None:
                lightval = mulr(light, _lg(SCALE[1]) - 4 - _lg(SCALE[2])) & 0xFF
            else:
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
    ap.add_argument("--dump", action="store_true",
                    help="write each frame's triangles and spans to debug/<game>-f<n>/raster.txt")
    ap.add_argument("--grad-rcp", default=str(GRAD_RCP),
                    help="the setup's reciprocal of the determinant, mantissa bits, or 'exact'")
    ap.add_argument("--pix-table", type=int, default=PIX_TABLE,
                    help="per-pixel reciprocal by table and Newton step: table index bits")
    ap.add_argument("--z-drop", type=int, default=Z_DROP, help="low z bits the depth buffer drops")
    ap.add_argument("--coverage", choices=("mame", "edge"), default=COVERAGE,
                    help="mame: poly.h's scanline extents; edge: SpinalVoodoo's edge functions")
    ap.add_argument("--geometry", default="int",
                    help="'int': geom_int.py, the RTL's specification (the default); 'float': MAME's "
                         "float geometry; 'mv=24,eye=20,...': float64 rounded at GEO's stages")
    a = ap.parse_args()
    globals()["XY_F"] = a.xy_bits
    globals()["COVERAGE"] = a.coverage
    globals()["Z_DROP"] = a.z_drop
    globals()["PIX_TABLE"] = a.pix_table
    globals()["GRAD_RCP"] = None if a.grad_rcp == "exact" else int(a.grad_rcp)
    from PIL import Image
    import render_model as rm
    import rom_regions
    r3.Renderer = FxRenderer
    if a.geometry == "int":
        import geom_int
        r3.Machine = geom_int.IntMachine
    elif a.geometry != "float":
        r3.Machine = FxMachine
        for kv in a.geometry.split(","):
            if kv:
                k, v = kv.split("=")
                GEO[k] = None if v == "float" else int(v)
    for f in a.frames:
        d = REPO / "debug" / f"{a.game}-f{f}"
        wl = d / "wlog.trace"
        if a.dump:
            globals()["DUMP"] = open(d / "raster.txt", "w")
            globals()["FRAGS"] = []
        res = r3.run(a.game, [f], trace=wl, capture=True) if wl.exists() else r3.run(a.game, [f])
        color, st, stats = res[f]
        if DUMP:
            color.astype("<u2").tofile(d / "raster_color.bin")
            n = [len(f[1]) for f in FRAGS]
            np.savez_compressed(d / "fragments.npz",
                                addr=np.concatenate([f[0] if f[0] is not None else np.full(k, -1)
                                                     for f, k in zip(FRAGS, n)]).astype(np.int64),
                                pixel=np.concatenate([f[1] for f in FRAGS]).astype(np.int32),
                                draw=np.concatenate([f[2] for f in FRAGS]),
                                written=np.concatenate([f[3] for f in FRAGS]))
            globals()["FRAGS"] = None
            DUMP.close()
            globals()["DUMP"] = None
            print("dump: " + ", ".join(f"{k} {v.bit_length() + 1} bits" for k, v in sorted(DUMP_MAX.items())))
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
