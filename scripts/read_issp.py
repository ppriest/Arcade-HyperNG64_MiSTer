#!/usr/bin/env python3
"""Read the core's ISSP probes over JTAG, holding the machine-wide hwlock.

    python scripts/read_issp.py                # decode the first instance
    python scripts/read_issp.py D              # decode instance D
    python scripts/read_issp.py C clear        # further args go to the Tcl
    python scripts/read_issp.py F set 8        # write source byte 8 and leave it
    python scripts/read_issp.py F pulse 2      # write 2, then 0

scripts/read_issp.tcl does the reading; run it through this. quartus_stp
started bare takes no marker, so a build or a simulation -- from this repo or
another core's -- could start underneath it, which is the combination
scripts/hwlock.py exists to prevent. scripts/probe.py is the one-line-per-read
form of the same thing.
"""
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from coretools import core_root, quartus_stp   # noqa: E402
from hwlock import jtag_session                # noqa: E402

REPO = core_root()
TCL = Path(__file__).resolve().parent / "read_issp.tcl"


def read(*args, capture=False):
    """Run read_issp.tcl under the lock; the CompletedProcess."""
    with jtag_session("read_issp " + " ".join(args)):
        return subprocess.run([str(quartus_stp(REPO)), "-t", str(TCL), *args],
                              cwd=REPO, capture_output=capture, text=True)


if __name__ == "__main__":
    sys.exit(read(*sys.argv[1:]).returncode)
