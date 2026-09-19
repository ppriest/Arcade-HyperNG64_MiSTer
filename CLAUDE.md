# HyperNG64

MiSTer arcade core for HyperNG64. Built with the `mister-arcade-core` skill.

## Before working

- `docs/ROADMAP.md` is the status and plan. No phase starts until the user approves it.
- Read the routing table at the top of `docs/LESSONS_LEARNED.md` before starting a
  subsystem.
- `docs/WORKFLOW.md` is binding.

## Rules

- Never touch `sys/`.
- Build with `python scripts/build_staged.py`, never in the tree. Commit first; it
  refuses a dirty tree.
- No JTAG while Quartus runs, and the reverse. Use `scripts/read_issp.py` and
  `scripts/probe.py`, which take `hwlock.py`.
- Deploy only with `scripts/deploy.py`. Launch and screenshot with `scripts/hw.py`,
  `--native` for pixel comparison.
- MAME is the reference. Follow it where it is wrong and log it in `docs/MAME_KLUDGES.md`.
- Anything approximate, stubbed or special-cased goes in `docs/HACKS.md` when written.
- Every subsystem gets a testbench fed from a MAME capture before it goes on hardware.
- Run the video-write sweep before choosing any sprite or tile buffering scheme.
- The standard feature set (README "Features") is part of done, not polish. Flip screen is one
  path from the OSD or the DIP, verified against the unflipped frame rotated 180 degrees, not
  against MAME alone. The OSD shows only what applies to the running set and output.
  Controls always include a Pause input that suspends the main CPU. Savestates and cheats
  are optional.
- Debug switches live on the OSD's hidden page, and probes in the `HyperNG64_stp` revision
  only.
- No multiplies or divides in 2D video or CPU glue: shifts, masks, adds, accumulators
  (WORKFLOW §14). GPU-like chips (3D geometry, rasterisers) use them by design.

## Style

- Comments say what the code cannot. Delete or rewrite them when they go stale.
- No dates unless load-bearing, no invented durations, no narrative.
- A hardware claim cites its evidence: screenshot path, probe readout, log line.
- New general lessons go in `docs/LESSONS_LEARNED.md` tagged `[HyperNG64]`.
