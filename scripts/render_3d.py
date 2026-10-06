#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The 3D pipeline as MAME runs it: a transcription of hng64_3d.ipp and of poly.h's triangle
rasteriser, in float32 as MAME computes it, driven by the display-list writes of a bus trace.

    python scripts/render_3d.py sams64 600          # MAME frame 600's 3D buffer, and the frame

MAME renders each display-list upload the moment it is written (dl_upload_w), into one 512x512
buffer of u16 (llll appp pppp pppp: light, blend, palette index) and a float depth buffer, and
clears both at vblank when tcram 0x50 bit 16 is set (screen_vblank). screen_update reads the
buffer before that clear; in the trace, the frame marker N + 1 follows frame N's update and its
vblank (LESSONS_LEARNED, frame markers), so the buffer shown for frame N is the one standing at
marker N + 1, taken before the clear.

float32 throughout, operation by operation in C's order, so that the model can be bit-exact
against MAME before it is turned into fixed point (docs/ROADMAP.md, 3D open items). Where MAME
reads state it never set (the reused polygon array), so does this.

Writes debug/<set>-f<N>/model3d.bin (the u16 buffer, 512x512 little-endian), model3d.png (its
palette indices, grey) and, when the capture has the 2D state, model_full.png, the whole frame
with the 3D mixed in as screen_update does it, compared with MAME's reference.png.
"""
import argparse
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import rom_regions  # noqa: E402

REPO = Path(__file__).resolve().parent.parent
F = np.float32
MAX_POLYS = 10000       # HNG64_MAX_POLYGONS: only its reuse matters here, not its size


def u2f(u):
    """uToF (hng64_3d.ipp:1288): s16 / 32768."""
    u &= 0xFFFF
    return F(u - 0x10000 if u & 0x8000 else u) / F(32768.0)


def identity():
    m = [F(0.0)] * 16
    m[0] = m[5] = m[10] = m[15] = F(1.0)
    return m


def matmul4(a, b):
    """matmul4 (hng64_3d.ipp:1243); the product may alias a, which C allows column by column."""
    p = [F(0.0)] * 16
    for i in range(4):
        ai0, ai1, ai2, ai3 = a[0 + i], a[4 + i], a[8 + i], a[12 + i]
        p[0 + i] = ai0 * b[0] + ai1 * b[1] + ai2 * b[2] + ai3 * b[3]
        p[4 + i] = ai0 * b[4] + ai1 * b[5] + ai2 * b[6] + ai3 * b[7]
        p[8 + i] = ai0 * b[8] + ai1 * b[9] + ai2 * b[10] + ai3 * b[11]
        p[12 + i] = ai0 * b[12] + ai1 * b[13] + ai2 * b[14] + ai3 * b[15]
    return p


def vecmatmul4(a, b):
    """vecmatmul4 (hng64_3d.ipp:1260): matrix a times vector b."""
    b0, b1, b2, b3 = b[0], b[1], b[2], b[3]
    return [b0 * a[0] + b1 * a[4] + b2 * a[8] + b3 * a[12],
            b0 * a[1] + b1 * a[5] + b2 * a[9] + b3 * a[13],
            b0 * a[2] + b1 * a[6] + b2 * a[10] + b3 * a[14],
            b0 * a[3] + b1 * a[7] + b2 * a[11] + b3 * a[15]]


def dot3(a, b):
    return (a[0] * b[0]) + (a[1] * b[1]) + (a[2] * b[2])


def normalize(x):
    """normalize (hng64_3d.ipp:1302): the sum in float, the root and divide in double."""
    l2 = float(x[0] * x[0] + x[1] * x[1] + x[2] * x[2])
    ln = math.sqrt(l2)
    for i in range(3):
        x[i] = F(float(x[i]) / ln) if ln != 0.0 else F(math.copysign(math.inf, float(x[i]))
                                                       if float(x[i]) != 0.0 else math.nan)


class Vert:
    __slots__ = ("world", "tex", "normal", "clip", "light")

    def __init__(self):
        self.world = [F(0.0)] * 4
        self.tex = [F(0.0)] * 2
        self.normal = [F(0.0)] * 4
        self.clip = [F(0.0)] * 4
        self.light = F(0.0)

    def copy_from(self, o):
        self.world = list(o.world)
        self.tex = list(o.tex)
        self.normal = list(o.normal)
        self.clip = list(o.clip)
        self.light = o.light


class Poly:
    def __init__(self):
        self.n = 0
        self.vert = [Vert() for _ in range(10)]
        self.face = [F(0.0)] * 4
        self.visible = False
        self.flat = False
        self.blend = False
        self.tex_index = 0
        self.tex4bpp = 0
        self.tex_page_small = 0
        self.pal_offset = 0
        self.color_index = 0
        self.texscrollx = 0
        self.texscrolly = 0
        self.tex_mask_x = 0
        self.tex_mask_y = 0

    def copy_from(self, o):
        self.n = o.n
        for a, b in zip(self.vert, o.vert):
            a.copy_from(b)
        self.face = list(o.face)
        for k in ("visible", "flat", "blend", "tex_index", "tex4bpp", "tex_page_small",
                  "pal_offset", "color_index", "texscrollx", "texscrolly", "tex_mask_x",
                  "tex_mask_y"):
            setattr(self, k, getattr(o, k))


def round_coordinate(v):
    """poly.h round_coordinate: floor, then up only when the fraction is above one half."""
    ip = math.floor(float(v))
    fp = F(v) - F(ip)
    return int(ip) + (1 if fp > F(0.5) else 0)


# ---- frustum clipping (poly.h:1344-1476); vertices are [x, y, z, w, p0..p4] ------------------------

W_PLANE = F(0.000001)


def _lerp(a, b, t):
    return [a[k] + ((b[k] - a[k]) * t) for k in range(len(a))]


def clip_w(v):
    if not v:
        return []
    out = []
    prev = len(v) - 1
    for i in range(len(v)):
        s1 = -1 if v[i][3] < W_PLANE else 1
        s2 = -1 if v[prev][3] < W_PLANE else 1
        if s1 * s2 < 0:
            wdiv = v[prev][3] - v[i][3]
            if wdiv == F(0.0):
                return []
            t = F(abs((W_PLANE - v[prev][3]) / wdiv))
            out.append(_lerp(v[prev], v[i], t))
        if s1 > 0:
            out.append(list(v[i]))
        prev = i
    return out


def clip_axis(v, axis, sign):
    if not v:
        return []
    out = []
    prev = len(v) - 1
    for i in range(len(v)):
        a1 = v[i][axis] if sign else -v[i][axis]
        a2 = v[prev][axis] if sign else -v[prev][axis]
        s1 = 1 if a1 <= v[i][3] else -1
        s2 = 1 if a2 <= v[prev][3] else -1
        if s1 * s2 < 0:
            wdiv = ((v[prev][3] - a2) - (v[i][3] - a1))
            if wdiv == F(0.0):
                return []
            t = F(abs((v[prev][3] - a2) / wdiv))
            out.append(_lerp(v[prev], v[i], t))
        if s1 > 0:
            out.append(list(v[i]))
        prev = i
    return out


def frustum_clip_all(v):
    v = clip_w(v)
    for axis, sign in ((0, 0), (0, 1), (1, 0), (1, 1), (2, 0), (2, 1)):
        v = clip_axis(v, axis, sign)
    return v


class Stats(dict):
    """What one frame asked of the 3D: for sizing the hardware and for coverage."""

    def add(self, k, n=1):
        self[k] = self.get(k, 0) + n


class Renderer:
    """hng64_poly_renderer: the two buffers and the scanline functions."""

    def __init__(self, textures):
        self.tex = textures
        self.stats = Stats()
        self.color = np.zeros(512 * 512, dtype=np.uint16)
        self.depth = np.zeros(512 * 512, dtype=np.float32)

    def clear(self):
        """clear3d's part: depth 100.0, colour 0."""
        self.depth[:] = F(100.0)
        self.color[:] = 0

    # poly.h render_triangle, for the parameters in use; p is a list per vertex
    def triangle(self, v1, v2, v3, nparams, scan):
        if v2[1] < v1[1]:
            v1, v2 = v2, v1
        if v3[1] < v2[1]:
            v2, v3 = v3, v2
            if v2[1] < v1[1]:
                v1, v2 = v2, v1
        v1y = round_coordinate(v1[1])
        v3y = round_coordinate(v3[1])
        v1yclip = max(v1y, 0)
        v3yclip = min(v3y, 512 + 1)
        if v3yclip - v1yclip <= 0:
            self.stats.add("triangles_empty")
            return
        self.stats.add("triangles")
        x1, y1, x2, y2, x3, y3 = v1[0], v1[1], v2[0], v2[1], v3[0], v3[1]
        z = F(0.0)
        d12 = z if y2 == y1 else (x2 - x1) / (y2 - y1)
        d13 = z if y3 == y1 else (x3 - x1) / (y3 - y1)
        d23 = z if y3 == y2 else (x3 - x2) / (y3 - y2)

        p1, p2, p3 = v1[2], v2[2], v3[2]
        a00 = y2 - y3
        a01 = x3 - x2
        a02 = x2 * y3 - x3 * y2
        a10 = y3 - y1
        a11 = x1 - x3
        a12 = x3 * y1 - x1 * y3
        a20 = y1 - y2
        a21 = x2 - x1
        a22 = x1 * y2 - x2 * y1
        det = a02 + a12 + a22
        if abs(det) < F(0.00001):
            dpdx = [z] * nparams
            dpdy = [z] * nparams
            pst = [p1[k] for k in range(nparams)]
        else:
            idet = F(1.0) / det
            dpdx = [idet * (p1[k] * a00 + p2[k] * a10 + p3[k] * a20) for k in range(nparams)]
            dpdy = [idet * (p1[k] * a01 + p2[k] * a11 + p3[k] * a21) for k in range(nparams)]
            pst = [idet * (p1[k] * a02 + p2[k] * a12 + p3[k] * a22) for k in range(nparams)]

        for cur in range(v1yclip, v3yclip):
            fully = F(cur) + F(0.5)
            startx = x1 + (fully - y1) * d13
            if fully < y2:
                stopx = x1 + (fully - y1) * d12
            else:
                stopx = x2 + (fully - y2) * d23
            ix0 = round_coordinate(startx)
            ix1 = round_coordinate(stopx)
            if ix0 > ix1:
                ix0, ix1 = ix1, ix0
            ix0 = max(ix0, 0)
            ix1 = min(ix1, 512 + 1)
            if ix0 >= ix1:
                ix0 = ix1 = 0
            fsx = F(ix0) + F(0.5)
            start = [pst[k] + fsx * dpdx[k] + fully * dpdy[k] for k in range(nparams)]
            scan(cur, ix0, ix1, start, dpdx)

    @staticmethod
    def _walk(start, d, n):
        """The span's parameter at each pixel: start, then += d, accumulated in float32 in order."""
        a = np.empty(n, dtype=np.float32)
        a[0] = start
        a[1:] = d
        return np.cumsum(a, dtype=np.float32)

    def flat_scan(self, rd):
        def scan(y, x0, x1, start, dpdx):
            if y > 511 or y < 0 or x0 >= x1:
                return
            z = self._walk(start[0], dpdx[0], x1 - x0)
            color = (rd.pal_offset + rd.color_index) & 0xFFFF
            self._plot(y, x0, x1, z, np.full(x1 - x0, color, dtype=np.uint16),
                       np.ones(x1 - x0, dtype=bool))
        return scan

    def _plot(self, y, x0, x1, z, color, draw):
        """Depth-test and write, pixel by pixel in x order: x & 511 folds 512 onto 0."""
        xs = np.arange(x0, x1) & 511
        row = y * 512
        self.stats.add("pixels_tested", int(draw.sum()))
        self.stats.add("spans")
        if x1 <= 512:
            idx = row + xs
            ok = draw & (z < self.depth[idx])
            self.color[idx[ok]] = color[ok]
            self.depth[idx[ok]] = z[ok]
            self.stats.add("pixels_written", int(ok.sum()))
        else:
            for i in range(x1 - x0):
                j = row + xs[i]
                if draw[i] and z[i] < self.depth[j]:
                    self.color[j] = color[i]
                    self.depth[j] = z[i]

    def texture_scan(self, rd):
        base = rd.tex_index * 1024 * 1024
        sub = (rd.tex_page_small & 0xC000) >> 14
        hoff = (rd.tex_page_small & 0x3F80) >> 7
        voff = rd.tex_page_small & 0x007F
        sy = F((rd.texscrolly & 0x3FFF) >> 5)
        sx = F((rd.texscrollx & 0x3FFF) >> 5)

        def scan(y, x0, x1, start, dpdx):
            if y > 511 or y < 0 or x0 >= x1:
                return
            n = x1 - x0
            z = self._walk(start[0], dpdx[0], n)
            w = self._walk(start[1], dpdx[1], n)
            light = self._walk(start[2], dpdx[2], n)
            s = self._walk(start[5], dpdx[5], n)
            t = self._walk(start[6], dpdx[6], n)
            with np.errstate(all="ignore"):
                sc = s / w
                tc = t / w
                rc = light / w
                ts = sc * F(1024.0) + sy
                tt = tc * F(1024.0) + sx
                if sub & 2:
                    tt = np.fmod(tt, F(rd.tex_mask_x)) + F(8.0) * F(hoff)
                    ts = np.fmod(ts, F(rd.tex_mask_y)) + F(8.0) * F(voff)
                ti = _to_int(tt) & 1023
                si = _to_int(ts) & 1023
            if rd.tex4bpp:
                b = self.tex[base + si * 512 + (ti >> 1)]
                pen = np.where(ti & 1, (b >> 4) & 0x0F, b & 0x0F)
            else:
                pen = self.tex[base + si * 1024 + ti]
            with np.errstate(all="ignore"):
                lightval = _to_int(rc / F(16.0)) & 0xFF
            color = (((rd.pal_offset + pen.astype(np.int64)) & 0x7FF) | (lightval << 12)) & 0xFFFF
            if rd.blend:
                color |= 0x800
            self._plot(y, x0, x1, z, color.astype(np.uint16), pen != 0)
        return scan

    def draw_shaded(self, p):
        """drawShaded (hng64_3d.ipp:1445): a fan of triangles from vertex 0."""
        st = self.stats
        st.add("polys_drawn")
        st.add("flat" if p.flat else ("tex4bpp" if p.tex4bpp else "tex8bpp"))
        if p.blend:
            st.add("blended")
        if (p.tex_page_small >> 15) & 1:
            st.add("small_page")
        st.add(f"verts_after_clip_{p.n}")
        if p.flat:
            for j in range(1, p.n - 1):
                vs = [p.vert[0], p.vert[j], p.vert[j + 1]]
                tri = [[v.clip[0], v.clip[1], [v.clip[2], F(0), F(0), F(0)]] for v in vs]
                self.triangle(*tri, 4, self.flat_scan(p))
        else:
            for j in range(p.n):
                v = p.vert[j]
                v.clip[3] = F(1.0) / v.clip[3]
                v.light = v.light * v.clip[3]
                v.tex[0] = v.tex[0] * v.clip[3]
                v.tex[1] = v.tex[1] * v.clip[3]
            for j in range(1, p.n - 1):
                vs = [p.vert[0], p.vert[j], p.vert[j + 1]]
                tri = [[v.clip[0], v.clip[1],
                        [v.clip[2], v.clip[3], v.light, F(0), F(0), v.tex[0], v.tex[1]]] for v in vs]
                self.triangle(*tri, 7, self.texture_scan(p))


