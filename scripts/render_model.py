#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Software model of the HNG64 2D video, from a MAME capture.

    python scripts/mame_capture.py sams64 --frame 1200 --name attract
    python scripts/render_model.py sams64 attract          # writes model.png beside it
    python scripts/render_model.py sams64 attract --diff   # and diff.png + a pixel count

The model is MAME's video code transcribed (hng64_v.cpp), not an independent reading of the
hardware: it is the reference the RTL is checked against, and it is only as right as MAME.
Where MAME is a guess its comment says so, and those places go in docs/MAME_KLUDGES.md.

Covered so far: palette, the four tilemaps (8x8/16x16, 4/8 bpp, flip, wrap, mosaic, simple and
per-line scroll and zoom), priority order. Not yet: sprites, 3D, split-screen modes, blending,
the tcram palette fades.
"""
import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
from rom_regions import region  # noqa: E402

# MAME's gfx layouts for "scrtile" (hng64.cpp:1678-1727): planes, x offsets, y offsets, stride.
LAYOUTS = {
    # "sprtile" (hng64.cpp:1729-1750); gfx 4 is 4bpp, gfx 5 is 8bpp
    4: (16, 16, 4, [0, 1, 2, 3],
        [56, 60, 24, 28, 48, 52, 16, 20, 40, 44, 8, 12, 32, 36, 0, 4],
        [i * 64 for i in range(16)], 16 * 64),
    5: (16, 16, 8, list(range(8)),
        [56, 24, 48, 16, 40, 8, 32, 0,
         1024 + 56, 1024 + 24, 1024 + 48, 1024 + 16, 1024 + 40, 1024 + 8, 1024 + 32, 1024 + 0],
        [i * 64 for i in range(16)], 32 * 64),
    0: (8, 8, 4, [0, 1, 2, 3], [24, 28, 8, 12, 16, 20, 0, 4],
        [i * 32 for i in range(8)], 8 * 32),
    1: (8, 8, 8, list(range(8)), [24, 8, 16, 0, 256 + 24, 256 + 8, 256 + 16, 256 + 0],
        [i * 32 for i in range(8)], 16 * 32),
    2: (16, 16, 4, [0, 1, 2, 3],
        [24, 28, 8, 12, 16, 20, 0, 4, 256 + 24, 256 + 28, 256 + 8, 256 + 12,
         256 + 16, 256 + 20, 256 + 0, 256 + 4],
        [i * 32 for i in range(8)] + [i * 32 for i in range(16, 24)], 32 * 32),
    3: (16, 16, 8, list(range(8)),
        [24, 8, 16, 0, 256 + 24, 256 + 8, 256 + 16, 256 + 0,
         1024 + 24, 1024 + 8, 1024 + 16, 1024 + 0, 1280 + 24, 1280 + 8, 1280 + 16, 1280 + 0],
        [i * 32 for i in range(8)] + [i * 32 for i in range(16, 24)], 64 * 32),
}


def reorder_scrtile(rom):
    """hng64_reorder (hng64.cpp:1814), applied to "scrtile" by init_reorder_gfx.

    Two 4bpp tiles share each 8bpp tile, so the driver interleaves the region's halves in
    32-byte units before decoding. Without it every tile is nonsense.
    """
    a = np.frombuffer(rom, dtype=np.uint8)
    half = a.size // 2
    n = half // 32
    lo = a[:n * 32].reshape(n, 32)
    hi = a[half:half + n * 32].reshape(n, 32)
    out = np.empty((n, 2, 32), dtype=np.uint8)
    out[:, 0] = hi
    out[:, 1] = lo
    return out.tobytes()


class Gfx:
    """MAME gfx_layout decode, with a tile cache: a tile is ~1000 bit tests."""

    def __init__(self, rom):
        self.rom = np.frombuffer(rom, dtype=np.uint8)
        self.bits = np.unpackbits(self.rom)          # MSB first, as MAME numbers gfx bits
        self.cache = {}

    def tile(self, idx, code):
        key = (idx, code)
        hit = self.cache.get(key)
        if hit is not None:
            return hit
        w, h, planes, po, xo, yo, inc = LAYOUTS[idx]
        base = code * inc
        out = np.zeros((h, w), dtype=np.uint16)
        if base + inc > self.bits.size:
            self.cache[key] = out
            return out
        for p, pofs in enumerate(po):
            shift = planes - 1 - p
            for y in range(h):
                row = base + yo[y] + pofs
                out[y] |= self.bits[[row + x for x in xo]].astype(np.uint16) << shift
        self.cache[key] = out
        return out


class Capture:
    def __init__(self, path):
        self.path = Path(path)

        def u32(name):
            return np.frombuffer((self.path / name).read_bytes(), dtype=">u4")

        self.videoram = u32("videoram.bin")
        self.videoregs = u32("videoregs.bin")
        self.palette = u32("palette.bin")
        self.tcram = u32("tcram.bin")
        self.spriteram = u32("spriteram.bin")
        self.spriteregs = u32("spriteregs.bin")
        fb = self.path / "reg_fbctrl.bin"
        self._fbctrl = fb.read_bytes() if fb.exists() else b""

    def fbcontrol(self, i):
        """hng64_3d.ipp:1091, four bytes at 0x30000000; 0 bit 0 gates the background fill."""
        return self._fbctrl[i] if i < len(self._fbctrl) else 0


def _fade(rgb, fadeval, modes):
    """One fade palette (hng64_v.cpp:1209): per channel, add or subtract a constant."""
    out = rgb.astype(np.int16).copy()
    vals = [(fadeval >> 16) & 0xFF, (fadeval >> 8) & 0xFF, fadeval & 0xFF]
    for ch, (mode, v) in enumerate(zip(modes, vals)):
        if mode == 1:
            out[:, ch] = np.minimum(out[:, ch] + v, 255)
        elif mode == 3:
            out[:, ch] = np.maximum(out[:, ch] - v, 0)
    return out.astype(np.uint8)


def palettes(cap):
    """Base palette and the two fade palettes (hng64_v.cpp:1279-1375)."""
    p = cap.palette
    rgb = np.stack([(p >> 16) & 0xFF, (p >> 8) & 0xFF, p & 0xFF], axis=-1).astype(np.int16)
    # per-region modifiers: 8 regions of 256 entries, mode from tcram[0x24/4]
    for i in range(8):
        tcdata = int(cap.tcram[(0x28 // 4) + i])
        tcregion = (tcdata >> 24) & 0x0F
        mods = [tcdata & 0xFF, (tcdata >> 8) & 0xFF, (tcdata >> 16) & 0xFF]   # r, g, b
        mode = (int(cap.tcram[0x24 // 4]) >> (i << 1)) & 3
        if mode not in (2, 3):
            continue
        sel = (np.arange(rgb.shape[0]) >> 8) == tcregion
        for ch, m in enumerate(mods):
            if mode == 2:
                rgb[sel, ch] = np.minimum(rgb[sel, ch] + m, 255)
            else:
                rgb[sel, ch] = np.maximum(rgb[sel, ch] - m, 0)
    base = rgb.astype(np.uint8)
    t14 = int(cap.tcram[0x14 // 4])
    fade0 = _fade(base, int(cap.tcram[0x18 // 4]), [(t14 >> 10) & 3, (t14 >> 8) & 3, (t14 >> 6) & 3])
    fade1 = _fade(base, int(cap.tcram[0x1C // 4]), [(t14 >> 4) & 3, (t14 >> 2) & 3, t14 & 3])
    return base, fade0, fade1


def palette_rgb(cap):
    return palettes(cap)[0]


def tileregs(cap, tm):
    # int(): numpy integers overflow rather than widen, and scroll deltas go negative
    return int(cap.videoregs[0x02 + ((tm >> 1) & 1)] >> (0 if tm & 1 else 16)) & 0xFFFF


def scrollbase(cap, tm):
    return int(cap.videoregs[0x04 + ((tm >> 1) & 1)] >> (0 if tm & 1 else 16)) & 0x3FFF


def tile_at(cap, gfx, tm, tx, ty, big, alt):
    """Palette-index block for one tile of tilemap tm (hng64_v.cpp:49, get_tile_info)."""
    cols = 256 if alt else 128
    idx = (ty % (64 if alt else 128)) * cols + (tx % cols)
    word = int(cap.videoram[idx + (tm << 14)])
    pal = (word >> 24) & 0xFF
    flip = (word >> 22) & 3
    if (word >> 21) & 1 and (int(cap.videoregs[0x01]) >> 16) & 1:
        word = (word & int(cap.videoregs[0x0B])) | int(cap.videoregs[0x0C])
    code = word & 0x1FFFFF
    eight_bpp = (tileregs(cap, tm) >> 10) & 1
    if not big:
        gi, code, pal = (1, code >> 1, pal >> 4) if eight_bpp else (0, code, pal)
    else:
        gi, code, pal = (3, code >> 3, pal >> 4) if eight_bpp else (2, code >> 2, pal)
    px = gfx.tile(gi, code)
    if flip & 1:
        px = px[:, ::-1]
    if flip & 2:
        px = px[::-1, :]
    depth = 8 if gi in (1, 3) else 4
    colour = pal << depth
    return np.where(px == 0, 0, px + colour)


def tilemap_pixmap(cap, gfx, tm):
    """The whole tilemap as palette indices; 0 is transparent, as MAME's pixmap is."""
    regs = tileregs(cap, tm)
    big = (regs >> 9) & 1
    alt = big and (int(cap.videoregs[0x00] >> 24) & 3) != 0
    tw = 16 if big else 8
    cols, rows = (256, 64) if alt else (128, 128)
    out = np.zeros((rows * tw, cols * tw), dtype=np.uint16)
    for ty in range(rows):
        for tx in range(cols):
            out[ty * tw:(ty + 1) * tw, tx * tw:(tx + 1) * tw] = tile_at(cap, gfx, tm, tx, ty, big, alt)
    return out


