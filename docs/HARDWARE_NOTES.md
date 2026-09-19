# Hyper NeoGeo 64: hardware notes

Source: MAME `src/mame/snk/hng64*.cpp`, `hng64.h` at `E:/mame` commit 5ae594bafe9, and
`mame -listxml` from MAME 0.285. Everything here is MAME's model unless marked otherwise.

## Sets

| Set | Game | Board config | ROM total |
|---|---|---|---|
| `hng64` | BIOS (parent) | | 2 MB bios + 0.5 MB comm + iomcu + fpga |
| `roadedge` | Roads Edge / Round Trip RV (rev.B) | drive | 127 MB |
| `sams64` | Samurai Shodown 64 | fight | 183 MB |
| `xrally` | Xtreme Rally / Off Beat Racer! | drive | 131 MB |
| `bbust2` | Beast Busters: Second Nightmare | shoot | 155 MB |
| `sams64_2` | Samurai Shodown 64: Warriors Rage | fight | not listed; same family as `sams64` |
| `fatfurwa` | Fatal Fury: Wild Ambition (rev.A) | fight | 239 MB |
| `buriki` | Buriki One (rev.B) | fight | 215 MB |

All are `MACHINE_IMPERFECT_GRAPHICS | MACHINE_IMPERFECT_SOUND`; save states unsupported.

Per-game ROM regions (`fatfurwa`, the largest): `gameprg` 16 MB, `scrtile` 64 MB, `sprtile`
64 MB, `textures0..3` 4 x 16 MB, `verts` 12 MB, `l7a1045` 16 MB.

## CPUs and chips

| Tag | Part | MAME clock | Role |
|---|---|---|---|
| `maincpu` | NEC VR4300, big-endian, 64-bit MIPS III | 50 MHz | main program |
| `audiocpu` | NEC V53A (V30-compatible + DMAU/ICU/SCU) | 32 MHz | sound program, uploaded by main CPU |
| `l7a1045` | L7A1045 L6028 DSP-A | 33.8688 MHz | sample playback |
| `network` | Kawasaki KL5C80A12 (Z80-compatible) | 12.5 MHz | comms board |
| `iomcu` | Toshiba TMP87PH40AN (TLCS-870) | 8 MHz | inputs, lamps; 32 KB ROM dumped |
| | RTC-62423, 93C46-class EEPROM, NVRAM 16 KB | | |

The MAME clock for the VR4300 is MAME's setting; the board clock is unverified.

## Video

Display from `-listxml`: 512 x 448 visible, 768 x 528 total, 25 MHz pixel clock, 61.65 Hz.

Three generators, mixed:

- Sprites: sprite RAM `0x20000000-0x2000bfff`, regs `0x20010000`. Tiles from `sprtile`.
- Tilemaps: VRAM `0x20100000-0x2017ffff`, regs `0x20190000`. Tiles from `scrtile`.
- 3D: display list written at `0x20300000`, two frame buffers `0x30100000` and `0x30200000`
  (384 KB each), textures from `textures0..3`, vertices from `verts`. MAME:
  `hng64_3d.ipp`, 1541 lines.
- Palette `0x20200000` (16 KB); transition control `0x20208000` (fades/blends).

## Main CPU map (`main_map`, hng64.cpp:1182)

| Range | What |
|---|---|
| `0x00000000-0x00ffffff` | work RAM, 16 MB |
| `0x04000000-0x05ffffff` | `gameprg` ROM |
| `0x1f700000-0x1f7021c7` | system regs, IRQ controller, DMA, RTC, IO-MCU IRQ |
| `0x1f800000-0x1f803fff` | NVRAM |
| `0x1f808000-0x1f8087ff` | dual-port RAM to the IO MCU |
| `0x1fc00000-0x1fc7ffff` | BIOS ROM |
| `0x20000000-0x2030021b` | sprites, tilemaps, palette, 3D display list (above) |
| `0x30000000-0x3025ffff` | 3D frame buffer control and RAM |
| `0x60000000-0x603fffff` | sound RAM (V53A program uploaded here) |
| `0x68000000`, `0x6f000000` | main-to-sound comms, sound CPU enable |
| `0xc0000000-0xc0001007` | comms board shared RAM (`m_comhack` is a MAME hack) |

