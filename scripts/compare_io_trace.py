#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The hardware's first I/O requests (ISSP instance T) against MAME's system trace.

    python scripts/read_issp.py T dump > debug/hw/hw_io_first.txt      # the core on the MiSTer
    python scripts/compare_io_trace.py sams64 debug/hw/hw_io_first.txt
    python scripts/compare_io_trace.py sams64 debug/hw/hw_io.txt --fetch   # read in chunks, stop at a split

T records each request as the CPU port gives it: the data word in the CPU's layout and a mask
bit per byte of it. MAME's trace is at its handler's granularity, big-endian with a 32-bit mask.
Both are turned into (read/write, word address, mask, data under the mask) and compared in order;
the first difference and its context are printed. Reads' data differ legitimately where the
hardware is not MAME (timers, the MCU's mailbox), so a read's data is shown but not a stop.
"""
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent


def io(a):
    return not (a < 0x01000000 or 0x04000000 <= a < 0x06000000 or 0x1FC00000 <= a < 0x1FC80000)


def logged_read(a):
    """The reads the system trace records (scripts/mame/systrace.lua): the I/O ranges only."""
    return 0x1F700000 <= a <= 0x1F8087FF or 0x60000000 <= a <= 0x6F000003 or 0xC0000000 <= a <= 0xC0001007


def mame(game, n):
    out = []
    after_clear = False
    for ln in open(REPO / "debug" / f"{game}-sys" / f"{game}_sys.trace"):
        if ln.startswith("#"):
            continue
        p = ln.rstrip("\n").split("\t")
        if len(p) < 5 or not io(int(p[2], 16)):
            continue
        m = int(p[3], 16)
        a = int(p[2], 16)
        # MAME's sprite clears write sprite RAM themselves (sprite_clear_even_w/_odd_w), and the
        # trace logs those writes; the CPU made only the clear's
        in_clear = 0x2000D800 <= a < 0x2000F000
        if p[1] == "w" and 0x20000000 <= a < 0x2000C000 and int(p[4], 16) == 0 and after_clear:
            continue
        after_clear = in_clear and p[1] == "w"
        out.append((p[1], a & ~3, m, int(p[4], 16) & m))
        if len(out) >= n:
            break
    return out


def hw_raw(path):
    """Each kept entry's raw data word as the CPU port gave it (index-aligned with hw())."""
    out = []
    for ln in open(path):
        w = ln.split()
        if len(w) < 6 or not w[0].isdigit():
            continue
        out.append(int(w[3], 16))
    return out


def read_value(raw, mask):
    """A read as the bridge returns it, right-justified and in the CPU's byte order
    (hng64_bus.sv justify), placed in MAME's lanes: the access's width and lanes are MAME's mask."""
    lanes = [k for k in range(4) if (mask >> (8 * (3 - k))) & 0xFF]
    n = len(lanes)
    vb = (raw & ((1 << (8 * n)) - 1)).to_bytes(n, "little")    # the value's bytes, address order
    v = 0
    for byte, lane in zip(vb, lanes):
        v |= byte << (8 * (3 - lane))
    return v


def mame_reg(path, n):
    """scripts/mame/regtrace.lua's log: every register access, reads included."""
    out = []
    for ln in open(path):
        w = ln.split()
        if len(w) < 4:
            continue
        m = int(w[3], 16)
        out.append((w[0], int(w[1], 16) & ~3, m, int(w[2], 16) & m))
        if len(out) >= n:
            break
    return out


def hw(path, all_reads=False):
    out = []
    for ln in open(path):
        w = ln.split()
        if len(w) < 6 or not w[0].isdigit():
            continue
        rw, a, d, raw = w[1], int(w[2], 16), int(w[3], 16), int(w[4], 16)
        d = int.from_bytes(d.to_bytes(4, "little"), "big")        # to MAME's big-endian word
        m = 0
        for k in range(4):
            if (raw >> k) & 1:
                m |= 0xFF << (8 * (3 - k))
        if rw == "r":
            if not all_reads and not logged_read(a):
                continue
            if not all_reads:
                m = 0xFFFFFFFF
        out.append((rw, a & ~3, m, d & m))
    return out


def fmt(e):
    return f"{e[0]} {e[1]:08X} mask {e[2]:08X} data {e[3]:08X}" if e else "-"


def fetch(path, chunk=512, total=4096):
    """Read T from the core a chunk at a time into `path`, comparing as it goes; stop at the
    sequences' split (each read_issp.py run costs several seconds of quartus_stp start-up)."""
    import subprocess
    with open(path, "w") as f:
        pass
    for k0 in range(0, total, chunk):
        out = subprocess.run([sys.executable, str(REPO / "scripts" / "read_issp.py"), "T", "dump",
                              "from", str(k0), "count", str(chunk)],
                             capture_output=True, text=True).stdout
        lines = [ln for ln in out.splitlines() if ln.strip()[:1].isdigit() and len(ln.split()) >= 6]
        with open(path, "a") as f:
            f.write(chr(10).join(lines) + chr(10))
        print(f"read {k0 + len(lines)} entries", flush=True)
        if len(lines) < chunk or compare(sys.argv[1], path, quiet=True):
            break


def main():
    if "--fetch" in sys.argv:
        sys.argv.remove("--fetch")
        fetch(sys.argv[2])
    return compare(sys.argv[1], sys.argv[2])


def compare(game, path, quiet=False):
    """Prints the comparison; returns True once the sequences have split. With --regtrace FILE
    (scripts/mame/regtrace.lua) the reference has every read, and reads' data are compared too."""
    reg = None
    if "--regtrace" in sys.argv:
        reg = sys.argv[sys.argv.index("--regtrace") + 1]
    h = hw(path, all_reads=reg is not None)
    raw_read = hw_raw(path) if reg else None
    m = mame_reg(reg, len(h) + 50) if reg else mame(game, len(h) + 50)
    data_diffs = 0
    for k in range(len(h)):
        a, b = h[k], m[k] if k < len(m) else None
        if b is None or a[0] != b[0] or a[1] != b[1]:
            if quiet:
                return True
            print(f"the sequences split at request {k} of {len(h)} ({data_diffs} data differences before):")
            for j in range(max(0, k - 8), min(len(h), k + 8)):
                mark = ">>" if j == k else "  "
                print(f"{mark} {j:5d}  hw   {fmt(h[j])}")
                print(f"         mame {fmt(m[j] if j < len(m) else None)}")
            return True
        if a[0] == "r" and reg:
            a = (a[0], a[1], b[2], read_value(raw_read[k], b[2]))
        if (a[0] == "w" or reg) and (a[2] != b[2] or a[3] != b[3]):
            data_diffs += 1
            if data_diffs <= 20 and not quiet:
                print(f"   {k:5d}  data: hw {fmt(a)}   mame {fmt(b)}")
    if not quiet:
        print(f"all {len(h)} requests agree in order and address; {data_diffs} writes differ in data or lanes")
    return False


if __name__ == "__main__":
    main()