def _to_int(a):
    """C's float-to-int conversion (truncation); NaN and out-of-range give INT_MIN, as cvttss2si."""
    a = np.asarray(a, dtype=np.float32)
    bad = ~np.isfinite(a) | (a >= F(2147483648.0)) | (a < F(-2147483648.0))
    out = np.where(bad, 0, np.trunc(np.where(bad, 0, a))).astype(np.int64)
    out[bad] = -2147483648
    return out


class Machine:
    """The 3D state of hng64_state and the display-list commands (hng64_3d.ipp:55-1071)."""

    def __init__(self, game, textures, verts):
        self.samsho_hack = game in ("sams64", "sams64_2")      # init_ss64
        self.verts = verts
        self.r = Renderer(textures)
        self.dl = [0] * 0x100
        self.wrap = [0x08] * 0x20                               # machine_start
        self.fbcontrol = [0, 0, 0, 0]
        self.fbscroll = 0
        self.fbscale = 0
        self.tcram50 = 0
        self.polys = [Poly() for _ in range(64)]
        self.frame_stats = []
        self.draw = True            # False: state packets only, before a clear that wipes the result
        self.vregs = [0xDEADBEEF] * 14                          # machine_start, [0] = 0
        self.vregs[0] = 0
        self.split_log = None       # during the captured frame: (vpos, vregs before, 3D buffer)
        self.light_vec = [F(0.0)] * 3
        self.light_strength = F(0.0)
        self.texscrollx = self.texscrolly = 0
        self.palstate = 0
        self.scalex = self.scaley = self.scalez = 0
        self.clear3d()

    def clear3d(self):
        self.r.clear()
        self.palstate = 0
        self.projection = identity()
        self.modelview = identity()
        self.camera = identity()

    # ---- bus writes, from the trace (32-bit big-endian data, mask per byte) ------------------------
    def write(self, addr, mask, data, vpos=None):
        if 0x20190000 <= addr < 0x20190038:                     # vregs_w
            i = (addr - 0x20190000) >> 2
            new = (self.vregs[i] & ~mask) | (data & mask)
            # MAME draws the lines above the beam with the old value first
            # (update_partial(vpos - 1)); in vblank the frame is already drawn
            if new != self.vregs[i] and self.split_log is not None and vpos and 0 < vpos < 448:
                self.split_log.append((vpos, list(self.vregs), self.r.color.copy()))
            self.vregs[i] = new
            return
        if 0x20300000 <= addr < 0x20300200:                     # dl_w, u16
            o = (addr - 0x20300000) >> 1
            if mask & 0xFFFF0000:
                self.dl[o] = _combine16(self.dl[o], data >> 16, mask >> 16)
            if mask & 0x0000FFFF:
                self.dl[o + 1] = _combine16(self.dl[o + 1], data & 0xFFFF, mask & 0xFFFF)
        elif addr == 0x20300200:                                # dl_upload_w
            self.r.stats.add("uploads")
            for start in range(0, 0x100, 16):
                if not self.command3d(self.dl[start:start + 16]):
                    break
        elif addr == 0x30000000 or (0x30000010 <= addr < 0x30000030):   # u8 registers
            for k in range(4):
                if mask & (0xFF000000 >> (8 * k)):
                    b = (data >> (24 - 8 * k)) & 0xFF
                    if addr == 0x30000000:
                        self.fbcontrol[k] = b
                    else:
                        self.wrap[addr - 0x30000010 + k] = b
        elif addr == 0x30000004:
            self.fbscale = (self.fbscale & ~mask) | (data & mask)
        elif addr == 0x30000008:
            self.fbscroll = (self.fbscroll & ~mask) | (data & mask)
        elif addr == 0x20208050:
            self.tcram50 = (self.tcram50 & ~mask) | (data & mask)

    def vblank(self):
        self.frame_stats.append(self.r.stats)
        self.r.stats = Stats()
        if (self.tcram50 >> 16) & 1:
            self.clear3d()

    # ---- the commands ------------------------------------------------------------------------------
    def command3d(self, pk):
        polys = []
        op = pk[0]
        if op == 0x0000:
            return False
        if op == 0x0001:
            c = self.camera
            c[0], c[4], c[8], c[3] = u2f(pk[1]), u2f(pk[2]), u2f(pk[3]), F(0.0)
            c[1], c[5], c[9], c[7] = u2f(pk[4]), u2f(pk[5]), u2f(pk[6]), F(0.0)
            c[2], c[6], c[10], c[11] = u2f(pk[7]), u2f(pk[8]), u2f(pk[9]), F(0.0)
            c[12], c[13], c[14], c[15] = u2f(pk[10]), u2f(pk[11]), u2f(pk[12]), F(1.0)
        elif op == 0x0010:
            self.light_vec = [u2f(pk[3]), u2f(pk[4]), u2f(pk[5])]
            self.light_strength = u2f(pk[9])
        elif op == 0x0011:
            self.texscrollx, self.texscrolly, self.palstate = pk[1], pk[2], pk[8]
            self.scalex, self.scaley, self.scalez = pk[5], pk[6], pk[7]
        elif op == 0x0012:
            self.set_projection(pk)
        elif op in (0x0100, 0x0101, 0x0102) and not self.draw:
            pass
        elif op in (0x0100, 0x0101):
            polys = self.polygon_block(pk)
        elif op == 0x0102:
            mini = list(pk[0:7]) + [0x7FFF, 0, 0, 0, 0x7FFF, 0, 0, 0, 0x7FFF]
            polys = self.polygon_block(mini)
            if pk[7] == 1 and pk[8] == 0x0102:
                mini = list(pk[8:15]) + [0x7FFF, 0, 0, 0, 0x7FFF, 0, 0, 0, 0x7FFF]
                polys += self.polygon_block(mini, start=len(polys))
        for p in polys:
            if p.visible:
                self.r.draw_shaded(p)
        return True

    def set_projection(self, pk):
        left, right = u2f(pk[11]), u2f(pk[10])
        top, bottom = u2f(pk[12]), u2f(pk[13])
        screen_z = u2f(pk[6]) * u2f(pk[4]) + u2f(pk[6])
        near = u2f(pk[5]) * u2f(pk[4]) + u2f(pk[5])
        with np.errstate(all="ignore"):
            far = -(screen_z * near) / (screen_z - F(2.0) * near)
            m = [F(0.0)] * 16
            m[0] = (F(2.0) * screen_z) / (right - left)
            m[5] = (F(2.0) * screen_z) / (top - bottom)
            m[8] = (right + left) / (right - left)
            m[9] = (top + bottom) / (top - bottom)
            m[10] = -((far + near) / (far - near))
            m[11] = F(-1.0)
            m[14] = -((F(2.0) * far * near) / (far - near))
        self.projection = m

    def std_verts(self, p, m, ch, c, pk):
        """recoverStandardVerts (hng64_3d.ipp:355). Returns the new word counter."""
        v = p.vert[m]
        v.world = [u2f(ch(c)), u2f(ch(c + 1)), u2f(ch(c + 2)), F(1.0)]
        c += 3
        p.n = 3
        c += 1                                                  # maybe_blend
        v.tex[0] = u2f(ch(c))
        if p.flat:
            p.color_index = ch(c) >> 5
        c += 1
        v.tex[1] = u2f(ch(c))
        c += 1
        if pk[1] & 0x0040:
            v.world[0] = (v.world[0] * F(self.scalez)) / F(256.0)
            v.world[1] = (v.world[1] * F(self.scaley)) / F(256.0)
            v.world[2] = (v.world[2] * F(self.scalex)) / F(256.0)
        return c

    def polygon_block(self, pk, start=0):
        """recoverPolygonBlock (hng64_3d.ipp:394). Polygons go into the reused array from `start`."""
        obj = identity()
        obj[8], obj[4], obj[0], obj[3] = u2f(pk[7]), u2f(pk[8]), u2f(pk[9]), F(0.0)
        obj[9], obj[5], obj[1], obj[7] = u2f(pk[10]), u2f(pk[11]), u2f(pk[12]), F(0.0)
        obj[10], obj[6], obj[2], obj[11] = u2f(pk[13]), u2f(pk[14]), u2f(pk[15]), F(0.0)
        obj[12], obj[13], obj[14], obj[15] = u2f(pk[4]), u2f(pk[5]), u2f(pk[6]), F(1.0)

        vr = self.verts
        off = (pk[2] << 16) | pk[3]
        if off * 3 >= len(vr):
            return []
        ptr = off * 3
        megaoff = vr[ptr + 2]
        address = [vr[ptr + 0], vr[ptr + 1], vr[ptr + 3], vr[ptr + 4]]
        size = [vr[ptr + 6], vr[ptr + 7], vr[ptr + 9], vr[ptr + 10]]
        address = [a | (megaoff << 16) for a in address]

        last = Poly()
        n = start
        out = []
        for k in range(4):
            chunk = address[k] * 3
            for _ in range(size[k]):
                def ch(i, base=chunk):
                    j = base + i
                    return int(vr[j]) if j < len(vr) else 0
                ctype = ch(0) & 0xFF
                if ch(0) & 0xFF00:
                    continue                                    # MAME skips without advancing
                while n >= len(self.polys):
                    self.polys.append(Poly())
                p = self.polys[n]
                w1, w2 = ch(1), ch(2)
                p.tex4bpp = 1 if w1 & 0x1000 else 0
                p.tex_page_small = w2
                p.tex_index = w1 & 0x000F
                p.tex_mask_x = 1 << self.wrap[p.tex_index * 2 + 0]
                p.tex_mask_y = 1 << self.wrap[p.tex_index * 2 + 1]
                p.flat = not (w1 & 0x8000)
                p.blend = False
                pal = ((w1 & 0x0FF0) >> 4) << 3
                if pk[1] & 0x0100:
                    pal |= ((self.palstate >> 8) & 0x3F) * 0x80
                p.pal_offset = pal & 0xFFFF
                if w1 & 0x4000:
                    p.blend = True
                if pk[1] & 0x0080:
                    p.texscrollx, p.texscrolly = self.texscrollx, self.texscrolly
                else:
                    p.texscrollx = p.texscrolly = 0

                c = 3
                if ctype in (0x05, 0x0F):
                    for m in range(3):
                        c = self.std_verts(p, m, ch, c, pk)
                        p.vert[m].normal = [u2f(ch(c)), u2f(ch(c + 1)), u2f(ch(c + 2)), F(0.0)]
                        c += 3
                    p.face = [u2f(ch(c)), u2f(ch(c + 1)), u2f(ch(c + 2)), F(0.0)]
                    c += 3
                elif ctype in (0x04, 0x0E, 0x24, 0x2E):
                    for m in range(3):
                        c = self.std_verts(p, m, ch, c, pk)
                    nrm = [u2f(ch(c)), u2f(ch(c + 1)), u2f(ch(c + 2)), F(0.0)]
                    c += 3
                    for m in range(3):
                        p.vert[m].normal = list(nrm)
                    p.face = list(nrm)
                elif ctype in (0x87, 0x97, 0xD7, 0xC7):
                    p.vert[1].copy_from(last.vert[0])
                    p.vert[2].copy_from(last.vert[2])
                    c = self.std_verts(p, 0, ch, c, pk)
                    p.vert[0].normal = [u2f(ch(c)), u2f(ch(c + 1)), u2f(ch(c + 2)), F(0.0)]
                    c += 3
                    p.face = [u2f(ch(c)), u2f(ch(c + 1)), u2f(ch(c + 2)), F(0.0)]
                    c += 3
                elif ctype in (0x86, 0x96, 0xB6, 0xC6, 0xD6):
                    p.vert[1].copy_from(last.vert[0])
                    p.vert[2].copy_from(last.vert[2])
                    c = self.std_verts(p, 0, ch, c, pk)
                    p.vert[0].normal = list(last.face)
                    p.face = list(last.face)
                    c += 3
                p.visible = True
                self.r.stats.add("polys")
                self.r.stats.add(f"chunk_{ctype:02x}")
                last.copy_from(p)
                self.transform(p, pk, obj)
                chunk += c
                n += 1
                out.append(p)
        return out

    def transform(self, p, pk, obj):
        """The world transform, lighting, culls and projection of recoverPolygonBlock."""
        mv = identity()
        if not self.samsho_hack:
            mv = matmul4(mv, self.camera)
        mv = matmul4(mv, obj)
        self.modelview = mv

        if pk[1] & 0x0008 and self.light_strength > F(0.0):
            self.r.stats.add("lit")
            for v in range(3):
                tn = vecmatmul4(obj, p.vert[v].normal)
                normalize(tn)
                normalize(self.light_vec)
                inten = dot3(tn, self.light_vec) * F(-1.0)
                inten = F(0.0) if inten <= F(0.0) else inten
                inten = inten * (self.light_strength * F(128.0))
                inten = F(float(inten) * 128.0)
                if inten >= F(255.0):
                    inten = F(255.0)
                p.vert[v].light = inten
        else:
            for v in range(3):
                p.vert[v].light = F(0.0)

        ray = vecmatmul4(mv, p.vert[0].world)
        normalize(ray)
        nrm = vecmatmul4(mv, p.face)
        if pk[1] & 0x0010:
            p.visible = dot3(ray, nrm) < F(0.0)
            if not p.visible:
                self.r.stats.add("culled_back")
        ray = vecmatmul4(mv, p.vert[0].world)
        if ray[2] > F(0.0):
            if p.visible:
                self.r.stats.add("culled_behind")
            p.visible = False
        if not p.visible:
            return

        cv = []
        for m in range(p.n):
            eye = vecmatmul4(mv, p.vert[m].world)
            p.vert[m].clip = vecmatmul4(self.projection, eye)
            c = p.vert[m].clip
            cv.append([c[0], c[1], c[2], c[3], p.vert[m].tex[0], p.vert[m].tex[1],
                       p.vert[m].light, F(0.0), F(0.0)])
        with np.errstate(all="ignore"):
            cv = frustum_clip_all(cv)
            p.n = len(cv)
            for m, c in enumerate(cv):
                v = p.vert[m]
                v.tex = [c[4], c[5]]
                v.light = c[6]
                ndx, ndy, ndz = c[0] / c[3], c[1] / c[3], c[2] / c[3]
                wx = (ndx + F(1.0)) * F(256.0) + F(0.0)
                wy = (ndy + F(1.0)) * F(256.0) + F(0.0)
                wz = (ndz + F(1.0)) * F(0.5)
                v.clip = [wx, F(512.0) - wy, wz, c[3]]