## Feasibility on the DE10-nano: open

Recorded before any design work because it decides whether a roadmap exists.

- **ROM does not fit SDRAM.** 127-239 MB per game against a 128 MB maximum SDRAM module. ROM
  would live in DDR3, which the HPS shares, with SDRAM for work RAM and hot data.
- **Main CPU.** A 64-bit MIPS VR4300. The only MiSTer implementation known to the author of
  these notes is in the N64 core; its licence, resource use and extractability are
  unverified.
- **3D.** A textured polygon renderer reading 64 MB of texture ROM and up to 24 MB of vertex
  ROM, rendering to two frame buffers, alongside two 2D layers. No RTL is known.
- **Sound.** V53A plus the L7A1045 DSP. No RTL known for either (V30 cores exist; the V53A
  peripherals do not, unverified).
- **IO MCU.** TLCS-870 core needed, or a behavioural stand-in for the IO MCU; no RTL known.
- **Reference quality.** MAME itself marks graphics and sound imperfect, so the reference is
  weaker than for the five prior cores.

### N64 core as a VR4300 source

`MiSTer-devel/N64_MiSTer` at adbf9b5, read in LICENSE, README, `N64.qsf`, `rtl/cpu.vhd`
entity, PLL settings only.

- Licence GPL-3.0: reusable in this GPL-3.0 core.
- `rtl/cpu.vhd` + `cpu_FPU`, `cpu_TLB_*`, `cpu_cop0`, `cpu_*cache`, `cpu_mul`, `divider`:
  a separate entity, VHDL.
- Its memory port is generic in part (`mem_request/rnw/address/req64/size/writeMask/
  dataWrite/dataRead/done`, 64-bit) and N64-specific in part (`rdram_granted2x`,
  `ddr3_DOUT*`: cache fills come straight off the N64's DDR3 RDRAM path; `ram_*`). An HNG64
  bus bridge would have to present that interface or the caches be re-plumbed.
- Clocks: `clk93` 93.75 MHz for the CPU pipeline, `clk1x` 62.5 MHz, `clk2x` 125 MHz. The
  project builds with `AGGRESSIVE PERFORMANCE` and router duplication on, so timing on the
  CPU is already tight.
- It carries N64 debug/cache switches (`DATACACHESLOW`, `RANDOMMISS`, ...) and savestate
  ports that would be tied off.
- Resource use: not measured. The repo has no fitter report, and the CPU's share of the N64
  core is unknown until it is synthesised on its own.

### HNG64 3D is more than a rasteriser

`hng64_3d.ipp` models camera transform (`setCameraTransformation`), projection
(`setCameraProjectionMatrix`), lighting (`setLighting`), polygon fetch from vertex ROM
(`recoverPolygonBlock`) and 4x4 float matrix products, then rasterises. On the N64 those
transforms run in RSP microcode; the RDP only rasterises. So the RDP is at most a source of
parts (texture fetch/filter, z-buffer, perspective correction), and hardware transform and
lighting would be new RTL. MAME models it in floating point; the real chip's number format is
unverified.

### Verdict so far

The N64 core fits VR4300 + RSP (vector unit, where the N64 does transform and lighting) +
RDP (textured rasteriser) + VI + framework in one 5CSEBA6. HNG64's main CPU, 3D geometry and
3D rasteriser are the same order of work. What HNG64 adds on top: sprite and tilemap
generators, the V53A, the L7A1045 DSP and the IO MCU.

Not shown to be feasible. Blocking unknowns, in order:

1. Headroom left by the N64 core, against the 5CSEBA6's 41,910 ALMs, 553 M10K and 112 DSP
   blocks. The repo has no fitter report. It enables `MISTER_DOWNSCALE_NN` and
   `MISTER_DISABLE_ALSA`, both framework resource savers, which suggests it is tight; not
   measured.
2. Whether HNG64's transform and lighting maps onto something RSP-sized. The RSP is a
   programmable vector unit; the HNG64 chip is fixed-function, possibly smaller.
3. DDR3 bandwidth: CPU cache fills, textures, vertices and 2D tile fetches all from DDR3.
