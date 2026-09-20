# Hacks, approximations and workarounds in this core

Everything in this core's own RTL, scripts or `.mra` layout that is known not to be what the
hardware does: a stand-in, a shortcut, a value chosen to make something work, a workaround for a
tool. Each entry is added in the commit that introduces the hack and removed in the commit that
removes it.

This is not `MAME_KLUDGES.md`. That file lists MAME's own guesses that the core reproduces on
purpose because MAME is the reference. This file lists what is ours.

Rules:

- An entry cites `file:line` (or a module and signal name if the line moves often), and the
  evidence column says what was measured, or "unverified".
- "What would make it correct" names the work, not "fix later".
- A hack whose entry is missing is a bug. A hack whose entry is stale is worse: update it in the
  same commit as the code.
- Severity is what a player or a verifier would see: **visible** (wrong pixels, wrong sound, wrong
  timing a game can hit), **latent** (wrong only for input no in-scope set produces), **tooling**
  (affects the build or the bench, not the bitstream).

| What | Where | Why it is a hack | What would make it correct | Evidence | Severity |
|---|---|---|---|---|---|
| CPU at 93.75 MHz, board runs it at 100 MHz | CPU clock (planned, Phase 0) | the N64 core's rate is used (user decision); code timed by the CPU runs up to 6% slow | an overclock to 100 MHz if Phase 0 Fmax allows | unverified whether any game shows it | latent |
| Sound CPU stand-in on the mailbox | beside the bus bridge (planned, Phase 0) | no V53A: status reads `0x0080` (ready) and the data latch echoes the last command; sound RAM kept so the BIOS read-back passes | a V53A + L7A1045 implementation (Phase 4) | MAME trace to frame 900, `docs/HARDWARE_NOTES.md` "Sound mailbox"; game play not traced | visible (no sound) |
| Video renders a line ahead | `rtl/video/hng64_video.sv`, `bank`/`primed` | the engines fill line N while the mixer emits line N-1, so a mid-screen write to tile VRAM, the palette or the video registers takes effect one line later than MAME shows it | a measurement of when the board latches a line's state; real hardware fills a line buffer during the previous scanline too, so this may already be right | `scripts/write_timing.py` shows both games writing mid-screen; the one-line offset itself is unverified against hardware | latent |

<!-- Examples of the shape, from sibling cores:
| Sound mailbox is a stub that answers the power-on test | `rtl/gx_snd_stub.sv` | No sound CPU yet; the stub returns the reply the test expects and a heartbeat | Phase 3: the real sound board | The game's RAM check passes with it; nothing else is exercised | visible |
| Sound-command spin of 800 CPU clocks after a latch write | `rtl/cpu/…_bus.sv:NNN` | Copies MAME's 40 us wait; the real board's mechanism is unknown | A measurement of the latch on hardware | Without it the second byte overwrote the first (commit) | latent |
| Sound CPU reset held 1,024 clocks | `rtl/….sv:NNN` | MAME's pulse is zero-length; the T80 needs to see it | The measured reset length | A PCB measurement says about one second | latent |
| Screen timing from one game used for every game | `rtl/video/…crtc.sv` | MAME declares 60 Hz with no comment; the one PCB-verified rate is used for all | Per-game timing from PCB measurement | 0.043% from the verified rate | visible |
-->

## Removed

Entries move here when the hack is gone, with the commit that removed it, so a later reader can
tell "never had it" from "had it and fixed it". Delete a row once nothing else refers to it.

| What | Removed by | Replaced with |
|---|---|---|
