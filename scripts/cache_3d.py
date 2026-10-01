#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The 3D's DDR3 traffic per frame, for choosing the texture cache and the render buffer's cache.

    python scripts/render_3d_fx.py sams64 2500 --dump      # writes debug/sams64-f2500/fragments.npz
    python scripts/cache_3d.py sams64-f2500 [more captures]
    python scripts/cache_3d.py --summary sams64-f2500 [more captures]

Replays the fragments of a captured frame, in the rasteriser's order, through:

- a texture cache in front of textures0: set-associative, LRU, every textured fragment reads its
  texel whether or not it is drawn (the pen decides that);
- a render-buffer cache: one 64-bit word a pixel (colour, depth and the frame tag), row-major,
  write-back, LRU; a drawn fragment reads its pixel (the depth test), a written one dirties it,
  and the dirty lines are written back at the end of the frame. The frame tag replaces the clear,
  so there is no clear traffic.

and prints misses (each one DDR3 burst of a line) and bytes, with the display's read-out of the
visible window added: 512 x 448 pixels of colour a frame, at 2 or 8 bytes a pixel.
"""
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parent.parent


def cache(lines, size, line, ways, writes=None):
    """LRU set-associative cache over line numbers. Returns (misses, dirty write-backs)."""
    nsets = size // (line * ways)
    sets = [[] for _ in range(nsets)]                 # most recent last: [line, dirty]
    misses = wb = 0
    for i, ln in enumerate(lines):
        s = sets[ln % nsets]
        for j, e in enumerate(s):
            if e[0] == ln:
                s.append(s.pop(j))
                break
        else:
            misses += 1
            if len(s) == ways:
                wb += s.pop(0)[1]
            s.append([ln, 0])
        if writes is not None and writes[i]:
            s[-1][1] = 1
    wb += sum(e[1] for s in sets for e in s)          # the flush at the frame's end
    return misses, wb


PORT_BYTES_PER_CLOCK = 8          # the DDRAM port: 64 bits a clock at clk2x
FRAME_CLOCKS = 125_000_000 // 60  # clk2x clocks in a 60 Hz frame


def summary(cap, addr, pixel, draw, written):
    """Two layouts, a frame's DDR3 bytes and the port's clocks for them:
    one: a 64-bit word a pixel (tag, z, colour); 1 KB 64 B 2-way cache; display reads 8 B a pixel.
    two: a depth plane of 32 bits (tag, z) through the same cache, a colour plane of 16 bits
    written through a write-combining 1 KB 64 B 2-way buffer (no reads), display 2 B a pixel.
    Texture: 8 KB, 32 B lines, direct mapped."""
    tex = addr[addr >= 0]
    tm, _ = cache((tex // 32).tolist(), 8192, 32, 1)
    px, wr = pixel[draw], written[draw]
    rows = []
    m, wb = cache((px * 8 // 64).tolist(), 1024, 64, 2, wr.tolist())
    rows.append(("one word a pixel", tm * 32, m * 64, wb * 64, 512 * 448 * 8, tm + m + wb))
    dm, dwb = cache((px * 4 // 64).tolist(), 1024, 64, 2, wr.tolist())
    cw = pixel[written]
    _, cwb = cache((cw * 2 // 64).tolist(), 1024, 64, 2, [True] * len(cw))
    rows.append(("depth and colour planes", tm * 32, dm * 64, (dwb + cwb) * 64, 512 * 448 * 2,
                 tm + dm + dwb + cwb))
    print(f"{cap}: per frame           texture KB  buffer read KB  buffer write KB  display KB  bursts"
          f"  port clocks (of {FRAME_CLOCKS})")
    for name, t, r, w, dsp, bursts in rows:
        tot = t + r + w + dsp
        print(f"  {name:24s} {t / 1024:8.0f} {r / 1024:13.0f} {w / 1024:14.0f} {dsp / 1024:11.0f} "
              f"{bursts:8d}  {tot // PORT_BYTES_PER_CLOCK:8d} ({100 * tot / PORT_BYTES_PER_CLOCK / FRAME_CLOCKS:.0f}%)")


def main():
    if sys.argv[1] == "--summary":
        for cap in sys.argv[2:]:
            f = np.load(REPO / "debug" / cap / "fragments.npz")
            summary(cap, f["addr"], f["pixel"], f["draw"], f["written"])
        return
    for cap in sys.argv[1:]:
        f = np.load(REPO / "debug" / cap / "fragments.npz")
        addr, pixel, draw, written = f["addr"], f["pixel"], f["draw"], f["written"]
        tex = addr[addr >= 0]
        print(f"{cap}: {len(addr)} fragments, {len(tex)} textured, {int(draw.sum())} drawn, "
              f"{int(written.sum())} written")
        print("  texture cache           misses   KB read")
        for size in (1024, 2048, 4096, 8192, 16384):
            for line in (16, 32, 64):
                for ways in (1, 2, 4):
                    m, _ = cache((tex // line).tolist(), size, line, ways)
                    print(f"  {size // 1024:2d} KB {line:2d} B {ways}-way  {m:8d}  {m * line / 1024:8.0f}")
        print("  render buffer           read misses  write-backs  KB")
        px, wr = pixel[draw], written[draw]
        for size in (512, 1024, 2048, 4096):
            for line in (32, 64):
                for ways in (1, 2):
                    m, wb = cache((px * 8 // line).tolist(), size, line, ways, wr.tolist())
                    print(f"  {size:5d} B {line:2d} B {ways}-way  {m:8d}  {wb:8d}  "
                          f"{(m + wb) * line / 1024:8.0f}")


if __name__ == "__main__":
    main()
