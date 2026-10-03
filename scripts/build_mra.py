#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Generate the .mra files: one per in-scope set, laid out to the DDR3 map.

    python scripts/build_mra.py             -> releases/<Description>.mra
    python scripts/build_mra.py sams64      -> just that set

WHAT THE IMAGE IS
-----------------
Unlike the sibling cores, this one does not copy the DDR3 image into SDRAM: the
video engines read `scrtile` and `sprtile` from DDR3 every line, and the CPU
reads `gameprg` from it (docs/MEMORY.md). So the `<rom index="0">` stream IS the
DDR3 window at 0x30000000, byte for byte, and every region is stored exactly as
MAME's ROM_START builds it before region_post_process() -- which is the image
`scripts/rom_regions.py` produces and the video benches are pixel-exact against.

Two transforms MAME applies are therefore NOT applied here, and are undone in
the core instead:

  * `init_reorder_gfx` interleaves `scrtile`'s halves in 32-byte units. An .mra
    cannot express that (the HPS writes DDR3 without the core seeing the bytes,
    and no `<interleave>` works in 32-byte chunks), so `rtl/video/hng64_video.sv`
    translates the address.
  * `region_post_process` byte-swaps a region whose declared endianness is not
    the host's. The core's CPU is big-endian and reads bytes in address order,
    which is the pre-swap image.

