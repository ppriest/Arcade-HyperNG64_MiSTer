#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""The sound board bench on the MiSTer's ARM: how fast the emulator runs there.

    python scripts/snd_arm_bench.py fatfurwa

Builds sw/hng64snd's bench for armhf (WSL's arm-linux-gnueabihf-g++, static), copies it and the
set's capture (scripts/mame_sound_trace.py) to /tmp/hng64snd on the board, runs it and prints its
report; "emulated X s in Y s" is the figure that matters. Leaves /tmp/hng64snd in place.
"""
import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from coretools import load_env  # noqa: E402
from hw import Mister, REPO  # noqa: E402

SRC = ["nec_core.cpp", "v53.cpp", "l7a1045.cpp", "board.cpp", "bench.cpp"]
OUT = REPO / "obj_hng64snd" / "hng64snd_bench_arm"
REMOTE = "/tmp/hng64snd"


def wsl_path(p):
    p = Path(p).resolve()
    return f"/mnt/{p.drive[0].lower()}{p.as_posix()[2:]}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game")
    ap.add_argument("--div", type=int, default=1, help="V33 clock as 32 MHz over this")
    ap.add_argument("--opt", default="-O2", help="optimisation flags")
    a = ap.parse_args()

    OUT.parent.mkdir(exist_ok=True)
    src = " ".join(SRC)
    cmd = (f"cd {wsl_path(REPO / 'sw' / 'hng64snd')} && arm-linux-gnueabihf-g++ -std=c++17 {a.opt} "
           f"-mcpu=cortex-a9 -mfpu=neon -mfloat-abi=hard -static -Wall -Wno-sign-compare -I. "
           f"-o {wsl_path(OUT)} {src}")
    r = subprocess.run(["wsl.exe", "-e", "bash", "-lc", cmd], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"cross-compile failed:\n{r.stdout}{r.stderr}")

    cap = REPO / "debug" / f"{a.game}-sound"
    files = [OUT, cap / f"{a.game}_sound.trace", cap / f"{a.game}_sndram_0.bin",
             REPO / "debug" / "rom" / f"{a.game}-l7a1045.bin"]
    for f in files:
        if not f.exists():
            sys.exit(f"missing {f}; run scripts/mame_sound_trace.py {a.game} first")

    m = Mister(load_env())
    m.sh(f"mkdir -p {REMOTE}")
    have = {}
    for ln in m.sh(f"cd {REMOTE} && stat -c '%n %s' * 2>/dev/null", check=False).splitlines():
        name, _, size = ln.rpartition(" ")
        have[name] = int(size) if size.isdigit() else -1
    for f in files:
        if f != OUT and have.get(f.name) == f.stat().st_size:
            continue
        p = subprocess.run([m.pscp, "-batch", "-pw", m.pw, str(f),
                            f"{m.user}@{m.host}:{REMOTE}/{f.name}"],
                           capture_output=True, text=True, timeout=600)
        if p.returncode != 0:
            sys.exit(f"upload failed: {f}\n{p.stderr.strip()}")
    out = m.sh(f"cd {REMOTE} && chmod +x {OUT.name} && BENCH_CPU_DIV={a.div} BENCH_PROGRESS=1 ./{OUT.name} {a.game}_sound.trace "
               f"{a.game}_sndram_0.bin {a.game}-l7a1045.bin {a.game}_arm.wav; "
               f"cat /proc/cpuinfo | grep -m1 -i 'model name\\|BogoMIPS'",
               timeout=1200, check=False)
    print(out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
