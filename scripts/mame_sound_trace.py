#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The sound interface from both CPUs' sides for the first N frames, from MAME.

    python scripts/mame_sound_trace.py <set> 3600
    -> debug/<set>-sound/<set>_sound.trace, <set>_sndram_<k>.bin, <set>.wav
       debug/rom/<set>-l7a1045.bin, when missing

What the ARM sound bridge has to carry, and the bench of its emulator: the mailbox, the sound CPU
enable, the main CPU's sound RAM traffic once the sound CPU runs, sound RAM at each enable, the
V53A's L7A1045 traffic, and MAME's output at 44.1 kHz. See scripts/mame/soundtrace.lua.
"""
import argparse
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO / "scripts"))
from mame_boot_trace import run_traced  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game")
    ap.add_argument("frames", type=int)
    ap.add_argument("--seconds", type=int, default=600, help="MAME -seconds_to_run backstop")
    a = ap.parse_args()
    out = REPO / "debug" / f"{a.game}-sound"
    samples = REPO / "debug" / "rom" / f"{a.game}-l7a1045.bin"
    env = {"CORE_FRAMES": str(a.frames),
           "CORE_SAMPLES": "" if samples.exists() else samples.as_posix()}
    wav = out / f"{a.game}.wav"
    r = run_traced(a.game, "soundtrace.lua", out, env, a.seconds,
                   ["-wavwrite", str(wav), "-samplerate", "44100"])
    trace = out / f"{a.game}_sound.trace"
    if not trace.exists():
        sys.stdout.write(r.stdout[-2000:])
        sys.stderr.write(r.stderr[-2000:])
        sys.exit("no trace written; see MAME output above")
    if any(ln.startswith("# FIRST ERROR") for ln in trace.read_text().splitlines()):
        sys.exit(f"{trace}: a tap recorded an error")
    print(f"-> {trace}")
    print(f"-> {wav}" if wav.exists() else "no WAV written")
    return 0


if __name__ == "__main__":
    sys.exit(main())
