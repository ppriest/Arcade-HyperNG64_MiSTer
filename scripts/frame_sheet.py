#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""A comparison sheet: per frame, MAME's screenshot | ours | where they differ, with the count.

    python scripts/frame_sheet.py sams64 3500 5000 --ours model_full.png --out debug/sheet.png
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

REPO = Path(__file__).resolve().parent.parent


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game")
    ap.add_argument("frames", type=int, nargs="+")
    ap.add_argument("--ours", default="model_full.png", help="file in each capture directory")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    rows = []
    for f in a.frames:
        d = REPO / "debug" / f"{a.game}-f{f}"
        ref = np.asarray(Image.open(d / "reference.png").convert("RGB"))[:448]
        img = np.asarray(Image.open(d / a.ours).convert("RGB"))[:448]
        bad = (ref != img).any(axis=-1)
        diff = np.zeros_like(ref)
        diff[bad] = (255, 0, 0)
        row = Image.fromarray(np.concatenate([ref, img, diff], axis=1))
        ImageDraw.Draw(row).text((6, 6), f"{a.game} frame {f}: MAME | {a.ours} | diff "
                                         f"({int(bad.sum())} of {bad.size} px)", fill=(255, 0, 255))
        rows.append(row.resize((768, 224)))
    sheet = Image.new("RGB", (768, 224 * len(rows)))
    for i, r in enumerate(rows):
        sheet.paste(r, (0, 224 * i))
    sheet.save(a.out)
    print(a.out)


if __name__ == "__main__":
    main()
