# Hyper NeoGeo 64 — MiSTer Core Roadmap

**Approved by the user. A phase whose scope changes goes back for approval.**

## Context

Goal: a DE10-nano MiSTer core for SNK's Hyper NeoGeo 64, emulated by MAME's `snk/hng64.cpp` and
the devices it instantiates — a Quartus 17.0.2 project producing one `.rbf` and a `.mra` per
supported set, reusing proven open components where they exist.

Nothing on this board has an arcade FPGA implementation. The main CPU, a VR4300, exists in the
MiSTer N64 core (GPL-3.0) and is ported, not written. Everything else is new:

1. A bus bridge presenting HNG64's memory map to the N64 core's CPU memory port.
2. The 2D video: sprite generator (NEO64-SPR), four tilemaps (NEO64-SCC), palette, mixer.
3. The IO MCU (Toshiba TMP87CH40N, TLCS-870) and its dual-port RAM, for inputs.
4. The 3D pipeline: display list, transform and lighting, textured rasteriser, two frame
   buffers. In scope (user decision); Phase 3.

**Sound is out of scope** (V53A + L7A1045 DSP): no RTL exists for either, and the FPGA headroom
after the CPU and 3D is unmeasured. It is revisited in Phase 4 with measurements.

Background and sources for every number below: [`HARDWARE_NOTES.md`](HARDWARE_NOTES.md).
Cross-cutting findings from the previous cores are in [`LESSONS_LEARNED.md`](LESSONS_LEARNED.md).
Working practice built on them is in [`WORKFLOW.md`](WORKFLOW.md).

## Progress

**Phase 0 in progress.** Roadmap approved. Repository bootstrapped from Template_MiSTer.

Phase 0 so far:
- VR4300 vendored from the N64 core (`rtl/cpu/vr4300/`, PROVENANCE.md); all 15 files compile in
  ModelSim. One local change: `cpu_mul.vhd` library clause.
- MAME references: `scripts/mame_insn_trace.py` (per-instruction, all GPRs) and a multi-range
  `mame_sys_trace.py`; boot sequence to frame 900, BIOS TLB windows and the sound-mailbox
  handshake recorded in HARDWARE_NOTES. Criterion 2 answered for the BIOS: a mailbox stand-in
  (ready + echo) and a readable 2 MB sound RAM; game play not yet traced.
- **Criterion 1 met.** `rtl/hng64_bus.sv` (CPU port to a 64-bit backing store and a 32-bit
  big-endian I/O port) and `rtl/cpu/hng64_cpu.vhd` (wrapper) run the hng64 BIOS in
  `sim/boot_tb`: 199,998 instructions agree with MAME in PC and all 31 registers
  (`scripts/compare_insn_trace.py`). I/O reads are replayed from MAME's trace in order.
- Three reset-state differences had to be corrected, all because the N64 core boots as an N64
  after its IPL: Status (soft-reset bit), Config clock ratio and Config bits 23:16. See
  `rtl/cpu/vr4300/PROVENANCE.md` and `docs/MAME_KLUDGES.md`.
- **Criterion 3, measured on the real memory:** the boot bench now runs on the vendored SDRAM
  controller with a chip model (main RAM and BIOS) and the DDR3 transport, and **199,998 of
  199,998 instructions still agree with MAME in PC and all 31 registers**. CPI x1000 = 14516
  over 20,000 instructions and 7559 over 200,000, with 72-74% of cycles waiting on memory;
  against the old placeholder latency the same runs gave 10091 at 20,000. Contention with the
  video is not in these figures: the bench runs the CPU alone.
- **Criterion 5 met:** every set's four texture regions are identical copies; largest set after
  de-duplication and without the sound ROM is `sams64_2`, 187 MB.
- **Criterion 4 measured** (`rtl/synth_check/`, HARDWARE_NOTES): CPU + bridge = 9,227 ALMs (22%),
  26 M10K (5%), 9 DSP (8%). 62.5 and 125 MHz close; the 93.75 MHz CPU clock misses by 2.613 ns
  (~75 MHz as placed, ~79 MHz on the best of four seeds), and every worst path is inside the
  vendored CPU. Decided first that a CPU that did not close would be clocked down; replaced by a
  later user decision: the vendored pipeline is changed to close 93.75 MHz, because a lower CPU
  clock tightens its crossings into clk1x (the 3:2 ratio is the only one besides 1:1 that keeps
  them inside a clk1x period). Each change is in rtl/cpu/vr4300/PROVENANCE.md.
- Phase 0 criteria 1, 2, 3 and 5 met; criterion 4 measured, and its clock question closed by that
  decision.
- **Phase 1 started.** `scripts/render_model.py` reproduces MAME's 2D video pixel-exactly on
  2D-only frames (sams64 400/800/1200, buriki 200); frames with 3D differ only where MAME's
  polygon buffer covers the 2D layers. `scripts/rom_regions.py` builds tile and sprite ROM
  images from the driver's ROM_START. See `docs/phase1_video.md`.
- **The three 2D engines match the model on every capture.** `hng64_tilemap.sv`,
  `hng64_sprite.sv` and `hng64_mixer.sv` against `scripts/video_regress.sh`: 105 of 105
  checks at 0 of 229,376 pixels differing, over 21 captures of sams64, fatfurwa, buriki and
  xrally. Faults only the non-sams64 captures could show are in `docs/LESSONS_LEARNED.md`;
  two were model faults the RTL had been matching.
