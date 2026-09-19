#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Capture machine state from MAME at a chosen frame.

    python scripts/mame_capture.py <set> --frame 1200 --name title

Writes debug/<set>-<name>/: one .bin per `read` region of scripts/mame/regions.json,
one reg_<name>.bin per `wtap` region (rebuilt from writes), MAME's screenshot and a
manifest. See scripts/mame/capture.lua for how each is obtained.

The dumps are the strong reference: they are what the game wrote, and the RTL must
hold the same bytes. reference.png is MAME's rendering; where the driver is
MACHINE_IMPERFECT_GRAPHICS a pixel difference is a question, not a verdict, and is
settled in docs/MAME_KLUDGES.md.

Also the shared loader for regions.json and the MAME command line (write_timing.py).
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LUA_DIR = REPO / "scripts" / "mame"
NO_WINDOW = {"creationflags": 0x08000000} if os.name == "nt" else {}


def load_env(path=REPO / "mister.env"):
    env = {}
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip()
    return env


def mame_paths():
    env = load_env()
    mame_dir = Path(os.environ.get("MAME_DIR", env.get("MAME_DIR", "")))
    exe = mame_dir / os.environ.get("MAME_EXE", env.get("MAME_EXE", "mame.exe"))
    if not exe.exists():
        sys.exit(f"MAME not found at {exe}; set MAME_DIR/MAME_EXE in mister.env")
    return mame_dir, exe


def regions():
    return json.loads((LUA_DIR / "regions.json").read_text(encoding="utf-8"))


def spec(table, names=None):
    """{"name": [lo, hi]} -> "name:lo:hi,..." for the Lua side."""
    return ",".join(f"{n}:{int(lo, 16):x}:{int(hi, 16):x}"
                    for n, (lo, hi) in table.items() if names is None or n in names)


def lua_env(r):
    return {"CORE_CPU": r["cpu"], "CORE_SPACE": r["space"],
            "CORE_BYTES": str(r["bus_bytes"]), "CORE_BIG": "1" if r["big_endian"] else "0"}


def mame_cmd(exe, game, lua, mame_dir, extra=()):
    # -nodebug/-nowindow explicit: a mame.ini with `debug 1` halts in the debugger
    # while the autoboot script still loads and prints, so it looks alive.
    return [str(exe), game, "-nodebug", "-nowindow", "-video", "none", "-sound", "none",
            "-skip_gameinfo", "-nothrottle", "-autoboot_delay", "0",
            "-autoboot_script", str(LUA_DIR / lua),
            "-rompath", rompath(mame_dir), *extra]


def rompath(mame_dir):
    """roms/ in the repo, MAME's own roms/, then MAME_ROMPATH (mister.env or environment)."""
    extra = os.environ.get("MAME_ROMPATH", load_env().get("MAME_ROMPATH", ""))
    return ";".join(p for p in [str(REPO / "roms"), str(mame_dir / "roms"), extra] if p)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("set", help="MAME set name")
    ap.add_argument("--frame", type=int, default=1200)
    ap.add_argument("--name", default=None, help="output label (default: the frame)")
    ap.add_argument("--seconds", type=int, default=None,
                    help="emulated seconds to run; default frame/60 + 10")
    ap.add_argument("--out", default=None)
    ap.add_argument("--keep-going", action="store_true",
                    help="do not delete a previous capture of the same name")
    a = ap.parse_args()

    mame_dir, exe = mame_paths()
    r = regions()
    out = Path(a.out) if a.out else REPO / "debug" / f"{a.set}-{a.name or a.frame}"
    if out.exists() and not a.keep_going:
        shutil.rmtree(out)
    out.mkdir(parents=True, exist_ok=True)
    seconds = a.seconds if a.seconds is not None else max(10, a.frame // 60 + 10)

    cmd = mame_cmd(exe, a.set, "capture.lua", mame_dir, ["-seconds_to_run", str(seconds)])
    env = dict(os.environ, **lua_env(r), CORE_OUT=out.as_posix(), CORE_FRAME=str(a.frame),
               CORE_READ=spec(r.get("read", {})), CORE_WTAP=spec(r.get("wtap", {})))
    print(f"{a.set} frame {a.frame} -> {out}")
    p = subprocess.run(cmd, cwd=mame_dir, env=env, capture_output=True, text=True, **NO_WINDOW)
    blob = p.stdout + p.stderr
    if (out / "ERROR.txt").exists():
        sys.exit(f"capture.lua failed:\n{(out / 'ERROR.txt').read_text(encoding='utf-8')}")
    if "CORE_CAPTURE_OK" not in blob:
        tail = "\n".join(blob.strip().splitlines()[-15:])
        sys.exit(f"capture did not complete (no CORE_CAPTURE_OK).\n{tail}")
    print((out / "manifest.txt").read_text(encoding="utf-8").strip())
    print(f"{len(list(out.glob('*.bin')))} dumps + reference.png in {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
