#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build a set's ROM region image from the zips, the way MAME loads it.

    python scripts/rom_regions.py sams64 scrtile        # writes debug/rom/sams64-scrtile.bin
    from rom_regions import region                      # region("sams64", "scrtile") -> bytes

The records come from the driver's ROM_START (scripts/extract_romstart.py), so the interleave
is the driver's, not a guess. Files are read from the set's zip and its parent's (hng64), from
roms/ or MAME_ROMPATH. Images are cached under debug/rom/ because they are tens of megabytes.
"""
import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
from coretools import setting  # noqa: E402
from extract_romstart import blocks, region_decl, region_records  # noqa: E402
from prep_boot_tb import find_zip  # noqa: E402

# --- core-specific: edit for this core ---------------------------------------
# The driver. MAME_SRC may be the checkout root or the .cpp itself.
DRIVER = "src/mame/snk/hng64.cpp"
# -----------------------------------------------------------------------------


def driver_text():
    src = Path(setting("MAME_SRC") or "")
    if src.is_dir():
        src = src / DRIVER
    if not src.is_file():
        raise SystemExit(f"driver not found at {src} (set MAME_SRC in mister.env)")
    return src.read_text(encoding="utf8", errors="replace")

CACHE = REPO / "debug" / "rom"


def _file(name, sets):
    for s in sets:
        try:
            z = zipfile.ZipFile(find_zip(s))
        except SystemExit:
            continue
        if name in z.namelist():
            return z.read(name)
    raise SystemExit(f"{name} not in {' or '.join(s + '.zip' for s in sets)}")


# Every ROM_LOADnn_* macro is a case of ROMX_LOAD: `group` bytes are copied,
# reversed if ROM_REVERSE, and the destination then advances by group + skip
# (read_rom_data, MAME romload.cpp:812). Expressing them all one way means the
# byte order is implemented once.
GEOMETRY = {
    "load":         (1, 0, 0),
    "load16_byte":  (1, 1, 0),
    "load32_byte":  (1, 3, 0),
    "load32_word":  (2, 2, 0),
    "load16_wswap": (2, 0, 1),
    "load32_wswap": (2, 2, 1),
}


def geometry(kind):
    if kind.startswith("group:"):
        g, skip, rev = (int(v) for v in kind.split(":")[1:])
        return g, skip, rev
    if kind not in GEOMETRY:
        raise SystemExit(f"unhandled record kind {kind}")
    return GEOMETRY[kind]


def rec_end(kind, dest, length):
    g, skip, _rev = geometry(kind)
    return dest + ((length + g - 1) // g - 1) * (g + skip) + g


def place(out, kind, dest, data):
    g, skip, rev = geometry(kind)
    stride = g + skip
    n = len(data) // g
    for j in range(g):
        src = (g - 1 - j) if rev else j
        out[dest + j:dest + j + stride * n:stride] = data[src::g]


def region(game, want, parent="hng64"):
    """The region image as MAME builds it, BEFORE region_post_process().

    MAME byte-swaps a region whose declared endianness is not the host's, so
    that its native accessors work; the swap is undone again when a big-endian
    CPU reads a byte. What the core needs in memory is the pre-swap image, in
    CPU address order, which is what the load records alone produce.
    """
    cached = CACHE / f"{game}-{want}.bin"
    if cached.exists():
        return cached.read_bytes()
    body = blocks(driver_text())[game]
    recs, unknown = region_records(body, want)
    if not recs:
        raise SystemExit(f"no {want} region in {game}")
    if unknown:
        raise SystemExit(f"{game} {want}: unparsed records: " + "; ".join(unknown))
    size, fill = region_decl(body, want)
    end = max(rec_end(kind, dest, ln) for kind, _nm, dest, ln, _cs in recs)
    if end > size:
        raise SystemExit(f"{game} {want}: loads reach {end:#x}, the region is {size:#x}")
    out = bytearray(bytes([fill]) * size)
    for kind, nm, dest, ln, _cs in recs:
        place(out, kind, dest, _file(nm, [game, parent])[:ln])
    CACHE.mkdir(parents=True, exist_ok=True)
    cached.write_bytes(out)
    return bytes(out)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 2:
        sys.exit(__doc__)
    data = region(args[0], args[1])
    if "--reorder" in sys.argv:
        # MAME's init_reorder_gfx, for benches that want the ROM as the decoder sees it
        sys.path.insert(0, str(REPO / "scripts"))
        from render_model import reorder_scrtile
        data = reorder_scrtile(data)
        out = CACHE / f"{args[0]}-{args[1]}-reordered.bin"
        out.write_bytes(data)
        print(f"{len(data) / 2**20:.0f} MB -> {out}")
        return 0
    print(f"{len(data) / 2**20:.0f} MB -> {CACHE / f'{args[0]}-{args[1]}.bin'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