def _s32(v):
    v &= 0xFFFFFFFF
    return v - (1 << 32) if v & 0x80000000 else v


def _div512(v):
    """C integer division truncates toward zero; Python's floors."""
    return -((-v) // 512) if v < 0 else v // 512


def scroll_params(cap, tm, src_line):
    """MAME's three scroll-register layouts (hng64_v.cpp:143-318).

    Returns xtopleft, ytopleft and the four increments MAME derives from them. Split-screen
    (videoregs 0x09/0x0a) is not modelled.
    """
    regs = int(tileregs(cap, tm))
    sb = int(scrollbase(cap, tm)) << 4
    vr = cap.videoram

    def w(off):
        return _s32(int(vr[(off + sb) // 4]))

    vr0 = int(cap.videoregs[0x00])
    alt_fmt = vr0 & 0x04000000
    zoom_off = vr0 & 0x00010000

    if regs & 0x0800:                                   # not line mode
        if alt_fmt:                                     # rotation: buriki's title logo
            xtl, xalt, xmid = w(0x40000), w(0x40004), w(0x40010)
            ytl, yalt, ymid = w(0x40008), w(0x40018), w(0x4000C)
            xinc, yinc = _div512(_s32(xmid - xtl)), _div512(_s32(ymid - ytl))
            xinc2, yinc2 = _div512(_s32(xalt - xtl)), _div512(_s32(yalt - ytl))
        else:
            if zoom_off:
                xtl, xmid, ytl, ymid = 0, 256 << 16, 0, 256 << 16
            else:
                xtl, xmid = w(0x40000), w(0x40004)
                ytl, ymid = w(0x40008), w(0x4000C)
            xinc, yinc = _div512(_s32(xmid - xtl)), _div512(_s32(ymid - ytl))
            xinc2 = yinc2 = 0
    else:                                               # line mode
        if zoom_off:
            xtl, xmid, ytl, ymid = 0, 256 << 16, 0, 256 << 16
        else:
            lo = (src_line & 0xFFFF) * 0x10
            xtl, xmid = w(0x40000), w(0x40004)
            xtl2 = int(vr[(0x40000 + lo + sb) // 4])
            xmid2 = int(vr[(0x40004 + lo + sb) // 4])
            if (xtl2 & 0xFF) == 0:
                xtl = _s32(xtl2)
            if (xmid2 & 0xFF) == 0:
                xmid = _s32(xmid2)
            ytl, ymid = w(0x40008 + lo), w(0x4000C + lo)
        xinc = _div512(_s32(xmid - xtl))
        if alt_fmt:                                     # y follows x across the line, not down it
            yinc, xinc2, yinc2 = 0, 0, _div512(_s32(ymid - ytl))
        else:
            yinc, xinc2, yinc2 = _div512(_s32(ymid - ytl)), 0, 0

    return xtl, ytl, xinc << 1, yinc2 << 1, xinc2 << 1, yinc << 1


def draw_tilemap_line(cap, pixmap, tm, y, row=None):
    """One line of one tilemap, as palette indices; 0 transparent. Mixing is render()'s job."""
    regs = tileregs(cap, tm)
    if row is None:
        row = np.zeros(512, dtype=np.uint16)
    if not ((regs >> 6) & 1):                 # enable
        return row
    mosaic = (regs >> 12) & 0xF
    wrap = (regs >> 8) & 1
    src_line = (y // (mosaic + 1)) * (mosaic + 1)
    xtl, ytl, incxx, incxy, incyx, incyy = scroll_params(cap, tm, src_line)
    h, w = pixmap.shape
    wsh, hsh = w << 16, h << 16
    M = 0xFFFFFFFF
    startx = (xtl + src_line * incyx) & M
    starty = (ytl + src_line * incyy) & M

    def plot(x, pix):
        if pix:
            row[x] = pix

    if incxy == 0 and incyx == 0 and not wrap:
        # MAME's optimised path: skip to the first in-range pixel, then stop at the first
        # out-of-range one. The mosaic run starts at that first drawn pixel, not at x 0.
        x, cx = 0, startx
        while cx >= wsh and x <= 511:
            cx = (cx + incxx) & M
            x += 1
        if x > 511 or starty >= hsh:
            return row
        src = pixmap[starty >> 16]
        mc, data = 0, 0
        while x <= 511 and cx < wsh:
            if mc == 0:
                data, mc = int(src[cx >> 16]), mosaic
            else:
                mc -= 1
            plot(x, data)
            cx = (cx + incxx) & M
            x += 1
        return row

    cx, cy = startx, starty
    mc, data = 0, 0
    for x in range(512):
        if wrap:
            if mc == 0:
                data, mc = int(pixmap[(cy >> 16) & (h - 1)][(cx >> 16) & (w - 1)]), mosaic
            else:
                mc -= 1
            plot(x, data)
        elif cx < wsh and cy < hsh:
            if mc == 0:
                data, mc = int(pixmap[cy >> 16][cx >> 16]), mosaic
            else:
                mc -= 1
            plot(x, data)
        cx = (cx + incxx) & M
        cy = (cy + incxy) & M
    return row


def draw_sprites(cap, spr, height=448, width=512):
    """MAME's sprite buffer (hng64_sprite.ipp:254): palette index | group<<12 | blend<<15."""
    out = np.zeros((height, width), dtype=np.uint16)
    regs = [int(v) for v in cap.spriteregs]
    ram = cap.spriteram
    offsx, offsy = regs[1] & 0xFFFF, (regs[1] >> 16) & 0xFFFF
    zsort = not ((regs[0] >> 24) & 1)
    zbuf = np.full((height, width), 0 if zsort else 0x7FF, dtype=np.int32)
    four_bpp = (regs[0] >> 23) & 1
    gi = 4 if four_bpp else 5
    gran = 16 if four_bpp else 256
    zoom_shift = 4 if (regs[0] >> 27) & 1 else 8

    def sext(v, bits):
        m = 1 << (bits - 1)
        return (v & (m - 1)) - (v & m)

    cur = 0
    while cur < (0xC000 // 4) // 8:
        w0, w1, w2, w3, w4 = (int(ram[cur * 8 + i]) for i in range(5))
        zval = (w2 & 0x07FF0000) >> 16
        ypos = sext(((w0 & 0xFFFF0000) >> 16) + offsy, 10)
        xpos = sext((w0 & 0xFFFF) + offsx, 10)
        blend = bool(w4 & 0x00800000)
        group = (w4 & 0x00700000) >> 8
        checker = bool(w4 & 0x04000000)
        mosaic = (w4 & 0xF0000000) >> 28
        yflip, xflip = (w4 >> 24) & 1, (w4 >> 25) & 1
        chainy, chainx = w2 & 0xF, (w2 & 0xF0) >> 4
        chaini = w2 & 0x00000100
        nxt = cur + 1 if not chaini else cur + (chainx + 1) * (chainy + 1)
        zoomy, zoomx = (w1 & 0xFFFF0000) >> 16, w1 & 0xFFFF
        if not zoomx or not zoomy or (zsort and zval == 0):
            cur = nxt
            continue
        dx0, dy = zoomx << zoom_shift, zoomy << zoom_shift

        full_y, dstheight = 0, 0
        while full_y < (chainy + 1) * 0x100000:
            full_y += dy
            dstheight += 1

        realline, mos_y = 0, 0
        for curyy in range(dstheight):
            if not mosaic:
                realline = curyy
            elif mos_y == 0:
                realline, mos_y = curyy, mosaic
            else:
                mos_y -= 1
            if 0 <= ypos < height:
                src_y = (realline * dy) >> 16
                ytile, tline = src_y // 0x10, src_y & 0xF
                x = xpos
                srcpix_x = 0
                mos_x, srcpix = 0, 0
                for xdrw in range(chainx + 1):
                    dstwidth = 0
                    while srcpix_x < 0x100000:
                        srcpix_x += dx0
                        dstwidth += 1
                    srcpix_x &= 0x0FFFFF
                    # get_tile_details (hng64_sprite.ipp:201)
                    if not xflip:
                        ofs = xdrw + (ytile * (chainx + 1)) if not yflip else xdrw + ((chainy - ytile) * (chainx + 1))
                    else:
                        ofs = (chainx - xdrw) + (ytile * (chainx + 1)) if not yflip                             else (chainx - xdrw) + ((chainy - ytile) * (chainx + 1))
                    if not chaini:
                        tileno = w4 & 0x0007FFFF
                        pal = (w3 & 0x00FF0000) >> 16
                        if not four_bpp:
                            tileno >>= 1
                            pal &= 0xF
                        tileno += ofs
                    else:
                        b4 = int(ram[(cur + ofs) * 8 + 4])
                        b3 = int(ram[(cur + ofs) * 8 + 3])
                        tileno = b4 & 0x0007FFFF
                        pal = (b3 & 0x00FF0000) >> 16
                        if not four_bpp:
                            tileno >>= 1
                            pal &= 0xF
                    colour = gran * (pal % (256 if four_bpp else 16))
                    if blend:
                        colour |= 0x8000
                    colour |= group
                    tile = spr.tile(gi, tileno)
                    row = tile[(15 - tline) & 0xF] if yflip else tile[tline & 0xF]
                    dx, srcx = dx0, 0
                    if xflip:
                        srcx = (dstwidth - 1) * dx
                        dx = -dx
                    cursrcx = srcx
                    for curx in range(dstwidth):
                        xd = x + curx
                        if 0 <= xd < width:
                            if not mosaic:
                                srcpix = int(row[(cursrcx >> 16) & 0xF])
                            elif mos_x == 0:
                                srcpix, mos_x = int(row[(cursrcx >> 16) & 0xF]), mosaic
                            else:
                                mos_x -= 1
                            pix = srcpix
                            if checker and (((xd & 1) and not (ypos & 1)) or (not (xd & 1) and (ypos & 1))):
                                pix = 0
                            hit = zval >= zbuf[ypos, xd] if zsort else zval < zbuf[ypos, xd]
                            if hit and pix != 0:
                                zbuf[ypos, xd] = zval
                                out[ypos, xd] = colour + pix
                        cursrcx += dx
                    x += dstwidth
            ypos += 1
        cur = nxt
    return out


def blend_mode(cap, tm):
    """1 plain, 2 additive (hng64_v.cpp:595). MAME calls this a guess from xrally and sams64."""
    tc = int(cap.tcram[0x0C // 4])
    bit = 2 if (tileregs(cap, tm) >> 5) & 1 else 26
    return 2 if (tc >> bit) & 1 else 1


def _add(dst, src):
    return np.minimum(dst.astype(np.int16) + src.astype(np.int16), 255).astype(np.uint8)


def _alpha(dst, src):
    """MAME's alpha_blend_r32 at level 0x80: (s * 128 + d * 128) >> 8."""
    return (((src.astype(np.int16) << 7) + (dst.astype(np.int16) << 7)) >> 8).astype(np.uint8)


def render(cap, gfx, spr=None, height=448, width=512):
    """screen_update (hng64_v.cpp:743-940), without the 3D blit between the two priority halves.

    Sprites are mixed by group inside the priority walk, not over the finished tilemaps: a
    blended sprite or an additive layer sees whatever is under it at that point.
    """
    base, fade0, fade1 = palettes(cap)
    cluts = (base, fade0, fade1)
    img = np.zeros((height, width, 3), dtype=np.uint8)
    if cap.fbcontrol(0) & 0x01:
        img[:, :] = base[0]
    if (int(cap.tcram[0x24 // 4]) >> 17) & 1:      # "disable all palette output", set in fades
        return img
    if int(cap.tcram[2]) & 0xFFFF0000 == 0 or int(cap.tcram[2]) & 0xFFFF == 0:
        return img                                 # screen disabled (hng64_v.cpp:1398)

    pixmaps = {tm: tilemap_pixmap(cap, gfx, tm) for tm in range(4)
               if (tileregs(cap, tm) >> 6) & 1}
    if int(cap.videoregs[0x00]) & 1:
        raise SystemExit("split-screen scroll (videoregs[0] bit 0) is not modelled")
    sprites = draw_sprites(cap, spr, height, width) if spr is not None else None
    order = [(int(tileregs(cap, tm)) & 0x1F, tm) for tm in sorted(pixmaps)]
    sel_clut = {tm: (2 if (tileregs(cap, tm) >> 7) & 1 and not ((tileregs(cap, tm) >> 5) & 1)
                     else (1 if (tileregs(cap, tm) >> 7) & 1 else 0)) for tm in pixmaps}
    modes = {tm: blend_mode(cap, tm) for tm in pixmaps}
    # tcram 0x4c bit 16 picks alpha over additive for blended sprites (hng64_v.cpp:697)
    spr_alpha = (int(cap.tcram[0x4C // 4]) >> 16) & 1

    for y in range(height):
        dst = img[y]
        for i in list(range(0x1F, 0x0F, -1)) + list(range(0x0F, -1, -1)):
            for p, tm in order:
                if p != i:
                    continue
                idx = draw_tilemap_line(cap, pixmaps[tm], tm, y)
                sel = idx != 0
                if not sel.any():
                    continue
                src = cluts[sel_clut[tm]][np.clip(idx[sel], 0, base.shape[0] - 1)]
                dst[sel] = src if modes[tm] == 1 else _add(dst[sel], src)
            if (i & 3) == 0 and sprites is not None:
                sp = sprites[y]
                sel = ((sp & 0x0FFF) != 0) & ((sp & 0x7000) == ((i >> 2) << 12))
                if not sel.any():
                    continue
                src = base[sp[sel] & 0x0FFF]
                bl = (sp[sel] & 0x8000) != 0
                out = src.copy()
                if bl.any():
                    out[bl] = (_alpha(dst[sel][bl], src[bl]) if spr_alpha
                               else _add(dst[sel][bl], src[bl]))
                dst[sel] = out
    return img


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("set")
    ap.add_argument("name")
    ap.add_argument("--diff", action="store_true", help="also write diff.png and count pixels")
    ap.add_argument("--dump", action="store_true",
                    help="also write per-layer palette indices for the RTL benches: "
                         "layer<N>.bin and sprites.bin, 512x448 u16, little-endian")
    a = ap.parse_args()
    d = REPO / "debug" / f"{a.set}-{a.name}"
    cap = Capture(d)
    gfx = Gfx(reorder_scrtile(region(a.set, "scrtile")))
    img = render(cap, gfx, Gfx(region(a.set, "sprtile")))
    Image.fromarray(img).save(d / "model.png")
    print(f"-> {d / 'model.png'}")
    for tm in range(4):
        r = int(tileregs(cap, tm))
        print(f"  tm{tm}: regs {r:04x} enable {(r >> 6) & 1} pri {r & 0x1f:02x} "
              f"big {(r >> 9) & 1} 8bpp {(r >> 10) & 1} wrap {(r >> 8) & 1} "
              f"mosaic {(r >> 12) & 0xf} line {(not ((r >> 11) & 1)) and 1 or 0} "
              f"scrollbase {int(scrollbase(cap, tm)):04x}")
    if a.dump:
        for tm in range(4):
            if not (tileregs(cap, tm) >> 6) & 1:
                continue
            idx = np.zeros((448, 512), dtype=np.uint16)
            pm = tilemap_pixmap(cap, gfx, tm)
            for y in range(448):
                idx[y] = draw_tilemap_line(cap, pm, tm, y)
            (d / f"layer{tm}.bin").write_bytes(idx.astype("<u2").tobytes())
        spr = draw_sprites(cap, Gfx(region(a.set, "sprtile")))
        (d / "sprites.bin").write_bytes(spr.astype("<u2").tobytes())
        (d / "model_rgb.bin").write_bytes(img.tobytes())   # 448 x 512 x 3, for the mixer bench
        print(f"  dumped per-layer indices and sprites.bin in {d}")

    if a.diff:
        ref = np.array(Image.open(d / "reference.png").convert("RGB"))
        n = min(ref.shape[0], img.shape[0])
        bad = np.any(ref[:n] != img[:n], axis=-1)
        Image.fromarray((bad * 255).astype(np.uint8)).save(d / "diff.png")
        print(f"  {bad.sum()} of {bad.size} pixels differ ({100.0 * bad.sum() / bad.size:.1f}%)"
              f" -> {d / 'diff.png'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