- **The model now transcribes MAME's mixing, not a simplification of it**: sprite groups
  interleaved with tilemap priorities, additive tilemap blending, additive and half-alpha
  sprite blending. `scripts/scan_video.py` samples every video register every frame to find
  frames that use a feature; additive blending is verified against MAME on xrally frame 540,
  and what could not be verified is in `docs/MAME_KLUDGES.md` with what would settle it.
- **The whole 2D video block runs end to end.** `rtl/video/hng64_video.sv` (four tilemap
  engines, the sprite engine, five line buffers, the mixer and a sequencer) rendering from
  nothing but a capture: 127 of 127 checks at 0 of 229,376 pixels differing, 21 captures.
  Two faults were in the seams, not the engines: the benches disagreed about read latency,
  and the block reported idle during the sprite engine's frame-start pre-pass.
- **Phase 1 is done except for throughput**, which is measured and deferred to Phase 2 with
  the DDR3 transport (user decision). The block as sequenced takes 8,900-11,200 cycles a
  line against a 2,880-clock budget.
- **Phase 2 started. Throughput closed, and the memory stack is real.** The engines were
  restructured to issue reads without waiting; tile VRAM and main RAM sit in SDRAM behind the
  vendored controller and a chip model, the tile ROM in DDR3 behind a transport that keeps
  reads in flight. 1,171-2,363 cycles a line against 2,880, pixel-exact at 100-cycle ROM
  latency with half of DDR3's cycles refused. The CPU still boots identically on it
  (199,998 of 199,998). See `docs/MEMORY.md`.
- **ROM loading is done to the point of a .mra.** `scripts/build_mra.py` emits one file per
  in-scope set whose index-0 stream is the DDR3 window itself, and verifies each region
  byte-for-byte by reading its own output back; `hng64_romcfg` latches the per-set layout from
  index 1 and `hng64_romload` copies the BIOS into SDRAM. Two region-image faults came out of
  it: the image was sized by the extent of the loads rather than the declared region (buriki's
  `scrtile` reorder split 4 MB out), and filled with 0xff where MAME uses 0.
- **The board less its CPU replays MAME's boot exactly.** `rtl/hng64_core.sv`: the IO MCU (the
  full TLCS-870 instruction set, running its dumped ROM), the main board's I/O, DMA, the memory
  stack and the video. `sim/sys_tb` drives MAME's bus trace of sams64 into the CPU's port: 0 of
  1,048,576 sound RAM reads and 0 of the I/O reads differ except the dual-port RAM's
  timing-dependent ones, and frames 400 and 800 are 0 of 229,376 pixels different. `sim/iomcu_tb`
  runs the MCU 3M instructions with no trace.
- **The MiSTer top level is written, not built.** `HyperNG64.sv`: the PLL (93.75 / 62.5 / 125 MHz),
  `hps_io`, the VR4300, inputs as MAME's `hng64_fight` ports, Pause, direct video out. Linted in
  Verilator with the CPU and PLL stubbed; no Quartus run yet (user decision).
- **The standard feature set is in, in simulation.** NVRAM to the `.nvm` (`sim/sys_tb`, both
  directions), CRT Adjust (`sim/crt_tb`), HDMI scaling and crop, Flip Screen from the OSD or a fake
  DIP (`sys_tb +flip=1`: frames exact against the model turned 180 degrees), HDMI rotation (since dropped for area)
  (`sys_tb +rot=1`: the rotated buffers exact, the frames exact under the writes), the hidden
  Debug page (layer switches) and ISSP instance F in the stp revision. Hiscore is n/a (no
  `hiscore.dat` entry). None of it has been built or run on hardware.
- **The first full build fits and misses timing** (stp revision, `94df023`): 35,048 of 41,910 ALMs
  (84%), 345 of 553 M10K, 43 of 112 DSP. Setup slack: clk2x -34.823 ns (TNS -172,534), clk93
  -4.533, the SDRAM pins -0.082; clk1x and the framework meet. The first attempt needed 663,477 ALMs
  (memories built from registers; `docs/LESSONS_LEARNED.md`). The clk2x paths are not yet looked at:
  Quartus is on hold (user decision). The sprite engine's z-buffer has since moved to MLABs,
  unsynthesised.