def _combine16(old, new, mask):
    return (old & ~mask & 0xFFFF) | (new & mask)


def trace_events(path):
    """(frame marker, None) and (addr, mask, data) for each write, in order."""
    with open(path) as f:
        for line in f:
            if line.startswith("# frame"):
                yield ("frame", int(line.split()[2]))
                continue
            if line.startswith("# capture"):
                yield ("capture", None)
                continue
            if line[0] == "#":
                continue
            p = line.split()
            if p[1] != "w":
                continue
            yield ("w", (int(p[2], 16), int(p[3], 16), int(p[4], 16),
                         int(p[5]) if len(p) > 5 else None))


def run(game, frames, trace=None, capture=False):
    """The 3D buffers for each MAME frame in `frames`: {frame: (color u16[512*512], machine state)}.

    From the bus trace, frame N's buffer is the one at marker N + 1. From a capture's own write
    log (capture=True, one frame), it is the one at the log's `# capture` line."""
    textures = np.frombuffer(rom_regions.region(game, "textures0"), dtype=np.uint8)
    verts = np.frombuffer(rom_regions.region(game, "verts"), dtype="<u2").astype(np.int64)
    m = Machine(game, textures, verts)
    trace = trace or REPO / "debug" / f"{game}-sys" / f"{game}_sys.trace"
    want = {f + 1: f for f in frames}
    out = {}
    last = max(want)
    def state():
        return (m.r.color.copy(), dict(fbcontrol=list(m.fbcontrol), fbscroll=m.fbscroll,
                                       fbscale=m.fbscale, roadedge=game == "roadedge"))
    # A clearing vblank wipes the buffer and the projection, camera and palette state, so nothing
    # drawn before the last one ahead of the first wanted frame can show: skip the polygons there.
    # The reused polygon array is the one thing that loses its history (MAME_KLUDGES, 3D).
    tc, start, first = 0, -1, (None if capture else min(want))
    for i, (kind, ev) in enumerate(trace_events(trace)):
        if kind == "capture" or (kind == "frame" and first is not None and ev >= first):
            break
        if kind == "frame" and (tc >> 16) & 1:
            start = i
        elif kind == "w" and ev[0] == 0x20208050:
            tc = (tc & ~ev[1]) | (ev[2] & ev[1])
    m.draw = start < 0
    for i, (kind, ev) in enumerate(trace_events(trace)):
        if i == start:
            m.draw = True
        if kind == "capture":
            if capture:
                out[frames[0]] = state() + (dict(m.r.stats),)
                out[frames[0]][1]["splits"] = m.split_log
                out[frames[0]][1]["vregs"] = list(m.vregs)
                break
            continue
        if kind == "frame":
            if capture:
                m.vblank()
                m.split_log = []            # the frame being drawn starts here
                continue
            if ev in want:
                out[want[ev]] = state() + (dict(m.r.stats),)
            if ev >= last:
                break
            m.vblank()
        else:
            m.write(*ev)
    return out


