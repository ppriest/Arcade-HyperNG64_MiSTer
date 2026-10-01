# Hyper NeoGeo 64 core for MiSTer

A MiSTer FPGA core for SNK's Hyper NeoGeo 64 arcade hardware (MAME's `hng64`), built with Quartus
Prime 17.0.2 Lite for the DE10-nano.

**Status: in bring-up. The BIOS boots on hardware (half-speed build) and runs its RAM test; no game
reaches its title yet. Not for playing.**

## Contents

- [History](#history)
- [Games](#games)
  - [Supported](#supported)
  - [Not yet](#not-yet)
  - [Out of scope for now](#out-of-scope-for-now)
- [Hardware](#hardware)
  - [Video timing](#video-timing)
- [Screenshots](#screenshots)
- [Installation](#installation)
- [Controls](#controls)
- [Status](#status)
  - [Features](#features)
  - [Todo](#todo)
  - [Resource usage](#resource-usage)
- [AI Attestation](#ai-attestation)
- [Verification](#verification)
- [Acknowledgements](#acknowledgements)
- [Layout](#layout)
- [License](#license)

## History

No release yet.

- Hardware bring-up, on a half-speed build (every clock halved, `halfspeed` branch, bring-up
  only). The BIOS stalled polling a 3D register because the vendored CPU cut TLB-mapped physical
  addresses to the N64's 29 bits (`rtl/cpu/vr4300/PROVENANCE.md`); with that fixed it boots and
  runs its RAM test, which shows the IO MCU's dual-port RAM as failing, a test MAME's run of the
  same BIOS never makes. Being traced against MAME with the `HyperNG64_stp` revision's probes.
- Phase 3: the 3D (geometry engine, rasteriser, render buffer in DDR3) written and in the core;
  identical to the fixed-point model in simulation. The full core fits the device (97% of ALMs) but
  misses timing at full speed.
- Phase 2: the whole board less sound, the MiSTer top level and the standard features, in
  simulation.

## Games

The fight board sets: two-player stick and buttons through the IO MCU, one memory map. Each needs
the `hng64` BIOS and is loaded into DDR3 (137 to 201 MB); main RAM, the BIOS copy and tile VRAM
are in a 32 MB SDRAM module.

### Supported

Sets with an `.mra` in `releases/`. None has run to a game on hardware.

| Name | Year | Manufacturer | MAME set | Notes |
|-|-|-|-|-|
| Samurai Shodown 64 / Samurai Spirits / Paewang Jeonseol 64 | 1997 | SNK | `sams64` | BIOS boots on hardware (half speed); stops in its RAM test |
| Samurai Shodown 64: Warriors Rage / Samurai Spirits 2: Asura Zanmaden | 1998 | SNK | `sams64_2` | not yet seen on hardware |
| Fatal Fury: Wild Ambition / Garou Densetsu: Wild Ambition (rev.A) | 1998 | SNK | `fatfurwa` | not yet seen on hardware |
| Buriki One: World Grapple Tournament '99 in Tokyo (rev.B) | 1999 | SNK | `buriki` | not yet seen on hardware |

### Not yet

| Name | Why |
|-|-|
| everything above | the core does not yet boot a game on hardware |

### Out of scope for now

| MAME description | Why |
|-|-|
| Roads Edge / Round Trip RV (rev.B) | drive board: analogue wheel and pedals through the IO MCU's ADC, and a network board MAME marks `MACHINE_NODEVICE_LAN` |
| Xtreme Rally / Off Beat Racer! | drive board, as above |
| Beast Busters: Second Nightmare | shoot board: light guns |

## Hardware

| Chip | Function | Status |
|-|-|-|
| NEC VR4300 | main CPU | the MiSTer N64 core's CPU, vendored with changes (`rtl/cpu/vr4300/PROVENANCE.md`); matches MAME for the BIOS's first 199,998 instructions in PC and all 31 registers (`sim/boot_tb`) |
| Toshiba TMP87PH40AN (TLCS-870) | IO MCU: inputs, coins, lamps | transcribed from MAME's `tlcs870` (`rtl/io/hng64_tlcs870.sv`), runs the dumped ROM |
| main board I/O | interrupts, DMA, RTC, NVRAM, dual-port RAM | written here from MAME's driver (`rtl/hng64_io.sv`) |
| NEO64-SCC, NEO64-SPR | four tilemaps, sprites, mixer | written here from MAME's video (`rtl/video/`); pixel-exact to a model of MAME's renderer in simulation |
| 3D chipset | display list, geometry, rasteriser | written here (SpinalHDL, `rtl/3d/`): a microcoded geometry engine and a rasteriser after SpinalVoodoo; render buffer in DDR3 |
| V53A + L7A1045 | sound CPU and DSP | not implemented; the CPU's mailbox is answered by a stand-in (`docs/HACKS.md`) |
| KL5C80A12 | network board | not implemented; its shared RAM is plain RAM (`docs/HACKS.md`) |

### Video timing

25 MHz pixel clock (a pixel every five clk2x clocks), 768 x 528 total, 512 x 448 visible, 32.55 kHz
and 61.65 Hz, as MAME's screen (`hng64.h`); 528 progressive lines as MAME runs the board's
interlaced 264-line field. MAME gives no sync positions; the ones here are this core's
(`docs/HACKS.md`). The half-speed bring-up build runs everything at half rate, about 30.8 Hz.

## Screenshots

None yet: no set reaches its title on hardware.

## Installation

A 32 MB SDRAM module is required.

* Take the latest `*.rbf` from `releases/` and put it in `_Arcade/cores`, renamed to drop the
  `Arcade-` prefix (`Arcade-HyperNG64_YYYYMMDD.rbf` becomes `HyperNG64_YYYYMMDD.rbf`). MiSTer launches
  the highest-sorting match for `<rbf>HyperNG64</rbf>`, and a `HyperNG64_*.rbf` sorts above every
  `Arcade-HyperNG64_*.rbf`
* Take the `*.mra` files from `releases/` and put them in `_Arcade` (or a subdirectory starting with
  an underscore, e.g. `_Arcade/_HyperNG64`)
* Put the MAME merged or split ROM sets in `games/mame`, with the `hng64` BIOS set (`hng64.zip`)

To run a development build instead: `python scripts/build_staged.py`, then `python scripts/deploy.py`
with a `mister.env` (see `scripts/deploy.py`).

## Controls

Two players, an 8-way stick and four buttons each, as MAME's `hng64_fight` ports:

| OSD name | default pad button | board input |
|---|---|---|
| Button 1-4 | A, B, X, Y | the four attack buttons |
| Start | Start | Start 1 / Start 2 |
| Coin | Select | Coin 1 / Coin 2, one 16.8 ms pulse per press |
| Pause | L | suspends the main CPU; press again to resume |
| Service | - | Service 1 (either pad) |
| Test | - | the test switch (either pad) |

## Status

Known issues:

* **No game boots on hardware yet.** On the half-speed build the BIOS runs its RAM test and reports
  the IO MCU's dual-port RAM as failing; MAME's BIOS skips that test. Being traced.
* **The full-speed build misses timing**: clk2x (125 MHz) by 5.96 ns, the CPU clock (93.75 MHz) by
  1.80 ns (commit `41c854b`). Bring-up runs at half speed.
* **No sound**: the V53A and L7A1045 are not implemented.
* The 3D has not run on hardware.

`docs/MAME_KLUDGES.md` lists what is taken from MAME as behaviour and what is known not to be
right. `docs/HACKS.md` lists this core's own approximations. `docs/ROADMAP.md` is the plan and its
progress; `docs/LESSONS_LEARNED.md` is what it cost.

### Features

* DIP switches from the `.mra` (`DIP;` in the OSD): n/a, MAME lists none for the fight sets
* Inputs: wired (`HyperNG64.sv`), not tried on hardware
* CRT Adjust (H-Position, V-Shift, H-Size, V-Size): H-Position, V-Shift and H-Size, checked in `sim/crt_tb`; no V-Size; not tried on hardware
* HDMI scaling (integer scale, crop, crop offset): wired (`video_freak`), crop to 432 or 360 of the 448 lines; not tried on hardware
* HDMI rotation (orientation): dropped, for area the 3D needs (user decision); every set is horizontal
* Flip screen, HDMI and analog, from the OSD or the DIP (fake DIP where the game has none): done in simulation, from the OSD or the `.mra`'s fake DIP (setting both cancels); checked in `sim/sys_tb` against the unflipped frame turned 180 degrees
* HDMI-only options hidden under direct video: done
* Peripheral menus shown only for games that use them: n/a for the fight sets (no guns, wheels or rotary sticks)
* Rotary joysticks (Ikari Warriors controls, GRS keystroke mode), where used: n/a
* Light guns: mouse, analog stick and synthetic crosshair, where used: n/a
* Audio mix (Mono, None, 25%, 50%): not yet, there is no sound
* Hiscore saving (`hiscore.v`, with autosave): n/a, MAME's `hiscore.dat` has no HNG64 set
* NVRAM / EEPROM saved to the `.nvm` file: wired, saved when the OSD opens after the game wrote it; `sim/sys_tb` checks both directions, not tried on hardware
* Fast ROM loading via DDR: done, the HPS writes the set into DDR3 (`docs/MEMORY.md`); works on hardware
* Pause (with CPU suspended): wired, not tried on hardware
* Sound: not yet (Phase 4)
* Savestates (optional): not yet
* Cheats (optional): not yet

### Todo

- [ ] Find why the BIOS tests the dual-port RAM on hardware and MAME's does not, and boot a game
- [ ] Close timing at full speed (clk2x 125 MHz, CPU 93.75 MHz)
- [ ] The 3D on hardware, against MAME's frames
- [ ] Sound (Phase 4)

### Resource usage

Commit `41c854b`, revision `HyperNG64` (no probes), at full speed, on the DE10-nano's Cyclone V
5CSEBA6, speed grade 7; timing not met (clk2x -5.959 ns, CPU clock -1.803 ns):

| resource | used | available |
| --- | --- | --- |
| Logic (ALMs) | 40,591 | 41,910 |
| Block memory bits | 2,567,469 | 5,662,720 |
| RAM blocks | 387 | 553 |
| DSP blocks | 87 | 112 |
| PLLs | 3 | 6 |

ALMs are the resource to watch: the main CPU takes about 9,300 and the 3D about 10,500 (the first
full fit). Since that build the triangle setup has moved into the geometry engine's microcode and
the render buffer's banks into block RAM; the half-speed build with both (`117ea68`) used 35,925
ALMs, not comparable at a different clock.

## AI Attestation

This core is being developed with heavy use of a frontier coding assistant. Commits written with
it carry a `Co-Authored-By` trailer.

## Verification

Not PCB-validated. MAME is the accuracy reference, with its own acknowledged uncertainties noted
where they matter.

* Main CPU: the BIOS's first 199,998 instructions match MAME in PC and all 31 registers (`sim/boot_tb`)
* Whole board less the CPU, replaying MAME's boot: frames 400 and 800 pixel-exact and every compared read equal, also flipped (`sim/sys_tb`)
* 2D video: every captured layer, the sprites, the mixer and the whole block pixel-exact to the model of MAME's renderer on every capture of `sams64`, `fatfurwa` and `buriki` (`scripts/video_regress.sh`)
* 3D model (float, MAME's operations): 0 of 229,376 pixels different from MAME on `sams64` frames 500-652 and 2500/3500/5000, `buriki` 2500 and `fatfurwa` 2500/4000; in integers, frame 2500 differs from MAME by 69 pixels (`docs/phase3_3d.md`)
* 3D RTL: the geometry engine's 1,088,030 setup records of `sams64` 2500's trace identical to its simulator (`sim/geo_tb`); the rasteriser's buffer identical to the model on six captures (`sim/raster_tb`); engine, rasteriser and DDR3 arbiter together 0 of 262,144 pixels different (`sim/g3d_tb`)
* On hardware: the first 4,028 comparable I/O requests of `sams64`'s boot match MAME's in order and address (`scripts/compare_io_trace.py`); the 12 data differences are MAME's `0xDEADBEEF` video-register fill
* `.mra` files: rebuilt byte for byte against MAME's `ROM_START` region images (`scripts/build_mra.py`)

## Acknowledgements

- **Sorgelig** and the **MiSTer-devel team** for the
  [Template_MiSTer](https://github.com/MiSTer-devel/Template_MiSTer) framework and the SDRAM
  controller (`rtl/memory/sdram/`).
- The **MAMEdev team**: David Haywood, Angelo Salese, ElSemi and Andrew Gardner for `hng64`, and the
  device emulations that are this core's specification.
- The **MiSTer N64 core** ([N64_MiSTer](https://github.com/MiSTer-devel/N64_MiSTer)) for the VR4300 (`rtl/cpu/vr4300/`).
- **fayalalebrun** for [SpinalVoodoo](https://github.com/fayalalebrun/SpinalVoodoo)'s triangle setup and span walker (`rtl/3d/`).
- **rmonic79** for CRT Adjust, from [Arcade-Raiden_MiSTer](https://github.com/rmonic79/Arcade-Raiden_MiSTer) (`rtl/video/`).

## Layout

Standard [Template_MiSTer](https://github.com/MiSTer-devel/Template_MiSTer) structure:

| path | contents |
| - | - |
| `sys` | MiSTer framework, vendored from the template, never edited |
| `rtl` | core source; vendored modules carry a `PROVENANCE.md`; `rtl/3d/spinal` is the SpinalHDL source of the 3D's generated Verilog |
| `releases` | `.rbf` and `.mra` files |
| `docs` | roadmap, workflow, release process, kludges, hacks, lessons |
| `sim` | ModelSim and Verilator testbenches |
| `scripts` | build, deploy, capture and verification tooling |
| `debug` | reference captures from MAME used as ground truth (gitignored) |
| `roms` | your own MAME sets (gitignored, never committed) |

## License

GPL-3.0 (see `LICENSE`). Imported components keep their own licences; each vendored directory's
`PROVENANCE.md` has the detail, and every modified vendored file states the change in its header.
SpinalVoodoo has no licence yet; one has been asked of its author (`rtl/3d/PROVENANCE.md`).

Game ROMs contain copyrighted material and are not included. Obtaining them is your
responsibility.
