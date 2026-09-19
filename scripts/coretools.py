#!/usr/bin/env python3
"""What every script in this directory needs to know about its core.

The core root is the parent of this scripts/ directory (or CORE_ROOT). From it:

    project()    the Quartus project name: the stem of the one .qpf there
                 (Fuuki.qpf -> "Fuuki"). Names the MiSTer artefacts too:
                 Arcade-<project>_NNNNNNNN.rbf, /media/fat/_Arcade/_<project>.
    revision()   the Quartus revision to build: CORE_REV, else the one .qsf,
                 else the last PROJECT_REVISION the .qpf lists. A core with
                 several revisions (X and X_stp) picks with CORE_REV or --rev.
    load_env()   <core>/mister.env, the gitignored per-machine file with the
                 MiSTer connection settings and tool locations.

Tool locations, in order: the environment, mister.env, then a default.

    QUARTUS_BIN    .../intelFPGA_lite/17.0/quartus/bin64
    MODELSIM_BIN   defaults to <quartus root>/modelsim_ase/win32aloem
    MAME_DIR       directory holding the MAME executable (required to use MAME)
    MAME_EXE       executable name inside it (default mame.exe)
    MAME_SRC       the MAME driver source this core follows (extract_dips.py,
                   extract_romstart.py, validate_mra.py)

`python scripts/coretools.py` prints what it resolved.
"""
import os
import subprocess
import sys
from pathlib import Path

QUARTUS_DEFAULT = r"C:\intelFPGA_lite\17.0\quartus\bin64"

# NO CONSOLE WINDOW for a spawned mame.exe: from a process with no console of
# its own Windows gives it a visible one, even with -video none -nowindow.
NO_WINDOW = {"creationflags": subprocess.CREATE_NO_WINDOW} if os.name == "nt" else {}


def core_root():
    """The core being worked on: CORE_ROOT, else the parent of scripts/."""
    root = Path(os.environ.get("CORE_ROOT") or Path(__file__).resolve().parent.parent)
    if not list(root.glob("*.qpf")):
        sys.exit("not a core root (no .qpf here): %s" % root)
    return root


def project(root=None):
    """The Quartus project name: the stem of the .qpf in the root.

    A core with X.qpf and X_stp.qpf has two; the shorter stem is the project."""
    root = root or core_root()
    qpfs = sorted(root.glob("*.qpf"), key=lambda p: len(p.stem))
    if not qpfs:
        sys.exit("no .qpf in %s" % root)
    return qpfs[0].stem


def revision(root=None, override=None):
    """The Quartus revision to build/report on."""
    root = root or core_root()
    if override:
        return override
    if os.environ.get("CORE_REV"):
        return os.environ["CORE_REV"]
    qsfs = sorted(root.glob("*.qsf"))
    if len(qsfs) == 1:
        return qsfs[0].stem
    # several revisions: the .qpf lists them, last one current
    revs = []
    for qpf in sorted(root.glob("*.qpf")):
        for ln in qpf.read_text(errors="replace").splitlines():
            if ln.startswith("PROJECT_REVISION"):
                revs.append(ln.split("=", 1)[1].strip().strip('"'))
    if revs:
        return revs[-1]
    sys.exit("cannot determine the revision in %s: %d .qsf files and no "
             "PROJECT_REVISION in the .qpf; set CORE_REV or pass --rev"
             % (root, len(qsfs)))


def load_env(root=None, path=None, require=()):
    """KEY=VALUE pairs from <core>/mister.env (comments and blanks skipped)."""
    path = Path(path or ((root or core_root()) / "mister.env"))
    env = {}
    if path.exists():
        for ln in path.read_text(encoding="utf-8", errors="replace").splitlines():
            ln = ln.strip()
            if not ln or ln.startswith("#") or "=" not in ln:
                continue
            k, v = ln.split("=", 1)
            env[k.strip()] = v.strip().strip('"').strip("'")
    elif require:
        sys.exit("%s not found. Create it with %s (it is gitignored)."
                 % (path, ", ".join(require)))
    for k in require:
        if not env.get(k):
            sys.exit("%s does not set %s" % (path.name, k))
    return env


def setting(name, default=None, root=None):
    """A tool setting: environment, then mister.env, then the default."""
    if os.environ.get(name):
        return os.environ[name]
    v = load_env(root).get(name)
    return v if v else default


def quartus_bin(root=None):
    return Path(setting("QUARTUS_BIN", QUARTUS_DEFAULT, root))


def quartus_stp(root=None):
    return quartus_bin(root) / "quartus_stp.exe"


def modelsim_bin(root=None):
    v = setting("MODELSIM_BIN", None, root)
    if v:
        return Path(v)
    return quartus_bin(root).parent.parent / "modelsim_ase" / "win32aloem"


def mame_dir(root=None):
    v = setting("MAME_DIR", None, root)
    if not v:
        sys.exit("MAME_DIR is not set: put MAME_DIR=<directory of the MAME "
                 "executable> (and MAME_EXE=<name>, if not mame.exe) in the "
                 "core's mister.env, or export it")
    return Path(v)


def mame_exe(root=None):
    return mame_dir(root) / setting("MAME_EXE", "mame.exe", root)


def mame_src(root=None):
    v = setting("MAME_SRC", None, root)
    if not v:
        sys.exit("MAME_SRC is not set: put MAME_SRC=<path to the MAME driver "
                 ".cpp this core follows> in the core's mister.env, or export it")
    return Path(v)


def rompath(root=None):
    """This core's gitignored roms/ FIRST, then whatever mame.ini already had.

    -rompath REPLACES the ini value rather than adding to it, so the ini's own
    entries are read and appended."""
    root = root or core_root()
    md = mame_dir(root)
    paths = [str(root / "roms")]
    ini = md / "mame.ini"
    if ini.exists():
        for line in ini.read_text(errors="replace").splitlines():
            if line.strip().startswith("rompath"):
                for part in line.split(None, 1)[1].split(";"):
                    part = part.strip()
                    if part:
                        q = Path(part)
                        paths.append(str(q if q.is_absolute() else md / q))
                break
    seen, out = set(), []
    for q in paths:
        if q not in seen:
            seen.add(q)
            out.append(q)
    return ";".join(out)


def find_putty(name):
    """plink.exe / pscp.exe: PATH, then the standard install."""
    import shutil
    for c in (name, os.path.join(r"C:\Program Files\PuTTY", name)):
        found = shutil.which(c) or (c if os.path.isfile(c) else None)
        if found:
            return found
    sys.exit("Couldn't find %s. Install PuTTY, or put it on PATH." % name)


if __name__ == "__main__":
    r = core_root()
    print("core root : %s" % r)
    print("project   : %s" % project(r))
    print("revision  : %s" % revision(r))
    print("quartus   : %s" % quartus_bin(r))
    print("modelsim  : %s" % modelsim_bin(r))
    print("mame      : %s" % setting("MAME_DIR", "(not set)", r))
    print("mame src  : %s" % setting("MAME_SRC", "(not set)", r))