def blit_line(dst, y, height, color, st, pal3d):
    """One line of the 3D blit of screen_update (hng64_v.cpp:868-923), onto dst as it stands:
    the 512 buffer lines are stretched over the visible ones, and fbscroll moves it in x."""
    if st["fbcontrol"][0] & 0x01:
        return
    # init_roadedge's m_roadedge_3d_hack leaves the base where it is (hng64_v.cpp:870)
    palbase = 0x800 if (st["fbcontrol"][2] >> 5) & 1 and not st.get("roadedge") else 0
    xs = st["fbscroll"] >> 21
    if xs & 0x400:
        xs -= 0x800
    xs += 256
    # the game's visible area (tcram 0x04/0x08, tcram_w): fatfurwa shows lines 16-447
    min_y, vis_h = st.get("vis", (0, height))
    if y < min_y or y >= min_y + vis_h:
        return
    yinc = (512 << 16) // (vis_h - 1)       # visarea.max_y - visarea.min_y
    realy = ((y - min_y) * yinc) >> 16
    src = color.reshape(512, 512)[realy & 0x1FF][(np.arange(dst.shape[0]) + xs) & 0x1FF].astype(np.int64)
    sel = (src & 0x07FF) != 0
    if not sel.any():
        return
    rgb = pal3d[(src[sel] & 0xF7FF) | palbase]
    bl = (src[sel] & 0x0800) != 0
    out = rgb.copy()
    d = dst[sel]
    out[bl] = ((rgb[bl].astype(np.int32) * 0x80 + d[bl].astype(np.int32) * 0x80) >> 8).astype(np.uint8)
    dst[sel] = out


