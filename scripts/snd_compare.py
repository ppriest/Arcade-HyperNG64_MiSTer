#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""MAME's -wavwrite output against the sound board bench's, as level envelopes.

    python scripts/snd_compare.py debug/<set>-sound/<set>.wav obj_hng64snd/<set>.wav out.png

Prints, per front channel, the RMS of each and the correlation of their 10 ms envelopes, and
draws the envelopes (MAME above, the bench below, the difference at the bottom).
"""
import sys
import wave

import numpy as np


def load(path):
    w = wave.open(path)
    n, ch, rate = w.getnframes(), w.getnchannels(), w.getframerate()
    a = np.frombuffer(w.readframes(n), dtype="<i2").reshape(-1, ch).astype(np.float64)
    return a, rate


def envelope(x, win):
    n = len(x) // win
    return np.sqrt((x[: n * win].reshape(n, win) ** 2).mean(axis=1))


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    a, ra = load(sys.argv[1])
    b, rb = load(sys.argv[2])
    if ra != rb:
        sys.exit(f"rates differ: {ra} and {rb}")
    n = min(len(a), len(b))
    a, b = a[:n], b[:n]
    win = ra // 100
    envs = []
    for c, name in ((0, "left"), (1, "right")):
        ea, eb = envelope(a[:, c], win), envelope(b[:, c], win)
        r = np.corrcoef(ea, eb)[0, 1] if ea.std() and eb.std() else float("nan")
        print(f"{name}: RMS MAME {np.sqrt((a[:, c] ** 2).mean()):.1f}, bench "
              f"{np.sqrt((b[:, c] ** 2).mean()):.1f}; 10 ms envelope correlation {r:.4f}")
        envs.append((ea, eb))

    from PIL import Image, ImageDraw
    w_px, h_px = 1200, 120
    img = Image.new("RGB", (w_px, h_px * 6), "white")
    d = ImageDraw.Draw(img)
    top = max(max(e.max() for e in pair) for pair in envs) or 1.0
    rows = []
    for ea, eb in envs:
        rows += [ea, eb, np.abs(ea - eb)]
    for i, e in enumerate(rows):
        y0 = i * h_px
        xs = np.linspace(0, w_px - 1, len(e))
        pts = [(float(x), y0 + h_px - 1 - float(v) / top * (h_px - 10)) for x, v in zip(xs, e)]
        d.line(pts, fill=("navy", "darkgreen", "red")[i % 3])
        d.text((4, y0 + 2), ("L MAME", "L bench", "L |diff|", "R MAME", "R bench", "R |diff|")[i],
               fill="black")
        d.line([(0, y0 + h_px - 1), (w_px, y0 + h_px - 1)], fill="gray")
    img.save(sys.argv[3])
    print(f"-> {sys.argv[3]} ({n / ra:.2f} s)")


if __name__ == "__main__":
    main()
