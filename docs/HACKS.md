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
| CPU at 93.75 MHz or below, board runs it at 100 MHz | CPU clock (the top level's PLL) | the N64 core's rate is used (user decision), and if the full design does not close it the clock is lowered further and the game runs slow (user decision); code timed by the CPU runs at least 6% slow | a clock that closes at 100 MHz | standalone the CPU closes about 79 MHz (ROADMAP, criterion 4); the full design is not compiled yet | visible if lowered, else latent |
| Sound CPU stand-in on the mailbox | `rtl/hng64_io.sv`, `D_SNDCOM` | no V53A: status `0x68000006` reads `0x0080` (ready) and the data latch `0x68000004` holds `main_latch[0]` as of the last trigger; sound RAM is plain memory so the BIOS read-back passes | a V53A + L7A1045 implementation (Phase 4) | `sim/io_tb`: all 6 mailbox reads to frame 900 match MAME, which ran the real V53A; game play not traced | visible (no sound) |
| RTC time is the host's, and read-only | `rtl/hng64_io.sv`, `rtc_read` | the MSM6242's time comes from `hps_io`'s RTC; writes to its time registers are dropped, and its BUSY and IRQ FLAG bits never set | an MSM6242 that counts and can be set, seeded from `hps_io` | `sim/io_tb`: the control registers match MAME; the time registers are not compared (MAME's is the host clock too) | latent |
| No network board | `rtl/hng64_io.sv`, `D_COM` | the comms board's shared RAM is plain RAM and there is no KL5C80; the line-240 network interrupt is still raised, as MAME raises it | nothing for the fight sets; the drive sets would need the board | the boot to frame 900 never touches `0xc0000000` | latent |
| DMA reaches the backing store only | `rtl/memory/hng64_dma.sv` | MAME's copy goes through the whole address space; this one reads and writes RAM, ROM and the plain-memory regions, and raises `err_nonstore` for anything else | route a device address through `hng64_io` | the one copy the boot makes, 1,024 dwords from `gameprg` to RAM, matches MAME's writes in `sim/io_tb` | latent |
| Interrupt 3 held while the 3D queue is full | `rtl/hng64_io.sv`, `fifo3d_cnt`; `rtl/hng64_3d.sv`, `dl_full`/`dl_upbusy` | MAME raises interrupt 3 5,120 CPU cycles after an upload whatever the work; here uploads are queued (32 slots) for the geometry engine, and with one slot left the count holds at 2 until the engine frees one; an upload with no slot free, or a display-list write during an upload's 129-clock copy, waits on the bus | an engine that keeps up with MAME's timing, or the board's real FIFO behaviour, which is unknown | none: unbuilt. The engine is estimated at 1.78M clk2x clocks for a sams64 3D frame against 4.17M between its clears (`docs/phase3_3d.md`); the start-up blocking copy (about 43 ms) delays the first uploads' engine work | visible if hit (game slowdown) |
| 3D shown one frame behind MAME | `rtl/hng64_3d.sv`, `S_FIN`/`S_SWAP`; `rtl/video/hng64_fb3d.sv`, `shown_*` | MAME draws into the buffer it shows; here a frame draws into one of two colour planes and is shown from the vblank after its clearing vblank, and a frame not finished by then stays off screen a frame longer (user decision, two buffers) | none planned: rendering into the displayed plane would tear | none: unbuilt | visible (3D a frame late against the 2D) |
| A polygon chunk of unknown type is skipped | `scripts/geo_ucode.py`, the chunk dispatch in `poly` | MAME (`recoverPolygonBlock`) consumes its three header words and then transforms and draws whatever its reused polygon slot last held; the engine consumes the same three words and draws nothing | none needed unless a set uses such a chunk: then MAME's behaviour, which is stale data, would have to be modelled | the six captures use types 0x04, 0x05, 0x0F, 0x87, 0x97, 0xC7, 0xD7 only (`geom_int.py` stats) | latent |
| Video renders two lines ahead | `rtl/video/hng64_vtiming.sv`, the pass schedule | a pass of `hng64_video` renders line L while its mixer emits L-1 at its own pace, so the display side buffers that output and starts the pass for line d+2 as line d begins; a mid-screen write to tile VRAM, the palette or the video registers takes effect two lines later than MAME's whole-frame render can show | a mixer that streams at the pixel clock, which would take one line off; what the board does is unmeasured | `sim/sys_tb` frames 400 and 800 are exact, but they are static frames; `scripts/write_timing.py` shows both games writing mid-screen | latent |
| Display sync positions, and progressive output | `rtl/video/hng64_vtiming.sv`, `HS_*`/`VS_*` | MAME gives the totals and blanking (768 x 528, 512 x 448 visible, 25 MHz) but no sync, so hsync is pixels 608-671 (centred in the blanking, which gives CRT Adjust 96 pixels of front porch to work in) and vsync lines 452-455 by choice; and the board draws 264 lines a field interlaced at 15 kHz, which this outputs as MAME runs it, 528 progressive lines at 32.55 kHz | a board's sync measured; an interlaced 15 kHz mode for CRT users | none: chosen | visible (CRT) |
| Flip Screen renders the frame bottom line first | `rtl/video/hng64_vtiming.sv`, `flip_f` | flipped, source line 447 is rendered as the beam starts and line 0 last, so a write the game makes mid-frame lands in the picture where the flipped beam is, not where it would on a board whose monitor were turned | a frame buffer, which would render in source order and read flipped a frame later | `sim/sys_tb +flip=1`: frames 400 and 800 exact, static frames | latent |
| Pause stops the CPU at its next memory access | `rtl/cpu/hng64_cpu.vhd`, `pause` | the VR4300's `ce_1x` gates only new memory requests, so code running from cache continues until it misses or touches I/O; the rest of the board, IO MCU and video included, keeps running | gating the whole pipeline's `ce_93`, which the N64 core does not do and nothing here has tested | none: unbuilt | latent |
| Coin pulse 16.8 ms | `HyperNG64.sv`, `coin_t` | MAME's `PORT_IMPULSE(1)` is one frame, 16.2 ms; this is 2^20 clk1x | a frame counted from vblank | none: unbuilt | latent |
| SDRAM clock phase carried over | `rtl/pll/pll_0002.v`, `outclk_3` | 180 degrees is what the Seta, Psikyo and Fuuki cores run on hardware at 96 MHz; here it is 125 MHz. `HyperNG64.sdc` carries their pin constraints unchanged (two-cycle read capture), uncompiled | the first compile's timing report on the SDRAM pins, then a hardware run | none: unbuilt | visible if wrong (the CPU would not boot) |

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
| IO MCU cycle counts transcribed but not verified | `hng64_iomcu.sv`: the bench takes interrupts from the modelled timer, not the trace | 1,560 timer interrupts land on MAME's instructions across 3M; a one-cycle shorter period fails at the second |