WHERE THE LAYOUT COMES FROM
---------------------------
Region sizes differ per set by up to 32 MB, and the tile reorder above needs
half the `scrtile` size at run time, so the bases cannot be fixed in the RTL
without either padding every set to the largest or editing RTL per set. The
image is packed instead, and `<rom index="1">` carries the bases and sizes --
the generalisation of the mod byte the ROADMAP calls for ("per-set differences
are .mra configuration"). Both come out of `layout()`, so they cannot drift.

WHAT IS CHECKED
---------------
The generated .mra is read back with scripts/mra.py -- the transcription of
mra-tools-c's own `map` decoding -- and every region of the resulting image is
compared byte for byte with scripts/rom_regions.py's. Nothing here reasons about
the map digits: they are derived from each record's ROMX_LOAD geometry and then
proven against an image the benches already agree with. docs/LESSONS_LEARNED.md
is explicit that every interleave derived by argument on these cores was wrong.
"""
import re
import sys
from pathlib import Path
from xml.sax.saxutils import escape

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
import mra  # noqa: E402
import rom_regions  # noqa: E402
from extract_romstart import IN_SCOPE, blocks, region_decl, region_records  # noqa: E402

RBF = "HyperNG64"
PARENT = "hng64"
MCU_ROM, MCU_CRC = "tmp87ph40an.bin", "b70df21f"
NVRAM_SIZE = 0x4000
MAMEVERSION = "0285"

# The regions the core reads at run time, in DDR3 order. `textures0` and `verts`
# are Phase 3: they append at the end, so adding them moved nothing.
LAYOUT = ["gameprg", "bios", "scrtile", "sprtile", "textures0", "verts"]
# The 3D's own buffers start here (rtl/hng64_core.sv, D3_*): the blocked textures,
# the depth plane and two colour planes. The ROM image must end below it.
D3_BASE = 0xE000000
ALIGN = 0x100000                # rtl/hng64_core.sv adds only the tile ROM bases' top 8 bits

# rom index 1. Big-endian, the CPU's order; `layout()` fills it.
CFG_MAGIC = b"HNG2"
CFG_REGIONS = ["gameprg", "bios", "scrtile", "sprtile", "textures0", "verts"]


def driver():
    return rom_regions.driver_text()


def games(text):
    """setname -> (year, maker, description) from the driver's GAME() lines."""
    out = {}
    for m in re.finditer(r'^GAMEL?\(\s*(\d+),\s*(\w+),.*?,\s*ROT\d+,\s*"([^"]*)"\s*,'
                         r'\s*"([^"]*)"', text, re.M):
        out[m.group(2)] = (m.group(1), m.group(3), m.group(4))
    return out


def init_of(text, game):
    """The GAME() line's init function, which sets the flags word."""
    m = re.search(r'^GAMEL?\(\s*\d+,\s*' + game + r'\s*,(?:[^,]*,){4}\s*(\w+)\s*,', text, re.M)
    if not m:
        raise SystemExit(f"no GAME() line for {game}")
    return m.group(1)


def layout(decls):
    """[(region, base, size)] packed in LAYOUT order, aligned to ALIGN.

    The size is the ROM_REGION's, not the extent of its loads. A set can leave
    a region short or holed (buriki's scrtile stops 8 MB early and has an 8 MB
    hole at 0x1800000) and MAME still presents the declared region -- and the
    tile reorder splits it at half the DECLARED size, so a short image would
    put every tile of one half at the wrong address.
    """
    out, pos = [], 0
    # hng64_video adds half of scrtile as an OR (rtl/video/hng64_video.sv, scr_raw)
    scr = decls["scrtile"][0]
    if scr & (scr - 1):
        raise SystemExit(f"scrtile is {scr:#x} bytes, not a power of two")
    for region in LAYOUT:
        size = decls[region][0]
        out.append((region, pos, size))
        pos += (size + ALIGN - 1) & ~(ALIGN - 1)
    if pos > D3_BASE:
        raise SystemExit(f"the ROM image ends at {pos:#x}, over the 3D buffers at {D3_BASE:#x}")
    return out


def config_blob(lay, flags=0):
    """rom index 1: the magic, then a base and a size per region of CFG_REGIONS,
    then the flags word (bit 0: init_ss64's m_samsho64_3d_hack). A region the
    .mra does not carry gets a zero size, which is how the core knows it is
    absent."""
    have = {r: (b, s) for r, b, s in lay}
    blob = bytearray(CFG_MAGIC)
    for r in CFG_REGIONS:
        base, size = have.get(r, (0, 0))
        blob += base.to_bytes(4, "big") + size.to_bytes(4, "big")
    blob += flags.to_bytes(4, "big")
    return bytes(blob)


def groups(recs):
    """Records grouped into interleaves.

    Each ROMX_LOAD writes `group` bytes every `group + skip` (read_rom_data,
    MAME romload.cpp:812). Records that share a stride and differ only in where
    they start within it fill one output word between them, which is exactly
    what an <interleave> does; `dest - dest % stride` is that word's base.
    """
    by_base = {}
    for kind, name, dest, ln, crc in recs:
        g, skip, rev = rom_regions.geometry(kind)
        stride = g + skip
        lane = dest % stride
        by_base.setdefault((dest - lane, stride), []).append((lane, g, rev, name, ln, crc))
    return [(base, stride, sorted(by_base[(base, stride)]))
            for base, stride in sorted(by_base)]


def map_digits(lane, g, rev, stride):
    """The `map` attribute for one part of an <interleave>.

    mra.pattern_from_map is the decoder, transcribed from mra-tools-c: the
    string is read right to left, a digit's position from the right is the
    output byte it feeds, and the digit itself is the source byte plus one.
    So this is written to satisfy that decoder and then checked against it.
    """
    digits = ["0"] * stride
    for j in range(g):
        src = (g - 1 - j) if rev else j
        digits[stride - 1 - (lane + j)] = str(src + 1)
    m = "".join(digits)
    idx, pat = mra.pattern_from_map(m)
    want = [(g - 1 - j) if rev else j for j in range(g)]
    if (idx, pat) != (lane, want):
        raise SystemExit(f"map {m!r} decodes to {(idx, pat)}, meant {(lane, want)}")
    return m


def region_xml(recs, fill=0, crc_ok=True):
    """<part>/<interleave> elements for one region, and the bytes they produce.

    A hole between two loads is emitted as the region's erase byte, so the
    stream is the region MAME presents rather than the ROMs concatenated.
    """
    lines, total = [], 0
    for base, stride, members in groups(recs):
        if base > total:
            lines.append(f'      <part repeat="{base - total:#x}">{fill:02X}</part>')
            total = base
        n = max(ln // g for _lane, g, _rev, _nm, ln, _c in members)
        if stride == 1:
            for _lane, _g, _rev, name, ln, crc in members:
                lines.append(f'      <part name="{name}"{crcattr(crc, crc_ok)}/>')
        else:
            lines.append(f'      <interleave output="{stride * 8}">')
            for lane, g, rev, name, ln, crc in members:
                m = map_digits(lane, g, rev, stride)
                lines.append(f'        <part name="{name}"{crcattr(crc, crc_ok)} map="{m}"/>')
            lines.append("      </interleave>")
        total += n * stride
    return lines, total


def crcattr(crc, on):
    return f' crc="{crc:08x}"' if on and crc is not None else ""


def mra_name(desc):
    """MAME's description as a file name. `<name>` and the file must agree, and
    a file name cannot hold "/" or ":", so both separators become " - ". The
    rule is mechanical rather than a choice per set: a shortened title would be
    a transcription, and the alternate titles are what MAME calls the set."""
    name = desc.replace(" / ", " - ").replace(": ", " - ")
    illegal = set(r'/\:?*"<>|')
    bad = illegal & set(name)
    if bad:
        raise SystemExit(f"{desc!r}: {sorted(bad)} cannot go in a file name")
    return name


def esc(s):
    return escape(str(s), {'"': "&quot;"})


def build(game, bl, meta, out_dir):
    recs_by_region, decls = {}, {}
    for region in LAYOUT:
        recs, unknown = region_records(bl[game], region)
        if unknown:
            sys.exit(f"{game} {region}: unparsed records: {unknown[:2]}")
        if not recs:
            sys.exit(f"{game}: no {region} region")
        recs_by_region[region] = recs
        decls[region] = region_decl(bl[game], region)
    lay = layout(decls)

    year, maker, desc = meta[game]
    name = mra_name(desc)
    xml = ["<!-- Generated by scripts/build_mra.py. The index-0 stream IS the core's DDR3",
           "     window at 0x30000000, region by region, exactly as MAME's ROM_START builds",
           "     each one; index 1 carries the bases and sizes. See docs/MEMORY.md. -->",
           "<misterromdescription>",
           f"  <name>{esc(name)}</name>",
           f"  <setname>{game}</setname>",
           f"  <year>{year}</year>",
           f"  <manufacturer>{esc(maker)}</manufacturer>",
           f"  <rbf>{RBF}</rbf>",
           "  <rotation>horizontal</rotation>",
           # the J1 line of HyperNG64.sv's CONF_STR, in its order
           '  <buttons names="Button 1,Button 2,Button 3,Button 4,Start,Coin,Pause,Service,Test"'
           ' default="A,B,X,Y,Start,Select,L"/>',
           # MAME lists no DIPs for the fight sets: this one is the core's own Flip Screen,
           # read by HyperNG64.sv and never by the game
           '  <switches default="00" base="0">',
           '    <dip name="Flip Screen" bits="0" ids="Off,On"/>',
           '  </switches>',
           f"  <mameversion>{MAMEVERSION}</mameversion>"]

    # init_ss64 sets m_samsho64_3d_hack (hng64.cpp:1847)
    blob = config_blob(lay, flags=int(init_of(driver(), game) == "init_ss64"))
    # index 1 comes first: the HPS sends roms in file order, and the core needs
    # the layout before anything reads DDR3.
    xml.append('  <rom index="1"><part>' +
               " ".join(f"{b:02X}" for b in blob) + "</part></rom>")
    # the IO MCU's ROM: MAME's "iomcu" region loads the 32 KB file at 0x8000 and the MCU
    # decodes ROM at 0xc000-0xffff, the file's top 16 KB (rtl/io/hng64_iomcu.sv)
    xml.append(f'  <rom index="2" zip="{PARENT}.zip" md5="none">'
               f'<part name="{MCU_ROM}" crc="{MCU_CRC}" offset="0x4000" length="0x4000"/></rom>')
    for region, base, size in lay:
        xml.append(f"  <!-- {region}: {size:#x} bytes at {base:#x} -->")
    xml.append(f'  <rom index="0" zip="{game}.zip|{PARENT}.zip" md5="none"'
               ' address="0x30000000">')
    pos = 0
    for region, base, size in lay:
        if pos != base:
            sys.exit(f"{game}: {region} would start at {pos:#x}, the layout says {base:#x}")
        fill = decls[region][1]
        body, produced = region_xml(recs_by_region[region], fill)
        if produced > size:
            sys.exit(f"{game} {region}: parts produce {produced:#x} bytes, region is {size:#x}")
        xml.append(f"    <!-- {region}: {size:#x} bytes at {base:#x}"
                   f"{f', {size - produced:#x} of erase byte {fill:#04x}' if produced != size else ''}"
                   " -->")
        xml += body
        pad = ((size + ALIGN - 1) & ~(ALIGN - 1)) - produced
        if pad:
            xml.append(f'      <part repeat="{pad:#x}">{fill:02X}</part>')
        pos = base + produced + pad
    xml.append("  </rom>")
    # NVRAM: 16 KB at 0x1f800000. Where MAME's set has an "nvram" region (fatfurwa's per-region
    # defaults, the export one by ROM_DEFAULT_BIOS) it is the first-run contents; the saved .nvm,
    # when there is one, is loaded after it.
    nv_recs, unknown = region_records(bl[game], "nvram")
    if unknown:
        sys.exit(f"{game} nvram: unparsed records: {unknown[:2]}")
    if nv_recs:
        body, produced = region_xml(nv_recs, 0)
        if produced != NVRAM_SIZE:
            sys.exit(f"{game} nvram: parts produce {produced:#x} bytes, want {NVRAM_SIZE:#x}")
        xml.append(f'  <rom index="4" zip="{game}.zip|{PARENT}.zip" md5="none">')
        xml += body
        xml.append("  </rom>")
    xml.append(f'  <nvram index="4" size="{NVRAM_SIZE}"/>')
    xml.append("</misterromdescription>")

    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / f"{name}.mra"
    path.write_text("\n".join(xml) + "\n", encoding="utf8")
    return path, lay


def verify(path, game, lay):
    """Read the .mra back and compare every region with rom_regions.py's image."""
    from prep_boot_tb import find_zip
    zips = [find_zip(game), find_zip(PARENT)]
    image = mra.build_image(path, zips)
    bad = 0
    for region, base, size in lay:
        want = rom_regions.region(game, region)
        if len(want) != size:
            print(f"  {region}: layout says {size:#x}, the region image is {len(want):#x}")
            bad += 1
            continue
        got = image[base:base + size]
        if got != want:
            first = next(i for i in range(size) if got[i] != want[i])
            print(f"  {region}: differs at {first:#x} (got {got[first]:#04x}, "
                  f"want {want[first]:#04x})")
            bad += 1
    # index 2 against the top 16 KB of MAME's iomcu region
    import zipfile
    import xml.etree.ElementTree as ET
    part = ET.parse(path).getroot().find("rom[@index='2']/part")
    with zipfile.ZipFile(find_zip(PARENT)) as z:
        mcu = mra._part_data(z, part)
    if mcu != rom_regions.region(game, "iomcu")[0xc000:]:
        print("  iomcu: index 2 differs from the region's 0xc000-0xffff")
        bad += 1
    # index 4, where there is one, against MAME's nvram region
    parts = ET.parse(path).getroot().findall("rom[@index='4']/part")
    if parts:
        with zipfile.ZipFile(find_zip(game)) as z:
            nv = b"".join(mra._part_data(z, el) for el in parts)
        if nv != rom_regions.region(game, "nvram"):
            print("  nvram: index 4 differs from the region")
            bad += 1
    return bad, len(image)


def main():
    wanted = [a for a in sys.argv[1:] if not a.startswith("-")] or IN_SCOPE
    text = driver()
    bl = blocks(text)
    meta = games(text)
    out_dir = REPO / "releases"
    bad = 0
    for game in wanted:
        path, lay = build(game, bl, meta, out_dir)
        nbad, size = verify(path, game, lay)
        bad += nbad
        print(f"{'FAIL' if nbad else 'ok  '}  {path.name}: {size / 2**20:.0f} MB, "
              f"{len(lay)} regions")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
