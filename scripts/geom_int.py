#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The 3D geometry in integers: the specification the geometry RTL is built to.

render_3d_fx.py --geometry int uses it. recoverPolygonBlock and drawShaded (hng64_3d.ipp) as
render_3d.py transcribes them, every value an integer at a stated binary point, every rounding
half up (`rnd`, `rdiv`), and the output the rasteriser's own formats (render_3d_fx.py SCALE):

    inputs          Q1.15, as the display list and the vertex ROM hold them (uToF's s16 / 32768)
    world           Q23: Q15 times the packet's scale / 256, exact
    model-view      Q30: camera x object, exact
    eye             Q26 (rounded)              clip          Q24 (rounded)
    projection      Q20: from the packet's Q15 values, near and screen z Q30 exact, far Q30
                    rounded, then each entry one divide, rounded
    clipper         t Q12 by an exact divide, rounded; lerps rounded at each component's point
    1/w             the pixel unit's reciprocal (a 10-bit table and a Newton step, 21 bits)
    divides         rounded half away from zero (a magnitude divider); products at most 36 x 36
                    bits, so 1/sqrt's Newton step and the light take an intermediate floor/round
    lighting        normals Q16; 1/length as 1 - (n - 1) / 2 within 1/128 of 1 (every normal the
                    captures have), else a table and one Newton step; light Q8 clamped at 255
    u, v            Q23 through the clipper

MAME's clip plane w >= 1e-6 is w >= 17 at Q24 (1.01e-6). A projection entry whose denominator is
zero is 0 (MAME's float gives an infinity).
"""
import numpy as np

import render_3d as r3

EYE_F, CLIP_F, PROJ_F, T_F, RCP_M = 26, 24, 20, 12, 20
EXACT_W = 0                                        # measurement: exact per-vertex divides
TEX_X = 8                                          # u, v at Q23 through the clipper (Q15: 3x the differences)
PROJ_MAME = 0                                      # measurement: MAME's float32 projection
W_MIN = 17                                         # 1e-6 at Q24, rounded up
RSQ_T = 8                                          # the 1/sqrt table's index bits


def rnd(x, s):
    """x / 2^s rounded half up; s <= 0 shifts left."""
    return (x + (1 << (s - 1))) >> s if s > 0 else x << -s


def rdiv(n, d):
    """n / d rounded half away from zero, exactly: what a magnitude divider gives."""
    q = (2 * abs(n) + abs(d)) // (2 * abs(d))
    return -q if (n < 0) != (d < 0) else q


def q15(f):
    """A float that is some s16 / 32768 back to the s16 (exact)."""
    return int(round(float(f) * 32768.0))


RCP_T = 10                                         # the reciprocal table's index bits
_RCP_TABLE = [((1 << (2 * RCP_T + 4)) // ((1 << (RCP_T + 1)) + 2 * k + 1) + 1) >> 1
              for k in range(1 << RCP_T)]


def rcp(w, m=RCP_M):
    """1/w for w > 0 as the pixel unit takes it (render_3d_fx.py rcp_newton, Pixel.scala): w's top
    21 bits wn, a table on the 10 bits after the leading one, one Newton step to 21 fraction bits.
    Returns (r, e) with 1/w = r / 2^(21 + e). m is kept for the measurement switches."""
    e = w.bit_length() - 1
    wn = w >> (e - 20) if e >= 20 else w << (20 - e)
    y0 = _RCP_TABLE[(wn >> (20 - RCP_T)) & ((1 << RCP_T) - 1)]
    p = RCP_T + 2
    y1 = (y0 * ((1 << (21 + p)) - wn * y0)) >> (2 * p - 1)
    return y1, e


RSQ_P = 16
_RSQ_TABLE = {i: int(np.floor((1 << RSQ_P) / np.sqrt((i + 0.5) * 2.0 ** (2 - RSQ_T)) + 0.5))
              for i in range(1 << (RSQ_T - 2), 1 << RSQ_T)}


def rsq(n):
    """1/sqrt(n) for an integer n > 0: n shifted by an even amount into [2^30, 2^32), a table on
    its top RSQ_T bits (each the value at its interval's midpoint, 16 fraction bits), one Newton
    step y1 = y0 (3 - m y0^2) / 2. Returns (y, s) with 1/sqrt(n) = y / 2^s."""
    k = n.bit_length() - 1 - 30
    if k % 2:
        k -= 1
    nn = n >> k if k >= 0 else n << -k
    y0 = _RSQ_TABLE[nn >> (32 - RSQ_T)]
    t = (((nn * y0) >> 13) * y0) >> 17             # m y0^2 at 2^32; each product fits 36 bits
    y1 = (y0 * ((3 << 32) - t)) >> 33
    return y1, 31 + k // 2


NORM_MODE = "linear"      # the normals' 1/length: "linear" (near 1, else rsq), "newton" (rsq), "none" (1)


def rsq_normal(n):
    """1/sqrt of a transformed normal's squared length n (Q32). Every in-scope capture has
    n within 2e-4 of 1.0 (unit normals, rotations): "linear" takes 1 - (n - 1) / 2 there, 24
    fraction bits, and rsq outside 1/128 of 1.0; "none" takes 1."""
    if NORM_MODE == "none":
        return 1 << 16, 32
    if NORM_MODE == "linear":
        d = n - (1 << 32)
        if abs(d) < (1 << 25):
            return (1 << 24) - rnd(d, 9), 40
    return rsq(n)


class IntMachine(r3.Machine):
    """render_3d.py's Machine with the geometry in integers (module docstring)."""

    def clear3d(self):
        super().clear3d()
        self.proj_i = [1 << PROJ_F if i in (0, 5, 10, 15) else 0 for i in range(16)]

    # ---- the projection, once a packet --------------------------------------------------------------
    def set_projection(self, pk):
        super().set_projection(pk)                  # MAME's floats, for anything else that reads them

        def s16(x):
            x &= 0xFFFF
            return x - 0x10000 if x & 0x8000 else x
        left, right, top, bottom = s16(pk[11]), s16(pk[10]), s16(pk[12]), s16(pk[13])   # Q15
        sz = s16(pk[6]) * s16(pk[4]) + (s16(pk[6]) << 15)                                # Q30, exact
        near = s16(pk[5]) * s16(pk[4]) + (s16(pk[5]) << 15)

        def div(n, d):
            return None if d == 0 else rdiv(n, d)
        far = div(-(sz * near), sz - 2 * near)                                           # Q30
        m = [0] * 16
        rl, tb = right - left, top - bottom
        m[0] = div((2 * sz) << (PROJ_F - 15), rl) or 0
        m[5] = div((2 * sz) << (PROJ_F - 15), tb) or 0
        m[8] = div((right + left) << PROJ_F, rl) or 0
        m[9] = div((top + bottom) << PROJ_F, tb) or 0
        if far is not None:
            m[10] = div(-(far + near) << PROJ_F, far - near) or 0
            m[14] = div(-(2 * far * near) << PROJ_F, (far - near) << 30) or 0
        m[11] = -(1 << PROJ_F)
        self.proj_i = m
        if PROJ_MAME:                               # for measurement: MAME's float32 entries, rounded
            self.proj_i = [int(np.floor(float(v) * (1 << PROJ_F) + 0.5)) if np.isfinite(float(v)) else 0
                           for v in self.projection]

    # ---- vertices kept exact ------------------------------------------------------------------------
    def std_verts(self, p, m, ch, c, pk):
        v = p.vert[m]
        w = [ch(c), ch(c + 1), ch(c + 2)]
        w = [x - 0x10000 if x & 0x8000 else x for x in w]
        c = super().std_verts(p, m, ch, c, pk)
        if pk[1] & 0x0040:
            v.world = [w[0] * self.scalez, w[1] * self.scaley, w[2] * self.scalex, 1 << 23]
        else:
            v.world = [w[0] << 8, w[1] << 8, w[2] << 8, 1 << 23]
        v.tex = [q15(v.tex[0]), q15(v.tex[1])]
        return c

    # ---- the transform ----------------------------------------------------------------------------
    def transform(self, p, pk, obj):
        p.iv = None
        obj_i = [q15(x) for x in obj]
        if self.samsho_hack:
            mv = [x << 15 for x in obj_i]
        else:
            cam = [q15(x) for x in self.camera]
            mv = [0] * 16                          # matmul4's layout
            for i in range(4):
                for j in range(4):
                    mv[4 * j + i] = sum(cam[4 * k + i] * obj_i[4 * j + k] for k in range(4))

        def vm(a, b):
            return [sum(b[k] * a[4 * k + i] for k in range(4)) for i in range(4)]

        # lighting
        lights = [0, 0, 0]
        st = q15(self.light_strength)
        if pk[1] & 0x0008 and st > 0:
            self.r.stats.add("lit")
            lv = [q15(x) for x in self.light_vec]
            n2 = sum(x * x for x in lv)
            if n2:
                y, s = rsq(n2)
                lvn = [rnd(x * y, s - 16) for x in lv]           # Q16
                for vi in range(3):
                    nrm = [q15(x) for x in p.vert[vi].normal]
                    tn = [rnd(sum(nrm[k] * obj_i[4 * k + i] for k in range(3)), 14) for i in range(3)]
                    n2v = sum(x * x for x in tn)
                    dot = -sum(a * b for a, b in zip(tn, lvn))  # Q32
                    if n2v and dot > 0:
                        yv, sv = rsq_normal(n2v)
                        cos = rnd(dot * yv, sv - 8)             # Q24
                        lights[vi] = min(rnd(cos * st, 17), 255 << 8)
        # culls
        eye0 = [rnd(x, 53 - EYE_F) for x in vm(mv, p.vert[0].world)]
        face = [q15(x) for x in p.face[:3]] + [0]
        nrm = [rnd(x, 45 - EYE_F) for x in vm(mv, face)]
        if pk[1] & 0x0010:
            p.visible = sum(eye0[k] * nrm[k] for k in range(3)) < 0
            if not p.visible:
                self.r.stats.add("culled_back")
        if eye0[2] > 0:
            if p.visible:
                self.r.stats.add("culled_behind")
            p.visible = False
        if not p.visible:
            return

        cv = []
        for m in range(p.n):
            v = p.vert[m]
            eye = [rnd(x, 53 - EYE_F) for x in vm(mv, v.world)]
            clip = [rnd(x, PROJ_F + EYE_F - CLIP_F) for x in vm(self.proj_i, eye)]
            cv.append(clip + [v.tex[0] << TEX_X, v.tex[1] << TEX_X, lights[m] if m < 3 else 0])
        cv = _clip_all(cv)
        p.n = len(cv)
        out = []
        for c in cv:
            x, y, z, w, u, vv, l = c
            if EXACT_W:                             # for measurement: each output an exact divide
                out.append(dict(
                    x=rdiv((x + w) << 20, w), y=(512 << 12) - rdiv((y + w) << 20, w),
                    z=rdiv((z + w) << 27, w), rw=rdiv(1 << 50, w),
                    u=rdiv(u << 33, w << TEX_X), v=rdiv(vv << 33, w << TEX_X), l=rdiv(l << 24, w)))
                continue
            r, e = rcp(w, RCP_M)
            sh = RCP_M + 1 + e                      # 1/w = r / 2^sh
            one = 1 << sh
            out.append(dict(
                x=rnd(x * r + one, sh - 20),
                y=(512 << 12) - rnd(y * r + one, sh - 20),
                z=rnd(z * r + one, sh - 27),
                rw=rnd(r, sh - 50),
                u=rnd(u * r, sh - 33 + TEX_X),
                v=rnd(vv * r, sh - 33 + TEX_X),
                l=rnd(l * r, sh - 24)))
        p.iv = out


def _clip_all(v):
    """poly.h's clipper (render_3d.py frustum_clip_all) in integers: t = |num / den| to T_F bits by
    an exact divide, each component a + (b - a) t rounded at its own point."""
    def lerp(a, b, t):
        return [a[k] + rnd((b[k] - a[k]) * t, T_F) for k in range(len(a))]

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

    def tw(a, b):
        d = a[3] - b[3]
        return None if d == 0 else rdiv(abs(W_MIN - a[3]) << T_F, abs(d))
    v = clip(v, lambda x: x[3] >= W_MIN, tw)
    for axis in (0, 1, 2):
        for sign in (0, 1):
            ax = (lambda x, axis=axis, sign=sign: x[axis] if sign else -x[axis])

            def ta(a, b, ax=ax):
                d = (a[3] - ax(a)) - (b[3] - ax(b))
                return None if d == 0 else rdiv(abs(a[3] - ax(a)) << T_F, abs(d))
            v = clip(v, lambda x, ax=ax: ax(x) <= x[3], ta)
    return v