- **Second full build, 2D shrunk, no 3D** (release revision, 73b78aa): 29,192 of 41,910 ALMs (70%;
  the first was 35,048), 2,036,545 block memory bits, 42 DSP. Setup slack: clk2x -4.899 ns (was
  -34.823; now the sprite engine's candidate list, `hng64_sprite` `ci` to `cand_h`), clk93 -2.509 (the
  VR4300's forwarding into `stall1`; underclocking is accepted), the SDRAM pins +0.031, the rest met.
  12,718 ALMs free for the 3D, whose first standalone fit is 12,536 (docs/phase3_3d.md).
- **Phase 3 started (user approval).** `scripts/render_3d.py` transcribes `hng64_3d.ipp` and
  `poly.h`'s rasteriser and clipper in float32 and replays the display-list writes of a trace
  (the bus trace, or a capture's own write log, `mame_capture.py --wlog`). Exact against MAME: the
  BIOS logo (frames 500-652, six frames) and in-game frame 2500, 0 of 229,376 pixels each. What
  in MAME's 3D reads as a slip rather than a guess is in `docs/MAME_KLUDGES.md`, 3D.
- **3D rasteriser RTL** (`rtl/3d/hng64_raster.v`, SpinalHDL): plane gradients (one 20-bit
  reciprocal a triangle), SpinalVoodoo's setup and span walker at HNG64's widths, and the pixel
  unit (1/w by a 10-bit table and a Newton step, texel address, light). With the texel read and
  depth test in the bench, the 3D buffer is identical to the fixed-point model's on six captures
  (sim/raster_tb). A SpinalVoodoo walker bug fixed (`rtl/3d/PROVENANCE.md`). A prefetching
  texture cache and the render buffer (depth plane with frame tags, colour planes, write-back
  depth cache) work through models of hng64_ddram's ports: the colour plane written to DDR3
  matches the model on six captures, two frames each; the start-up texture blocking copy is
  byte-exact.
- **3D in the core** (`rtl/hng64_3d.sv`, `rtl/video/hng64_fb3d.sv`; `docs/phase3_3d.md`, In the
  core): the upload queue, frame sequence and double-buffered display, the DDR3 clients, and the
  3D as the mixer's sixth contributor. `sim/g3d_tb` (engine, rasteriser and hng64_ddram from a
  capture's events) identical to the model on sams64 2500; `scripts/video_regress.sh` passes.
  The full fit and the display path on a whole frame are still to run.
- **3D geometry specified in integers** (`scripts/geom_int.py`, the model's default): within a few
  pixels of float geometry against MAME on six frames. Its RTL is a microcoded engine (user
  decision; `docs/phase3_3d.md`, Geometry RTL): products at most 36 x 36 bits, divides by magnitude.
Hardware notes and feasibility from MAME (`E:/mame` 5ae594bafe9) and the N64 core
(`MiSTer-devel/N64_MiSTer` adbf9b5). No RTL yet.

## Game scope

From `mame -listxml` (0.285). All seven are `MACHINE_IMPERFECT_GRAPHICS |
MACHINE_IMPERFECT_SOUND`.

| Set | Board | ROM total | Without sound ROM, one texture copy |
|---|---|---|---|
| `roadedge` | drive | 127 MB | 71 MB |
| `xrally` | drive | 131 MB | 71 MB |
| `bbust2` | shoot | 155 MB | 95 MB |
| `sams64` | fight | 183 MB | 123 MB |
| `sams64_2` | fight | 251 MB | 187 MB |
| `buriki` | fight | 215 MB | 151 MB |
| `fatfurwa` | fight | 239 MB | 175 MB |

**Criterion 5 met:** all seven sets have byte-identical `textures0..3` (CRCs from
`mame -listxml`), so the last column holds for every set. The largest is `sams64_2` at 187 MB,
inside the 256 MB DDR3 window. Each game also needs the 2 MB BIOS.

### Scope decision

- **In scope:** the fight board sets (`sams64`, `sams64_2`, `fatfurwa`, `buriki`). Digital
  joystick and buttons through the IO MCU; one memory map.
- **Out of the first scope:** drive (`roadedge`, `xrally`): analogue wheel and pedals through
  the IO MCU's ADC, and a network board MAME marks `MACHINE_NODEVICE_LAN`. Shoot (`bbust2`):
  light guns.
- **First target:** `sams64`, the smallest fight set. Final choice is a Phase 0 decision, made
  on which boots furthest, measured.
- **Second target:** `fatfurwa`, the largest ROM set; it exercises the full DDR3 layout.

## Hardware reality (from the driver, not assumption)

### Chips

| Part | Role | Source |
|---|---|---|
| NEC VR4300 (D30200GD-100), big-endian MIPS III | main CPU | hng64.cpp:107 |
| NEO64-SPR | sprite generator | hng64.cpp:105 |
| NEO64-SCC | scroll character controller (tilemaps) | hng64.cpp:106 |
| 3D chipset | display list, transform, rasteriser | hng64_3d.ipp |
| Toshiba TMP87CH40N, 32 KB internal ROM | IO MCU | hng64.cpp:273 |
| NEC V53A + L7A1045 DSP | sound: out of scope | hng64_a.cpp |
| KL5C80A12 | comms: out of scope | hng64.cpp:108 |
| RTC-62423, NVRAM 16 KB, EEPROM | | hng64.cpp:1198, 2584 |

### Clocks

- VR4300: 33.333 MHz in, internal PClock 100 MHz (hng64.cpp:107). MAME runs it at
  `HNG64_MASTER_CLOCK` 50 MHz (hng64.h:218, hng64.cpp:2575). The N64 core runs the same CPU
  at 93.75 MHz. Decided: the CPU runs at the MiSTer N64 core's 93.75 MHz, not the board's 100 MHz;
  an overclock towards 100 MHz may follow. The shortfall is a `docs/HACKS.md` entry.
- Pixel clock: 25 MHz in MAME (`HNG64_MASTER_CLOCK * 2 / 4`, hng64.h:221); 768 x 528 total,
  512 x 448 visible, 61.65 Hz.
- IO MCU: 8 MHz (hng64.cpp:306).

### Interrupts

Vectors as read by MAME from the BIOS (hng64.cpp:1884-1907): irq00 vblank, irq03 "3d FIFO?",
irq11 "IO MCU related?", others empty or invalid. Pending/level registers at
`0x1f701100` (`irqc_r/w`), set by `set_irq` (hng64.cpp:1871). The meaning of irq03 and irq11 is
MAME's guess.

### Memory map

See [`HARDWARE_NOTES.md`](HARDWARE_NOTES.md), "Main CPU map" (hng64.cpp:1182-1249).

### Video

- Four tilemaps, each 8x8 or 16x16, 4 or 8 bpp, with zoom, mosaic, alpha and line modes
  (hng64_v.cpp:123-225; `m_tilemap[4]`, hng64.h:310).
- Sprites 16x16, 4 or 8 bpp, zoomed (hng64_sprite.ipp).
- Palette 16 KB at `0x20200000`; transition control (fades) at `0x20208000`.
- 3D rendered into two 384 KB frame buffers and mixed with the 2D layers.
- MAME marks graphics imperfect; mixing and priority are its model, not the chip's.

### Sound

Out of scope. The main CPU uploads the V53A program to sound RAM (`0x60200000`). With no sound
CPU, the comms at `0x68000000` must still answer the way the BIOS expects: Phase 0 finds out
what that is.

### Protection

None found in MAME. The IO MCU is a real MCU running a dumped 32 KB ROM.

### Per-game configuration

Board type (fight/drive/shoot) selects inputs and init (`init_ss64`, `init_hng64_fght`, ...).
Each init's effect is listed in Phase 0 and becomes `.mra` mod-byte configuration.

## Component reuse map

| block | plan | source |
|---|---|---|
| VR4300 | Port | `MiSTer-devel/N64_MiSTer` adbf9b5, `rtl/cpu*.vhd`, GPL-3.0 |
| 3D texture fetch, z-buffer, perspective correction | Parts of the N64 RDP, if they fit the HNG64 formats | same, `rtl/RDP_*.vhd` |
| Bus bridge to the N64 CPU memory port | From scratch | |
| Sprites, tilemaps, mixer | Written from the software model | MAME hng64_v.cpp, hng64_sprite.ipp |
| TLCS-870 IO MCU | From scratch from MAME's CPU core (user decision), running the dumped 32 KB ROM | MAME `cpu/tlcs870` |
| Transform and lighting | From scratch from the software model | MAME hng64_3d.ipp |
| SDRAM controller | Sibling core's | a prior Arcade-* core, chosen in Phase 2 |
| Hiscore | MiSTer `hiscore.v` | see `references/hiscore.md` in the skill |

## On-chip RAM budget

Not yet estimated. Phase 0 measures the CPU's caches and TLBs. Large RAMs go to SDRAM/DDR3.

## Memory plan

- **DDR3** (256 MB window at `0x30000000`, loaded by the HPS from the `.mra`, see
  `ddr_rom_loading.md`): BIOS, program, sprite and tile ROM, one texture copy, vertex ROM.
  Largest set 175 MB. The sound ROM is not loaded.
- **SDRAM**: 16 MB work RAM and the 3D frame buffers; the remaining space holds whatever ROM
  Phase 1 measures as too slow from DDR3 (tile ROM is the likely candidate).
- **Block RAM**: palette, sprite RAM, tilemap regs, dual-port RAM, line buffers.
- DDR3 is shared with the framework's scaler and the CPU's cache fills. The per-scanline fetch
  budget is measured in Phase 1, not modelled.

## Design decisions

**Follow MAME, including where MAME is wrong, and write down every place that is.** There is no
PCB here. MAME is the accuracy target and its acknowledged guesses are inherited deliberately. Each
goes in `docs/MAME_KLUDGES.md` when it is implemented, with what MAME does, what the hardware is
suspected to do, and what would settle it.

**Where a vendored module and MAME disagree, record it and keep the module.** A silicon-derived
disagreement is evidence about the chip; MAME's is evidence about MAME. It goes in
`docs/MAME_KLUDGES.md`, not into a "fix", until one side is shown to describe the chip.

**Every approximation of this core's own goes in `docs/HACKS.md`** in the commit it lands, with
what would make it correct. A hack that is not written down is a bug nobody will find.

**Transcribe the reference literally first, then look for the chip.** Build MAME's version, get
pixel-exact (or trace-exact) agreement with captured references, and only then experiment — with
the experiment on an OSD switch so it is an A/B, not a rebuild.

**One `.rbf` for all games.** Per-set differences are `.mra` mod-byte configuration.

**Two Quartus revisions, `HyperNG64_stp` and `HyperNG64`,** differing only by a `DEBUG_ISSP` macro.
See [`WORKFLOW.md`](WORKFLOW.md).

**Licence: GPL-3.0-or-later.** Required by the N64 core's CPU. Every dependency, what it obliges
and the release checklist go in `THIRD-PARTY.md`. `sys/` is never edited.

**No multiplies, no divides, in the 2D pipeline and CPU glue** (WORKFLOW §14): sprites,
tilemaps, mixer, bridge. **The 3D pipeline is GPU-like and uses them by design** (user decision):
transform and lighting, perspective correction and the rasteriser are budgeted in DSP blocks in
Phase 3, and are not hacks.

**The N64 CPU is used as is, behind a bridge.** Its N64-specific ports (`rdram_granted2x`,
`ddr3_DOUT*`, `ram_*`) are driven by the bridge; its savestate and debug ports are tied off.
Edits to its files are listed in its `PROVENANCE.md`.

**Sprite list snapshotted at vblank start; everything else read live per line.** From
`scripts/write_timing.py` (docs/phase1_video.md): the games write the sprite list in the first two
lines after vblank start, and write tile VRAM and palette mid-screen while playing. So the sprite
list is double-buffered and the rest is raster.

**Store one copy of the graphics ROM** (user decision): there is no memory for the board's
duplicates. The four texture copies are for the board's parallel access; one copy saves 48 MB
a set. Any bandwidth the rasteriser loses by it is met in the memory design, not by copies.

**No sound ROM loaded, and the sound CPU is absent.** Recorded in `docs/HACKS.md`, with the
comms stand-in Phase 0 needs.

## Pitfalls that already bind decisions here

Section names in [`LESSONS_LEARNED.md`](LESSONS_LEARNED.md); read the entries before the matching
phase.

| Section | What it binds here |
|---|---|
| Diagnosis discipline | suspect the bridge before the N64 CPU |
| CPU cores (TG68K.C, T80, vendored CPUs) | porting the VR4300 |
| Memory transport: req/valid contracts, latency, byte order | the bridge; big-endian CPU, DDR3 |
| ROM loading: .mra, byte order, deployment | DDR3 layout, texture de-duplication |
| Sprite lists, line buffers and snapshots | sprite and tilemap timing (Phase 1) |
| Timing closure | 93.75 MHz CPU, DDR3 clock domains |

## Phased roadmap

**Phase 0 — CPU spike and the measurements. The gate.**

Vendor the N64 CPU into `rtl/cpu/vr4300/` with a `PROVENANCE.md`. Stand it up in its own
Quartus project (`rtl/synth_check/`) with the bridge and a DDR3 transport and nothing else.
Exit criteria:

1. **The CPU boots the `hng64` BIOS and matches MAME's bus trace**, diffed access by access,
   every peripheral stubbed to what MAME returns (`mame_boot_trace.py`).
2. **The sound-comms and IO-MCU stubs the BIOS needs are known**, from a MAME system trace.
3. **Measured CPI on BIOS and game code**, split between execution and memory stall.
4. **Standalone Fmax and area for the CPU and bridge at this project's settings.** Confirms
   93.75 MHz closes timing, says how much headroom an overclock has, and gives the ALM/M10K/DSP
   budget left for everything else.
5. **Every set's texture regions checked for identical copies**, from `-listxml` CRCs.

**Phase 1 — 2D video, against a software model.**

`mame_capture.py` + a `render_model.py` for sprites, four tilemaps, palette, fades and the mixer,
pixel-exact against MAME on captured frames. Then RTL against the model, layer by layer, in
Verilator. Run the video-write sweep before choosing line buffering. Exit: `sams64` 2D frames
pixel-identical to MAME's for a captured set of scenes, in simulation, with the 3D layer empty.

**Phase 2 — Hardware bring-up and inputs.**

DDR3 ROM loading, SDRAM work RAM, `.mra` generation, the TLCS-870 IO MCU and dual-port RAM,
inputs and DIPs, NVRAM/EEPROM/RTC, the ISSP probe and the OSD debug page, and the standard
feature set: CRT offset (v-size if BRAM allows), hiscore, HDMI scaling and crop, HDMI rotation,
HDMI-only options hidden under direct video, CRT offset parameters hidden until enabled, and
flip screen from the OSD or the DIP (a fake DIP
for sets without one) through the core's own flip logic, worked out per layer, 3D included, for
this board. The HDMI rotator is another DDR3 client beside ROM reads. Audio mix waits for sound.
Exit: `sams64` boots to attract mode and accepts coins and inputs on a DE10-nano, 2D only.

**Phase 3 — 3D. In scope.**

The area measured in Phases 0-2 sizes the design, not whether it happens. Display list, transform and
lighting, textured rasteriser, frame buffers, mixing with 2D, against a software model of
hng64_3d.ipp. Exit: `sams64` in-game frames match MAME's in simulation, then on hardware.

**Phase 4 — Sound on the ARM (user decision), the MiSTer Frontier model. Approved.**

The V53A and the L7A1045 run in a Linux process on the HPS; the FPGA carries the sound RAM, the
mailbox and the samples. With no process the core runs as now, silent.

From MAME (`scripts/mame_sound_trace.py`, fatfurwa 600 frames, `debug/fatfurwa-sound`): the main
CPU writes the whole sound program before it enables the sound CPU (`0x55AA` at frame 76) and
touches sound RAM no more after; it sends one command a frame and reads the reply the next frame;
the V53A replies 7 us after the interrupt. A millisecond of latency each way is inside that.

- **Launch.** `/tmp/CORENAME` is an `.mra`'s `<setname>` (Main_MiSTer `user_io.cpp:506`), so
  Frontier's `Master_Daemon.sh` runs `games/<setname>/_handler.sh`: one per set, each starting
  `games/HyperNG64/hng64snd` (armhf, static).
- **Shared DDR3, `0x3F200000` up** (above the 3D buffers, inside the core's window): a control
  block the FPGA writes (the sample ROM's base and size, a count of sound CPU enables, the main
  CPU's two latches and a count of its interrupt-5 writes); a status block the process writes (a
  heartbeat, the sound CPU's data and status latches); and a 2 MB copy of sound RAM, written by
  the FPGA on every main-CPU sound RAM write. SDRAM keeps the main CPU's copy. The enable count
  moves only once the copy's writes have drained. Layout in `rtl/hng64_sndbridge.sv`.
- **Samples.** The `l7a1045` region (16 MB) joins the `.mra` image after `verts` and the index-1
  blob; the largest set, `sams64_2`, then ends at `0xD900000`, under `D3_BASE`.
- **FPGA** (`hng64_sndbridge`): the sound RAM mirror and mailbox writes share the DDR3 writer with
  the 3D, taking turns; the status block is read every 8 us. The mailbox answers from the process
  while its heartbeat moved in the last 0.1 s and it runs the V53A, else from the stand-in.
- **Audio** goes out through the framework's ALSA path, not the core: the process writes 48 kHz
  to `/dev/MrAudio` (the default ALSA device's sink, `/etc/asound.conf`), which `sys/alsa.sv` reads
  from DDR3 and `audio_out` mixes with the core's. Writes there do not block, so the process
  paces itself by CLOCK_MONOTONIC, 40 ms ahead; `alsa.sv` plays faster as its buffer fills.
- **Process.** The V33 core, the V53A's timer, interrupt and DMA units, and the L7A1045, ported
  from MAME (BSD-3-Clause; the board glue, `hng64_a.cpp`, LGPL-2.1+), in `sw/hng64snd`; paced by
  the ring, resampled 44.1 to 48 kHz, so the pitch never follows the game's speed; the control
  block polled each 0.5 ms of emulated time.
- **Bench.** The same emulator built natively (`sw/hng64snd/bench.cpp`), driven by a MAME capture
  (sound RAM at the enable, the main CPU's mailbox writes and their times, the sample ROM), its
  output compared with MAME's `-wavwrite`; then `sim/` for the bridge, then the board.
  Done for fatfurwa, 1200 frames (`scripts/mame_sound_trace.py fatfurwa 1200`): the first 91,391
  of MAME's 520,677 V53A I/O accesses are identical in value (the first 25 in time too); all 94
  mailbox values the main CPU read are identical; the 10 ms level envelopes of the front
  channels correlate 0.9999 and 0.9996 with MAME's (`scripts/snd_compare.py`). The first
  difference is a read-back of a voice's filter envelope, which depends on timing, and the port's
  V53A runs ahead of MAME's by 0.18%. A likely cause, untested: MAME's scheduler cuts the V53A's
  timeslices at timers anywhere in the machine, and a REP string instruction resumed after a cut
  costs 2 more cycles. Not pursued (user: a little off is fine, a pitch change with the game's
  speed is not). The V53A runs 5.3 M instructions a second of game time and never halts.
  On the MiSTer's ARM (`scripts/snd_arm_bench.py`, sams64 running in the FPGA) the same 18.2 s
  take 26.7 s (-O3, ARM mode; output identical to the x86 build): 0.68 of real time, about 220
  cycles a V33 instruction. A switch dispatch is faster on x86 and slower there; idle skipping
  has no quiet main-loop pass to skip (every one changes RAM). MAME runs the V53A's core at its
  32 MHz input, where its V40 and V50 (`v50_base_device`) divide the input by 2; at 16 MHz the
  port runs 18.2 s in 17.4 s on the ARM, keeps up with the mailbox's command sequence, and differs
  from MAME in bit 1 of the status reply (18 of 94 reads). Decided (user): the ARM process runs
  the core at 16 MHz (MAME_KLUDGES). MAME gave the V53A 32 MHz / 2 until `826b75656f6`, which
  doubled it for the timer's sake ("reference footage indicates the timer must be the full
  32 MHz"); the V50's datasheet has the crystal at twice the operating frequency, and the V53A's
  range is 2-20 MHz (elm-chan.org/docs/dev/v53_e.html). At 16 MHz, under `chrt -f 50` (sams64 in
  the FPGA; Main_MiSTer and the Zaparoo daemon take a core between them): 14.73 s for the 18.2 s,
  13.07 s built with profile feedback (-fprofile-use, trained on the same run); with Zaparoo
  stopped 13.91 s and 10.75 s. The process runs at real-time priority, built with profile
  feedback.

**Phase 5 — The other fight sets, and accuracy.** `sams64_2`, `fatfurwa`, `buriki`, their
`.mra` files, `docs/MAME_KLUDGES.md` and `docs/HACKS.md` current.

**Phase 6 — Drive and shoot boards.** Analogue wheel and pedals, the network board; `bbust2`'s
light guns with mouse aiming and a synthetic crosshair. Their OSD groups are hidden for the
fight sets.

**Phase 7 — Savestates and cheats.** Optional but desirable. MAME has no savestate support for
this driver, so there is no reference to check one against.

## Verification strategy

- **MAME is a reference generator, driven from scripts, not a thing to eyeball.** Boot traces, VRAM
  and register dumps at known frames, palette dumps, register-write logs. WORKFLOW §9 applies.
- **The software model comes before the RTL.** The model is checked against MAME first; the RTL
  against the model.
- **The N64 CPU is regression-tested against MAME's VR4300 bus trace**, not only against the N64
  core's own behaviour.
- **Layouts are verified before ROMs are involved**: every `gfx_layout` gets the "every bit of a
  tile exactly once" check.
- **`.mra` files are generated, not written**, re-read byte-for-byte against an image built from
  `ROM_START`, and gated on an XML well-formedness check before deploy.
- **Worst cases are measured in the RTL**, not modelled: saturating counters with no reset port,
  each paired with a total.
- **PCB footage** (`references/pcb_video_reference.md` in the skill) is the only check on MAME's
  imperfect graphics; logged in `docs/REFERENCE_VIDEO.md` when used.

## Repository setup

Seeded from **MiSTer-devel/Template_MiSTer**, `Template.*` renamed to `HyperNG64.*` and split into
the `HyperNG64_stp` and `HyperNG64` revisions; the Quartus 13 project dropped. Quartus **17.0.2**.
Private repository `ppriest/Arcade-HyperNG64_MiSTer`. GPL-3.0-or-later.

## Open items

**Does everything fit?** The N64 core fits CPU + RSP + RDP; its headroom is not measured. 3D is
in scope regardless, so this sizes the 3D design and decides sound (Phase 4). Measured by Phase 0
criterion 4 plus the Phase 1 and 2 build reports.

~~**IO MCU: real core or stand-in?**~~ Closed: a TLCS-870 core written from MAME's `tlcs870`,
running the dumped ROM (user decision). No stand-in.

**Does the BIOS run without a sound CPU?** Unknown. Closed by Phase 0 criterion 2.

**Does the CPU close 93.75 MHz?** Standalone it misses by 2.613 ns (criterion 4). Decided (user):
the vendored pipeline is changed until it closes, rather than lowering the CPU clock. A lower
clock was the first decision; it was replaced because any ratio other than 3:2 or 1:1 to clk1x
shortens the crossing paths, which already miss at 3:2 (build f9bb4cc, -0.131 ns).

**CPU clock at runtime.** Decided (user): after clk2x closes at 125 MHz, the CPU's crossings into
clk1x become clock-domain FIFOs and the CPU gets its own PLL output, reconfigurable from the OSD.
The CPU is then constrained at a frequency that closes, and higher settings (the board's 100 MHz)
are offered as an overclock that timing analysis does not cover. clk2x stays fixed: the 25 MHz pixel
clock and the video's line budget need it.

**What does 93.75 MHz cost?** Decided to run at 93.75 MHz. Game logic timed by the CPU runs up
to 6% slow; a MAME run at 93.75 MHz shows whether any of it is visible. Overclocking is a later
option, measured by Phase 0 criterion 4's Fmax.

**DDR3 bandwidth** for CPU fills, tile ROM, textures and vertices together. Closed by Phase 1
measurement.

**3D: language and reuse (Phase 3, not yet approved).** Direction from discussion: the 3D
datapath in SpinalHDL as its own module with stream interfaces, the glue (display-list port,
frame-buffer read-out into the mixer, flip) in SystemVerilog, reusing SpinalVoodoo's triangle
setup, rasteriser, texture cache and DDR3 back end where they fit. SpinalVoodoo has no licence;
one has been asked of its author and is assumed granted for planning (user decision). If the
answer is no, reuse is off and the plan is redone.

**3D: area (user decision).** Phase 2 as built leaves about 6,900 ALMs; the 3D is estimated at
10,000-11,500 (`docs/phase3_3d.md`, Area). The area comes from shrinking the 2D video and from
dropping HDMI rotation (done). Not taken: the framework's size options, a cheaper 3D.

**3D: architecture (user decisions).** Render buffer in DDR3 with a frame tag instead of a clear;
two buffers swapped at the clearing vblank; SpinalVoodoo's triangle setup and rasteriser, widened,
the command, geometry, texture and pixel units ours (`docs/phase3_3d.md`, Proposed architecture).

**3D: memory (user decisions).** Immediate mode kept: depth (32 bits: frame tag and z) and colour
(16 bits) as two planes in DDR3, the display reading colour only. A frame too heavy to finish in
time shows the previous 3D frame (for HACKS when built); fatfurwa 2500 is estimated at 63% of the
DDRAM port's data clocks on its own. Tiled rendering, 3-4x less traffic, was not taken: it puts
the 3D two frames behind the 2D. The texture ROM is copied once at start-up into 4 x 8-byte blocks
(32-byte lines), 1.4-3x fewer texture misses (`docs/phase3_3d.md`, DDR3 traffic).

**3D: fixed point, not MAME's floats.** Every 3D input is 16-bit fixed point: MAME's `uToF`
(`hng64_3d.ipp:1288`) is `s16 / 32768` on the matrices, vertices, texture coordinates and
normals; the floats are MAME's. The word widths come from a fixed-point mode of the Python model
swept against MAME's frames; the RTL is then bit-exact to that model, and the model is within a
measured tolerance of MAME, recorded in `docs/MAME_KLUDGES.md`.

## Next steps

1. Timing closure at full speed (user decision: clk2x 125, clk3d 100, CPU on its own PLL). With
   CLK_VIDEO at 50 MHz and YC disabled (user decision, `bad3a3a`), `20b5e7d` seed 2 passes every
   clk2x path in the core, CLK_VIDEO and clk1x. Left: SDRAM reads, which the SDC times on the edge
   the RTL samples and which no capture phase closes at CL2 and 125 MHz with its chip numbers
   (`docs/HACKS.md`; setup -1.95 slow, hold +0.54 fast, `3023dda`); they work on the board. CL3
   and a 3-clock tRCD, memtest's timings, cost 15.5% on `sys_tb` and are not used (user decision).
   clk3d: the paths each placement failed were taken off in turn (`176837c` to `cef30f5`, no clock
   moved but EMIT's one a triangle), and the OSD clock options and the scaler's adaptive scanline
   filter removed for area (`04c8ca2`). Best: `50112e7` seed 1 -0.032 ns, one endpoint (fixed in
   `cef30f5`), and `cef30f5` seed 2 -0.096, one, both with PHYSICAL_SYNTHESIS_EFFORT EXTRA,
   ROUTER_TIMING_OPTIMIZATION_LEVEL MAXIMUM and PLACEMENT_EFFORT_MULTIPLIER 2.0 (`build_staged.py
   --set`); other seeds -0.3 to -0.9, one seed in four does not fit. Lite has no LogicLock regions
   (warning 292013) or partitions. The geometry engine is now SystemVerilog (`65f79d7`; -0.245, its
   worst path ST's 72-bit two-way shift into mVal); E's hold reads registers only (`3257a5e`) and
   ST shifts a step earlier (`2373ebe`). `2373ebe` seed 1: -0.099 ns, one endpoint, the forwarded
   M result into the branch decision (mVal to brPending); seed 2 -0.247. Seed 1 is on the board
   (`HyperNG64_30000061.rbf`, sams64's 3D drawn, `debug/hw_i1_sams64.png`).
2. All four sets run their attract modes with sprites since `c17f1fb` (sprite list read latency).
   To compare with MAME: fatfurwa's helicopter cabin (two of three men missing on the board, the
   third without his face; g3d_tb renders MAME's f1600 exactly, at 2.59 M clk2x clocks a frame
   against the display's 2.03 M), buriki's Ducalis intro (a yellow zigzag block). sams64_2's
   mirrored text and offset portrait are MAME's too (`debug/mame_s64b`, f1320, f2520, f3840).
   fatfurwa's title logo matches MAME's fly-in at f3600.
3. 3D throughput. Where the engine is slower than the game, the upload queue (32) fills, interrupt
   3 is held, the game's uploads run past the vblank and the clearing vblank's event lands among
   them, so a frame is shown part drawn: buriki's Ducalis intro cut off at a line, fatfurwa's cabin
   with models missing. OSD Game speed Auto (`d23a492`) hides a frame from the game when interrupt
   3 was held: on the board fatfurwa's intro is then whole, where at 100% it loses two of three
   men, the legs and a head (`debug/hw/ff_auto_compare.png`). In g3d_tb (+prof, latency 60, 20%
   busy; clk3d, 1.67 M in a 60 Hz frame), `6063e54`: fatfurwa f1600 1.49 M, the rasteriser busy for
   1.48 M; sams64 f2500 (a 3D frame every other video frame, 3.33 M) 3.65 M, the engine busy
   3.50 M, most of the excess the accumulator stores (ST, STF, STV) and SHRI, multi-cycle in
   rtl/3d/hng64_geo.sv for timing where docs/phase3_3d.md's 2.46 M estimate has one clock each.
4. Hangs. The tilemap engine busy for ever with nothing owed by DDR3 (`5626a76`, `74f4d60`, and
   fatfurwa's intro on the stp build of `bc6546a`) was a layer's mode written by the CPU mid-pass,
   not placement: fixed in `b9e8900` (LESSONS_LEARNED). The sprite engine's (per-line zoom test,
   copy after the passes) were fixed before. Not yet explained: on the same stp build fatfurwa once
   stopped with the CPU idle at 0x04000008, interrupts pending and its error flag set, the 3D and
   video running (that build misses the CPU clock by 0.141 ns).
   Also seen once: buriki at 100% stopped on Ducalis's intro for at least 2.5 minutes (`3b5372e`
   seed 1, `debug/hw/bfull_bk_sheet.png`); not again in a later run or a 10-minute soak at 100%
   on `6063e54` seed 1, whose placement is the same (`debug/hw/soak_bk_sheet.png`).
   sams64 sometimes stops on an I/O error after a while (user, on the board). Not investigated;
   to check again once sound (Phase 4) replaces the sound comms stand-in.
5. A mosaic sprite on a synthetic capture (`debug/sams64-wide`) draws its runs a pixel off the
   model's; no MAME capture has shown it.
