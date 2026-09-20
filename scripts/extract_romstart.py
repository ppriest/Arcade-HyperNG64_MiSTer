#!/usr/bin/env python3
"""Extract a set's ROM_START records for one region straight from the MAME driver.

    python scripts/extract_romstart.py --emit           # the maincpu SETS table
    python scripts/extract_romstart.py <set> <set>      # just these
    python scripts/extract_romstart.py --region gfx1 <set>
    python scripts/extract_romstart.py --driver path/to/driver.cpp --emit

The driver is MAME_SRC (mister.env or the environment) unless --driver is given.

WHY EXTRACT RATHER THAN TYPE
----------------------------
Hand transcription of ROM loads is the interleave-by-reasoning mistake in
slower motion: dozens of sets, several load forms, and offsets that differ by
one between the even and odd ROM of a pair. The driver is the authority.

What this understands (add a driver's own load macros to KINDS):

    ROM_LOAD16_BYTE       one byte lane; dest & 1 selects even or odd
    ROM_LOAD16_WORD_SWAP  whole words, byte-swapped, no pairing
    ROM_LOAD              plain, byte for byte
    ROM_LOAD24_BYTE       one byte every THREE, from dest
    ROM_LOAD24_WORD_SWAP  two byte-swapped bytes every three, from dest
    ROM_CONTINUE          the rest of the PREVIOUS file, at another offset
    ROMX_LOAD             the general form, as `group:<groupsize>:<skip>:<rev>`,
                          which is what read_rom_data() in MAME's romload.cpp
                          actually implements; the macros above are special
                          cases of it. ROM_BIOS(n) records are kept only for
                          the selected system BIOS.

An object-like macro named in EXPAND_MACROS is substituted into each ROM_START
body before parsing, because a driver that keeps its BIOS in one is otherwise
invisible to a ROM_START scan.

It deliberately does NOT try to be a general MAME ROM loader. Anything it does
not recognise is reported rather than skipped, so a set is never emitted with a
record silently missing -- which would produce an image that is subtly short
and still looks plausible.
"""
import argparse
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from coretools import setting   # noqa: E402

SRC = setting("MAME_SRC") or ""

# --- core-specific: edit for this core -------------------------------------
# Load macros the driver uses -> the record kind emitted. Anything in a
# region that is not listed here is reported, not skipped. A driver's own
# macros (ROM_LOAD24_*, ...) go here too.
KINDS = {
    "ROM_LOAD16_BYTE": "load16_byte",
    "ROM_LOAD16_WORD_SWAP": "load16_wswap",
    "ROM_LOAD": "load",
    "ROM_LOAD16_WORD": "load",         # bytes as they are in the file
    "ROM_LOAD32_BYTE": "load32_byte",
    "ROM_LOAD32_WORD": "load32_word",
    "ROM_LOAD32_WORD_SWAP": "load32_wswap",
    # ROM_COPY("src", srcofs, dstofs, len) takes bytes from ANOTHER region
    # rather than from a file, so it carries no CRC.
    "ROM_COPY": "copy",
}
# Object-like macros holding ROM records, expanded into each ROM_START body.
EXPAND_MACROS = ["HNG64_BIOS"]
# Driver-local function-like ROM macros, rewritten to the MAME form they wrap.
# hng64.cpp:2681 defines ROM_LOAD_HNG64_BIOS(bios,name,offset,length,hash) as
# ROMX_LOAD(name, offset, length, hash, ROM_BIOS(bios)).
PRE_REWRITE = [
    (r'ROM_LOAD_HNG64_BIOS\s*\(\s*(\d+)\s*,\s*(.*)\)\s*$',
     r'ROMX_LOAD( \g<2>, ROM_BIOS(\g<1>) )'),
]
# The sets in scope: the default when none are named.
IN_SCOPE = ["sams64", "sams64_2", "fatfurwa", "buriki"]
# ---------------------------------------------------------------------------


def expand_object_macros(text, names=None):
    r"""Substitute an object-like `#define NAME \` ... macro into the body text.

    A driver that keeps its BIOS records in a macro (hng64.cpp's HNG64_BIOS)
    has them nowhere a ROM_START scan can see. Expanding is still extraction:
    the records come from the driver, not from a transcription.
    """
    for name in (names if names is not None else EXPAND_MACROS):
        lines = text.split("\n")
        start = None
        for i, line in enumerate(lines):
            if re.match(r'^#define[ \t]+' + re.escape(name) + r'[ \t]*\\$', line):
                start = i
                break
        if start is None:
            continue
        end = start
        while lines[end].endswith("\\"):
            end += 1
        body = [l[:-1].rstrip() if l.endswith("\\") else l
                for l in lines[start + 1:end + 1]]
        out = []
        for i, line in enumerate(lines):
            if start <= i <= end:
                continue
            if line.strip() == name:
                out.extend(body)
            else:
                out.append(line)
        text = "\n".join(out)
    return text