def render_in_parts(rm, cap, gfx, spr, color, st):
    """The frame as MAME draws it: each change to a video register mid-screen draws the lines above
    the beam with the registers, and the 3D buffer, as they were (vregs_w's update_partial). Only
    the video registers are split this way; tile VRAM, palette and sprites are the capture's."""
    import copy
    pal = palette3d(cap)
    splits = st.get("splits") or []
    if not splits:
        return rm.render(cap, gfx, spr, layer3d=(color, st, pal))
    parts = [(v, regs, buf) for v, regs, buf in splits] + [(448, st["vregs"], color)]
    img, top = None, 0
    for v, regs, buf in parts:
        c = copy.copy(cap)
        c.videoregs = np.array(regs, dtype=np.uint32)
        part = rm.render(c, gfx, spr, layer3d=(buf, st, pal))
        if img is None:
            img = part.copy()
        img[top:v] = part[top:v]
        top = v
    return img


def visible_area(cap):
    """The rows MAME shows: tcram 0x04 low half is min_y, 0x08 low half the height (tcram_w)."""
    t1, t2 = int(cap.tcram[1]), int(cap.tcram[2])
    h = t2 & 0xFFFF
    return (t1 & 0xFFFF, h) if h else (0, 448)


def palette3d(cap):
    """m_palette_3d: 16 brightness copies of the palette, each + (intensity << 2), through fade 0."""
    import render_model as rm
    base, _, _ = rm.palettes(cap)
    t14 = int(cap.tcram[0x14 // 4])
    modes = [(t14 >> 10) & 3, (t14 >> 8) & 3, (t14 >> 6) & 3]
    pal = np.zeros((16 * 0x1000, 3), dtype=np.uint8)
    n = base.shape[0]
    for i in range(16):
        lit = np.minimum(base.astype(np.int16) + (i << 2), 255).astype(np.uint8)
        pal[i * 0x1000:i * 0x1000 + n] = rm._fade(lit, int(cap.tcram[0x18 // 4]), modes)
    return pal


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game")
    ap.add_argument("frames", type=int, nargs="+")
    a = ap.parse_args()
    from PIL import Image
    sys_frames = [f for f in a.frames
                  if not (REPO / "debug" / f"{a.game}-f{f}" / "wlog.trace").exists()]
    res = run(a.game, sys_frames) if sys_frames else {}
    for f in a.frames:
        d = REPO / "debug" / f"{a.game}-f{f}"
        if f not in res:
            res.update(run(a.game, [f], trace=d / "wlog.trace", capture=True))
        color, st, stats = res[f]
        d.mkdir(parents=True, exist_ok=True)
        color.astype("<u2").tofile(d / "model3d.bin")
        grey = ((color & 0x7FF) != 0).astype(np.uint8) * 255
        Image.fromarray(grey.reshape(512, 512)).save(d / "model3d.png")
        drawn = int(((color & 0x7FF) != 0).sum())
        msg = f"frame {f}: {drawn} 3D pixels drawn"
        if (d / "videoregs.bin").exists():
            import render_model as rm
            cap = rm.Capture(d)
            gfx = rm.Gfx(rm.reorder_scrtile(rom_regions.region(a.game, "scrtile")))
            spr = rm.Gfx(rom_regions.region(a.game, "sprtile"))
            min_y, vis_h = visible_area(cap)
            st["vis"] = (min_y, vis_h)
            img = render_in_parts(rm, cap, gfx, spr, color, st)[min_y:min_y + vis_h]
            Image.fromarray(img).save(d / "model_full.png")
            ref = np.asarray(Image.open(d / "reference.png").convert("RGB"))
            diff = int((ref != img).any(axis=-1).sum())
            msg += f"; whole frame {diff} of {img.shape[0] * img.shape[1]} pixels differ from MAME"
        print(msg)
        print("  " + ", ".join(f"{k} {v}" for k, v in sorted(stats.items())))


if __name__ == "__main__":
    main()
