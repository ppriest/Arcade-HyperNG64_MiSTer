#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build the sound process (sw/hng64snd) for the MiSTer and install it.

    python scripts/snd_deploy.py [--no-pgo | --reuse-pgo] [--package] [--no-install]

Cross-compiles with WSL's arm-linux-gnueabihf-g++ (static). With profile feedback, the default,
it first builds the bench instrumented, runs it on the board at 16 MHz on the fatfurwa capture
(scripts/mame_sound_trace.py fatfurwa 1200; scripts/snd_arm_bench.py uploads it), and builds the
process from that profile: 11% faster there (docs/ROADMAP.md Phase 4).

Installs /media/fat/games/HyperNG64/hng64snd; Scripts/HNG64_SoundServer.sh, which starts it in the
background from the Scripts menu (nothing starts it at boot); and, per set, games/<set>/_handler.sh,
which MiSTer Frontier's Master_Daemon.sh runs while that set is loaded (/tmp/CORENAME is the .mra's
setname). --package also writes releases/hng64snd_<YYYYMMDD>.zip, the binary and the script where
they go under /media/fat, to unzip there (docs/RELEASE_PROCESS.md); --no-install leaves the board
alone.
"""
import argparse
import shutil
import time
import zipfile
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from coretools import load_env  # noqa: E402
from hw import Mister, REPO  # noqa: E402
from snd_arm_bench import wsl_path  # noqa: E402

SRC = REPO / "sw" / "hng64snd"
OBJ = REPO / "obj_hng64snd" / "arm"
CORE = ["nec_core", "v53", "l7a1045", "board"]
FLAGS = "-std=c++17 -O3 -marm -mcpu=cortex-a9 -mfpu=neon -mfloat-abi=hard -Wall -Wno-sign-compare -I."
SETS = ["sams64", "sams64_2", "fatfurwa", "buriki"]
REMOTE_DIR = "/media/fat/games/HyperNG64"
TRAIN = "/tmp/hng64snd"                  # where snd_arm_bench.py leaves the capture

HANDLER = """#!/bin/sh
# HyperNG64 sound: the V53A and L7A1045 on the ARM (sw/hng64snd). MiSTer Frontier's
# Master_Daemon.sh runs this while the set is loaded and kills it when the core changes.
cd {dir} || exit 1
chmod +x hng64snd
exec ./hng64snd -v 2>/tmp/hng64snd.log
"""


def wsl(cmds):
    r = subprocess.run(["wsl.exe", "-e", "bash", "-lc", " && ".join(cmds)], capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit(f"build failed:\n{r.stdout}{r.stderr}")


def build(extra, objs, main, out):
    cmds = [f"cd {wsl_path(SRC)}"]
    for s in objs + [main]:
        cmds.append(f"arm-linux-gnueabihf-g++ {FLAGS} {extra} -c {s}.cpp -o {wsl_path(OBJ)}/{s}.o")
    cmds.append(f"arm-linux-gnueabihf-g++ {FLAGS} {extra} -static -o {wsl_path(out)} " +
                " ".join(f"{wsl_path(OBJ)}/{s}.o" for s in objs + [main]))
    wsl(cmds)


def put(m, local, remote):
    p = subprocess.run([m.pscp, "-batch", "-pw", m.pw, str(local), f"{m.user}@{m.host}:{remote}"],
                       capture_output=True, text=True, timeout=600)
    if p.returncode != 0:
        sys.exit(f"upload failed: {local}\n{p.stderr.strip()}")


START = SRC / "HNG64_SoundServer.sh"
REMOTE_START = "/media/fat/Scripts/HNG64_SoundServer.sh"


def start_script():
    """the start script with LF line ends, whatever the checkout gave it"""
    return START.read_bytes().replace(b"\r\n", b"\n")


def package(binary):
    """releases/hng64snd_<YYYYMMDD>.zip: the binary and the start script where they go under
    /media/fat, executable"""
    out = REPO / "releases" / f"hng64snd_{time.strftime('%Y%m%d')}.zip"
    with zipfile.ZipFile(out, "w") as z:
        for path, data in ((REMOTE_DIR + "/hng64snd", binary.read_bytes()), (REMOTE_START, start_script())):
            zi = zipfile.ZipInfo(path.removeprefix("/media/fat/"), time.localtime()[:6])
            zi.create_system = 3                # Unix, so the mode below is kept
            zi.external_attr = 0o100755 << 16
            zi.compress_type = zipfile.ZIP_DEFLATED
            z.writestr(zi, data)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-pgo", action="store_true")
    ap.add_argument("--reuse-pgo", action="store_true",
                    help="the profile in obj_hng64snd/pgo from the last run; nothing run on the board")
    ap.add_argument("--package", action="store_true", help="write releases/hng64snd_<YYYYMMDD>.zip")
    ap.add_argument("--no-install", action="store_true", help="build (and package) only")
    a = ap.parse_args()
    OBJ.mkdir(parents=True, exist_ok=True)
    m = Mister(load_env())
    profile = ""
    gcda = REPO / "obj_hng64snd" / "pgo"
    if a.reuse_pgo:
        if not gcda.exists():
            sys.exit(f"no profile in {gcda}")
        profile = f"-fprofile-use={wsl_path(gcda)} -fprofile-correction -Wno-missing-profile"
    elif not a.no_pgo:
        if "fatfurwa_sound.trace" not in m.sh(f"ls {TRAIN} 2>/dev/null", check=False):
            sys.exit(f"no capture in {TRAIN}: run scripts/snd_arm_bench.py fatfurwa first")
        build(f"-fprofile-generate={TRAIN}/pgo -fprofile-update=single", CORE, "bench", OBJ / "bench_gen")
        put(m, OBJ / "bench_gen", f"{TRAIN}/bench_gen")
        print(m.sh(f"cd {TRAIN} && rm -rf pgo && chmod +x bench_gen && BENCH_CPU_DIV=2 ./bench_gen "
                   "fatfurwa_sound.trace fatfurwa_sndram_0.bin fatfurwa-l7a1045.bin x.wav | grep emulated",
                   timeout=1800, check=False).strip())
        if gcda.exists():
            shutil.rmtree(gcda)
        for n in m.sh(f"cd {TRAIN}/pgo && find . -name '*.gcda'", check=False).split():
            dst = gcda / n[2:]
            dst.parent.mkdir(parents=True, exist_ok=True)
            m.get_file(f"{TRAIN}/pgo/{n[2:]}", dst)
        profile = f"-fprofile-use={wsl_path(gcda)} -fprofile-correction -Wno-missing-profile"
    build(profile, CORE, "mister", OBJ / "hng64snd")
    if a.package:
        print(f"-> {package(OBJ / 'hng64snd')}{'' if profile else ' (no profile feedback)'}")
    if a.no_install:
        return 0

    m.sh(f"mkdir -p {REMOTE_DIR}")
    # every copy, whatever its file's name (BusyBox's pkill -x matches none, pidof only the exact one)
    m.sh("for p in $(ps | grep '[h]ng64snd' | awk '{print $1}'); do kill $p; done; sleep 1; true", check=False)
    put(m, OBJ / "hng64snd", f"{REMOTE_DIR}/hng64snd")
    m.sh(f"chmod +x {REMOTE_DIR}/hng64snd")
    start = OBJ / START.name
    start.write_bytes(start_script())
    m.sh(f"mkdir -p {Path(REMOTE_START).parent.as_posix()}")
    put(m, start, REMOTE_START)
    m.sh(f"chmod +x {REMOTE_START}")
    for s in SETS:
        h = OBJ / f"_handler_{s}.sh"
        h.write_bytes(HANDLER.format(dir=REMOTE_DIR).encode())
        m.sh(f"mkdir -p /media/fat/games/{s}")
        put(m, h, f"/media/fat/games/{s}/_handler.sh")
        m.sh(f"chmod +x /media/fat/games/{s}/_handler.sh")
    print(f"-> {REMOTE_DIR}/hng64snd, {REMOTE_START}, handlers for {', '.join(SETS)}"
          f"{'' if profile else ' (no profile feedback)'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