def pre_rewrite(line):
    for pat, repl in PRE_REWRITE:
        line = re.sub(pat, repl, line)
    return line


def romx_geometry(flags):
    """ROMX_LOAD's flags as read_rom_data() (MAME romload.cpp:812) uses them:
    groupsize bytes are copied, reversed if ROM_REVERSE, and the destination
    then advances by groupsize + skip. Every ROM_LOADnn_* macro is a case."""
    group = 4 if "ROM_GROUPDWORD" in flags else 2 if "ROM_GROUPWORD" in flags else 1
    m = re.search(r'ROM_SKIP\(\s*(\d+)\s*\)', flags)
    rev = 1 if "ROM_REVERSE" in flags else 0
    return group, (int(m.group(1)) if m else 0), rev


def bios_choice(body, want=None):
    """(selected tag, {index: tag}) from ROM_SYSTEM_BIOS / ROM_DEFAULT_BIOS."""
    tags = {int(i): t for i, t in
            re.findall(r'ROM_SYSTEM_BIOS\(\s*(\d+)\s*,\s*"([^"]+)"', body)}
    m = re.search(r'ROM_DEFAULT_BIOS\(\s*"([^"]+)"', body)
    return (want or (m.group(1) if m else None)), tags


def blocks(text):
    text = expand_object_macros(text)
    out = {}
    for m in re.finditer(r"ROM_START\(\s*(\w+)\s*\)(.*?)ROM_END", text, re.S):
        out[m.group(1)] = m.group(2)
    return out


def region_decl(body, want="maincpu"):
    """(declared size, fill byte) of one ROM_REGION, or None.

    The declared size is the region, not the extent of the loads: a set can
    leave a hole (buriki's scrtile has 8 MB unfilled at 0x1800000) or stop
    short, and MAME still presents the whole declared region. Anything not
    loaded is the erase value, which defaults to 0 (romload.cpp:1429).
    """
    for raw in body.split("\n"):
        line = pre_rewrite(raw.split("//")[0].strip())
        m = re.match(r'ROM_REGION\w*\(\s*(0x[0-9a-fA-F]+)\s*,\s*"([^"]+)"\s*,(.*)', line)
        if m and m.group(2) == want:
            flags = m.group(3)
            mf = re.search(r'ROMREGION_ERASEVAL\(\s*(0x[0-9a-fA-F]+|\d+)\s*\)', flags)
            if mf:
                fill = int(mf.group(1), 0)
            elif "ROMREGION_ERASEFF" in flags:
                fill = 0xFF
            else:
                fill = 0x00
            return int(m.group(1), 16), fill
    return None


