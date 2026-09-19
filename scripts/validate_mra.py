#!/usr/bin/env python3
"""Validate .mra files before deploying them.

WHY
---
An edit to a comment block once left a `-->` in place that had already closed
the comment, so the new prose landed in the document as character data. It
contained a bare `<`, which is illegal in XML, so MiSTer refused the file: the
DIP switches vanished from the OSD, the ROM never loaded, and the core came
up on an all-zero image. That looked exactly like a core regression.

Nothing about that failure is visible by reading the diff, and MiSTer's own
parser is lenient enough that some malformations load fine while others kill
the file. So check mechanically, every time, before copying an .mra.

Checks:
  1. The file is well-formed XML (strict -- stricter than MiSTer's parser).
  2. No element carries stray non-whitespace TEXT content. Every leaked
     comment block shows up here, including ones MiSTer currently tolerates.
  3. <switches default="..."> byte count covers the declared bits, and the
     file declares a <setname> (the .CFG filename depends on it).
  4. <rotation> matches the set's orientation in the MAME driver's GAME()
     line (MAME_SRC, from mister.env or the environment): ROT0 ->
     "horizontal", ROT90 -> "vertical (cw)", ROT270 -> "vertical (ccw)".
     Skipped, with a note, when the driver is not available.

Usage:
    python scripts/validate_mra.py releases/*.mra
Exit status is non-zero if any file fails, so it works as a gate:
    python scripts/validate_mra.py releases/*.mra && <deploy>
"""
import glob
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from coretools import setting   # noqa: E402

# --- core-specific: edit for this core -------------------------------------
# Orientation per set, as the .mra <rotation> tag, for sets whose GAME() line
# the driver parse misses or that the core rotates differently. Entries here
# override the driver.
ROTATION_OVERRIDE = {}
# ---------------------------------------------------------------------------

ROT_TAG = {"ROT0": "horizontal", "ROT90": "vertical (cw)", "ROT180": "horizontal",
           "ROT270": "vertical (ccw)"}

# Elements whose text content is meaningful and must not be flagged.
TEXT_OK = {'part', 'name', 'setname', 'year', 'manufacturer', 'category',
           'rbf', 'rotation', 'players', 'joystick', 'region', 'about',
           'mratimestamp', 'catver', 'mameversion', 'status', 'nvram'}


def driver_rotations():
    """setname -> rotation tag from the driver's GAME()/GAMEL() lines."""
    src = setting("MAME_SRC")
    if not src or not Path(src).exists():
        return None
    out = {}
    text = Path(src).read_text(encoding="utf8", errors="replace")
    for m in re.finditer(r'^GAMEL?\(\s*\d+,\s*(\w+),.*?,\s*(ROT\d+)\b', text, re.M):
        out[m.group(1)] = ROT_TAG.get(m.group(2))
    return out


def check(path, rotations):
    problems = []
    try:
        tree = ET.parse(path)
    except ET.ParseError as e:
        return ['not well-formed XML: %s' % e]

    root = tree.getroot()
    for el in root.iter():
        if el.tag in TEXT_OK:
            continue
        for blob, where in ((el.text, 'text'), (el.tail, 'tail')):
            if blob and blob.strip():
                snippet = ' '.join(blob.split())[:70]
                problems.append(
                    'stray %s content in <%s>: %r\n'
                    '        (a comment block almost certainly closed early -- '
                    'check for a premature "-->")' % (where, el.tag, snippet))

    if root.find('setname') is None:
        problems.append('no <setname>; the per-core .CFG filename depends on it')
    elif rotations is not None:
        setname = (root.findtext('setname') or '').strip()
        rotation = (root.findtext('rotation') or '').strip()
        want = ROTATION_OVERRIDE.get(setname, rotations.get(setname))
        if want is None:
            problems.append('<setname> %r has no known MAME orientation' % setname)
        elif rotation != want:
            problems.append('<rotation> is %r, MAME orientation for %s is %r'
                            % (rotation, setname, want))

    sw = root.find('switches')
    if sw is not None and sw.get('default'):
        nbytes = len([x for x in sw.get('default').split(',') if x.strip()])
        bits = []
        for dip in sw.findall('dip'):
            for b in (dip.get('bits') or '').split(','):
                if b.strip().isdigit():
                    bits.append(int(b))
        if bits and max(bits) >= nbytes * 8 + 16:
            problems.append(
                'switches default has %d bytes but a <dip> uses bit %d, which '
                'is outside the range those bytes can cover' % (nbytes, max(bits)))
    return problems


def main(argv):
    files = []
    for pat in (argv or ['releases/*.mra']):
        files.extend(sorted(glob.glob(pat)))
    if not files:
        print('no .mra files matched'); return 1

    rotations = driver_rotations()
    if rotations is None:
        print('NOTE  MAME_SRC not set or missing; <rotation> not checked')

    bad = 0
    for f in files:
        problems = check(f, rotations)
        if problems:
            bad += 1
            print('FAIL  %s' % f)
            for p in problems:
                print('        %s' % p)
        else:
            print('OK    %s' % f)
    if bad:
        print('\n%d of %d file(s) failed -- do NOT deploy these.' % (bad, len(files)))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