def region_records(body, want="maincpu", bios=None):
    """Records for ONE named region, plus anything in it that did not parse.

    The region argument exists because the sprite and tile images need the same
    treatment the program ROM got: "gfx1" is loaded with the same four record
    kinds, and hand-transcribing it would reintroduce exactly the risk this
    script was written to remove.
    """
    records, unknown = [], []
    region = None
    want_bios, bios_tags = bios_choice(body, bios)
    for raw in body.split("\n"):
        line = pre_rewrite(raw.split("//")[0].strip())
        if not line:
            continue
        m = re.match(r'ROM_REGION\w*\(\s*(0x[0-9a-fA-F]+)\s*,\s*"([^"]+)"', line)
        if m:
            region = m.group(2)
            continue
        if region != want:
            continue
        # ROM_COPY has four numeric-ish arguments and a region name in the
        # first slot, so it matches the same shape with a different meaning:
        # (src region, src offset, dest offset, length).
        mc = re.match(r'ROM_COPY\(\s*"([^"]+)"\s*,\s*(0x[0-9a-fA-F]+)\s*,'
                      r'\s*(0x[0-9a-fA-F]+)\s*,\s*(0x[0-9a-fA-F]+)', line)
        if mc:
            records.append(("copy", mc.group(1), int(mc.group(3), 16),
                            int(mc.group(4), 16), None,
                            int(mc.group(2), 16)))
            continue

        # Some drivers write `ROM_LOAD24_BYTE     ( "x.u65", ...` with space
        # around the paren; a record that does not parse lands in `unknown`.
        m = re.match(r'(\w+)\s*\(\s*"([^"]+)"\s*,\s*(0x[0-9a-fA-F]+)\s*,'
                     r'\s*(0x[0-9a-fA-F]+)(.*)', line)
        if m and m.group(1) in KINDS:
            # The CRC is what actually identifies a dump. In a MERGED romset a
            # ROM is stored ONCE and found by hash, so the filename is not a
            # reliable key.
            crc = re.search(r'CRC\((\w+)\)', m.group(5))
            records.append((KINDS[m.group(1)], m.group(2),
                            int(m.group(3), 16), int(m.group(4), 16),
                            int(crc.group(1), 16) if crc else None))
            continue
        # The general form. ROM_BIOS(n) records belong to one system BIOS;
        # only the selected one is kept, so an image is never a mixture.
        m = re.match(r'ROMX_LOAD\s*\(\s*"([^"]+)"\s*,\s*(0x[0-9a-fA-F]+)\s*,'
                     r'\s*(0x[0-9a-fA-F]+)(.*)', line)
        if m:
            flags = m.group(4)
            mb = re.search(r'ROM_BIOS\(\s*(\d+)\s*\)', flags)
            if mb and bios_tags.get(int(mb.group(1))) != want_bios:
                continue
            g, skip, rev = romx_geometry(flags)
            crc = re.search(r'CRC\((\w+)\)', flags)
            records.append((f"group:{g}:{skip}:{rev}", m.group(1),
                            int(m.group(2), 16), int(m.group(3), 16),
                            int(crc.group(1), 16) if crc else None))
            continue
        m = re.match(r'ROM_CONTINUE\s*\(\s*(0x[0-9a-fA-F]+)\s*,'
                     r'\s*(0x[0-9a-fA-F]+)', line)
        if m:
            records.append(("continue", None,
                            int(m.group(1), 16), int(m.group(2), 16), None))
            continue
        # ROM_RELOAD(dest, length): the previous file again, from its start
        m = re.match(r'ROM_RELOAD\s*\(\s*(0x[0-9a-fA-F]+)\s*,'
                     r'\s*(0x[0-9a-fA-F]+)', line)
        if m:
            records.append(("reload", None,
                            int(m.group(1), 16), int(m.group(2), 16), None))
            continue
        if line.startswith(("ROM_LOAD", "ROM_CONTINUE", "ROMX_LOAD", "ROM_FILL",
                            "ROM_RELOAD", "ROM_IGNORE", "ROM_COPY")):
            unknown.append(line)
    return records, unknown


def maincpu_records(body):
    """The original entry point, kept because callers import it by name."""
    return region_records(body, "maincpu")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("sets", nargs="*", help="default: every in-scope set")
    ap.add_argument("--region", default="maincpu",
                    help="ROM_REGION to extract (maincpu, gfx1, ...)")
    ap.add_argument("--emit", action="store_true",
                    help="print a Python SETS table ready to paste")
    ap.add_argument("--driver", help="the MAME driver .cpp (default: MAME_SRC)")
    a = ap.parse_args()

    src = a.driver or SRC
    if not src or not os.path.exists(src):
        sys.exit(f"driver not found at {src!r} (set MAME_SRC or pass --driver)")
    all_blocks = blocks(open(src, encoding="utf8", errors="replace").read())
    wanted = a.sets or IN_SCOPE
    if not wanted:
        sys.exit("name the sets, or fill IN_SCOPE")

    problems = []
    table = {}
    for s in wanted:
        if s not in all_blocks:
            problems.append(f"{s}: no ROM_START in the driver")
            continue
        recs, unknown = region_records(all_blocks[s], a.region)
        if unknown:
            problems.append(f"{s}: {len(unknown)} unrecognised line(s): {unknown[:2]}")
        if not recs:
            problems.append(f"{s}: no {a.region} records found")
            continue
        table[s] = recs

    if a.emit:
        print("SETS = {")
        for s, recs in table.items():
            print(f'    "{s}": [')
            for kind, name, dest, ln, crc, *_ in recs:
                nm = "None" if name is None else f'"{name}"'
                cs = "None" if crc is None else f"{crc:#010x}"
                print(f'        ("{kind}", {nm:38s}, {dest:#08x}, {ln:#07x}, {cs}),')
            print("    ],")
        print("}")
    else:
        for s, recs in table.items():
            print(f"{s}:")
            for r in recs:
                print(f"    {r}")
    for p in problems:
        print("PROBLEM: " + p, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
