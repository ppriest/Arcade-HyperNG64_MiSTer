# Phase 3: the 3D

The plan is in `docs/ROADMAP.md` (Phase 3, and the 3D open items). This file is the working record:
the model, what it has been checked against, and the numbers the hardware design is taken from.

## The model

`scripts/render_3d.py` is MAME's 3D transcribed: `hng64_3d.ipp` (display-list commands, geometry,
lighting, culls, projection) and `devices/video/poly.h` (the frustum clipper and the triangle
rasteriser), in float32 operation by operation as MAME computes them. It replays the writes a
game makes to the display list and its registers, from the bus trace (`debug/<set>-sys`) or from a
capture's own write log (`scripts/mame_capture.py --wlog`, which logs them from boot), and the 2D
model (`scripts/render_model.py`) mixes its buffer in between the two tilemap priority halves.

MAME renders each upload as it is written, into one 512 x 512 buffer of `llll appp pppp pppp`
(light, blend, palette index) and a float depth buffer, cleared at vblank when tcram `0x50` bit 16
is set. A frame's buffer depends only on what follows the last clearing vblank (the clear also
resets the projection, camera and palette state), so the model draws nothing before it: a frame
takes seconds rather than a replay from boot.

Against MAME's screenshots, whole frame, 2D and 3D together:

| Frames | What | Pixels different |
|---|---|---|
| sams64 500, 566, 600, 601, 630, 652 | BIOS logo (601 shows 600's buffer) | 0 of 229,376 each |
| sams64 2500, 3500, 5000 | "How to play": two fighters, arena | 0 of 229,376 each |
| buriki 2500 | in game, 152 blended polygons | 0 of 229,376 |
| fatfurwa 2500, 4000 | in game (skyline, floor, 16 flat polygons; camera matrix); no 3D | 0 of 221,184 each |

fatfurwa shows 432 lines from raster line 16 (tcram 0x04/0x08, below) and swaps its sky and floor
tilemaps at line 244 by a video register write, which MAME draws in two parts; the model does the
same from the write log, which carries the beam's line with each write and the video registers.

What in MAME's 3D reads as a slip rather than a guess is in `docs/MAME_KLUDGES.md`, 3D; the model
copies all of it.

## What a frame asks for

`render_3d.py` prints per-frame statistics. sams64 in game (frames 2500-5000), one 3D frame; the
game uploads a display list every other video frame, so these are per 1/30 s:

| | per frame |
|---|---|
| display-list uploads | 26-29 |
| polygons submitted | 4,650-4,800 |
| back-face culled | 1,850-2,000 |
| drawn (visible after culls) | 2,770-2,800 |
| triangles rasterised | 2,650-2,680 |
| spans (triangle x scanline) | 19,400-23,400 |
| pixels tested (texel not transparent) | 140,000-190,000 |
| pixels written | 107,000-140,000 |
| textures | 8bpp about 2,500, 4bpp about 270 polygons; no flat, no blended |
| lighting | every polygon lit |
| clipped to 4 or 5 vertices | 6-60 |

Chunk types seen: `04 05 0e 0f 87 96 97 c7 d7`, all ones MAME decodes.

## Value ranges (`scripts/ranges_3d.py`, frames 600, 2500, 5000)

| Quantity | Range of magnitude |
|---|---|
| object matrix | Q1.15 inputs, up to 1.0 |
| projection matrix entries | 0.0026 to 2.45 |
| eye and clip coordinates | up to 0.41 |
| clip w after clipping | 0.020 to 0.41 |
| screen x, y | 0 to 512 |
| screen z | 0.53 to 0.66 |
| 1/w | 2.45 to 49 |
| u/w, v/w (page units) | up to 38 |
| light/w | up to 6,223 |
| dz/dx | down to 3.7e-10 |
| span length | 1 to 368 |

## Fixed point against MAME

`scripts/render_3d_fx.py` keeps the geometry in float and replaces the rasteriser with one in
integers: MAME's structure (scanline extents with `round_coordinate`, plane equations from the
three vertices, one pixel at a time), in SpinalVoodoo's formats: vertices 12.4, z as 20.12 of
z * 2^16, 1/w as 2.30 of (1/w) / 16, u/w and v/w as 14.18 of 64 u/w, light/w as 12.12 of
(light/w) / 16. Gradients are rounded to each parameter's format; the per-pixel divides are exact.

The buffer against the float model, frame 2500 (in game), by the vertex fraction bits:

| Vertex format | Coverage | Texel | Light only |
|---|---|---|---|
| 12.4 (Voodoo's) | 23 | 1,065 | 103 |
| 12.6 | 6 | 247 | 33 |
| 12.8 | 2 | 97 | 11 |
| 12.12 | 0 | 72 | 2 |
| 12.16 | 0 | 73 | 3 |

Texture-coordinate and 1/w precision make no difference (swept to 2^32): the vertex position is what
moves the texture plane. Of the 72 texel differences left at 12.12, 57 are pixels whose texel
coordinate in MAME is within 0.01 of a texel edge, where only 4% of all drawn pixels lie.

On the logo (frame 600), 6,292 of the 6,317 buffer differences are the light's 4 bits off by one.
Their light is constant across each polygon at a whole multiple of 16, so MAME's `rCorrect / 16`
lands on 7.9999 or 8.0000 by float rounding: 6,288 of those pixels are within 0.001 of the boundary,
as are 109,001 of the frame's 111,164 drawn pixels. MAME's value there is noise; any fixed-point
design gives one side consistently.

So far: **12.4 vertices are not enough; 8 or more fraction bits bring the in-game frames to within
about 100 pixels of MAME, and what is left is MAME's rounding at quantisation boundaries.**

### The geometry

`render_3d_fx.py --geometry` puts the geometry in fixed point too: exact products and sums, each
stage's result rounded (`GEO`). `scripts/sweep_geo_3d.py` sweeps one stage at a time, the rest
ideal; frame 2500's buffer against the float model, the rasteriser at 12.8, 110 differences with
all ideal (float64 geometry gives the same 110 as MAME's float32):

| Stage | Width | Differences at that width (fewer bits) |
|---|---|---|
| eye coordinates | 26 fraction bits | 106 (24: 120, 20: 329, 16: 4,594) |
| clip coordinates | 24 fraction bits | 112 (20: 238, 16: 2,637) |
| projection matrix | 20 fraction bits | 112 (16: 121, 12: 1,983) |
| 1/w | 20 mantissa bits | 109-112 (16: 136, 12: 683) |
| 1/length (normalise) | 16 mantissa bits | 109 (6-12: 128) |
| per-vertex light | 8 fraction bits | 112 (0: 410) |
| clipper interpolation | 12 fraction bits | 113 (8: 121) |

Eye and clip coordinates are small (to 0.41, w down to 0.02) and everything after divides by w,
so they need most of a 27-bit DSP operand. With all of these at once, against MAME's screenshots:

| Frame | Pixels different | 3D buffer against the float model |
|---|---|---|
| 600 (logo) | 2,639 | coverage 1, texel 0, light 6,024 (the boundary noise above) |
| 2500 | 91 | coverage 2, texel 103, light 10 |
| 3500 | 74 | coverage 0, texel 87, light 4 |
| 5000 | 96 | coverage 1, texel 110, light 7 |

### The geometry in integers (`scripts/geom_int.py`)

The stage widths above were measured with float64 between the roundings. `geom_int.py` is the same
geometry in integers only, the specification for its RTL and the model's default
(`--geometry int`; `float` for MAME's): inputs Q1.15 as the display list and vertex ROM hold them,
world Q23 (the packet scale exact), model-view Q30 exact, eye Q26, clip Q24, projection entries
from the packet with far rounded to Q30 and each entry one divide to Q20 (the exact rationals give
the same frames), the clipper's t Q12 by an exact divide, one
reciprocal of w a vertex (the pixel unit's table and Newton step; the gradients' 20-bit restoring
divide gives the same frames within 2 pixels) giving x, y, z, 1/w, u/w, v/w
and light/w in the rasteriser's formats, and the light through normals at Q16 and 1/length by a
table and one Newton step. MAME's clip plane w >= 1e-6 is w >= 17 at Q24.

Texture coordinates need Q23 through the clipper: at Q15, rounding each lerp costs 2 to 3 times
the differences (sams64 2500: 214). Exact per-vertex divides instead of the reciprocal, or MAME's
float32 projection instead of the exact one, change nothing (211, 214). Pixels differing from
MAME, rasteriser as above (gradients M = 20, pixel table T = 10, z 24 bits):

| Geometry | sams64 600 | 2500 | 3500 | 5000 | buriki 2500 | fatfurwa 2500 |
|---|---|---|---|---|---|---|
| float (MAME's) | 2,629 | 57 | 60 | 52 | 32 | 122 |
| float64 rounded at the stages | | 64 | 58 | 53 | 40 | 153 |
| integers, u and v Q15 in the clipper | | 214 | 203 | 139 | 74 | 376 |
| integers, u and v Q23 (the default) | 2,655 | 70 | 61 | 60 | 38 | 153 |

`debug/sheet_geoint_*.png`. The rasteriser bench passes on the dumps this geometry makes.

### Geometry RTL: proposal

Work a frame (`geom_int.py`'s counts): sams64 2500 submits 4,798 polygons (4,385 lit, 2,001 culled
at the back face, 2,789 drawn), fatfurwa 2500 1,448, buriki 2500 2,342; clipping adds a vertex to
2% of them. A lit polygon is about 140 multiply-adds (3x3 normal transforms and dots, the eye and
face vectors for the culls, eye and clip per vertex using the projection's seven non-zero entries,
the per-vertex outputs), three 22-step reciprocals and three 1/sqrt; a culled one stops after the
culls. One multiply-add a clock is about 0.7M clocks a frame, alongside the rasteriser.

Proposed: a small microcoded engine rather than a hard-wired state machine: one multiplier
(36 x 27 bits, two DSPs) into a 64-bit accumulator with a rounding shifter, a register file in
MLAB, the restoring divider (reciprocals, the clipper's t, the projection), the 1/sqrt table with
its Newton step on the multiplier, compare-and-branch, and a few hundred microcode words in M10K
written with a small Python assembler. The chunk formats (0x04, 0x05, 0x0F, 0x87, 0x97, ...), the
light and cull branches and the clipper's loops are then code, and a Python model of the engine
running the same microcode is checked against `geom_int.py` before the RTL is checked against it.
Around it: a command unit walking the display list at each upload (camera, light, scale and
scroll, projection, polygon blocks), and a streaming reader of the vertex ROM (an hng64_ddram
client, reads in flight, about 24,000 beats a frame).

**Decided (user):** the microcoded engine. For it the specification keeps every product within
36 x 36 bits (1/sqrt's Newton step and the light take an intermediate rounding) and rounds divides
half away from zero, as a magnitude divider does; a clearing vblank resets the projection to
identity, as MAME's `clear3d` does. The frames are unchanged.

### The geometry engine (`scripts/geo_engine.py`, `scripts/geo_ucode.py`)

The instruction set, a Python assembler and a functional simulator (raising on any operand over
36 bits or register over 48), and the microcode: `init`, `clear` and `upload` entries, the
display-list commands, polygon blocks and chunks, culls, lighting, the clipper and the per-vertex
outputs, the triangle fan. `python scripts/geo_engine.py <set> <frame>` runs it on every upload
beside `geom_int.IntMachine` and compares the triangles.

**The normals' 1/length.** Every transformed vertex normal in the captures has a length between
0.9999 and 1.0000 (unit normals, rotation matrices; the rest is Q15 rounding), and the light
vector's length is constant per game (1/32 on sams64, 1.0 on buriki). The normals' 1/sqrt is
therefore 1 - (n - 1)/2 when n is within 1/128 of 1.0, with the table and Newton step kept for
anything else (`geom_int.rsq_normal`). Against MAME it is the best of the three tried:

| Normals' 1/length | sams64 600 | 2500 | 3500 | 5000 | buriki 2500 |
|---|---|---|---|---|---|
| table and Newton step | 2,651 | 70 | 60 | 62 | 38 |
| 1 - (n - 1)/2 near 1.0 (the default) | 2,651 | 69 | 59 | 60 | 36 |
| 1 (not normalised) | 2,943 | 72 | 65 | 64 | 48 |

**Speed.** The simulator estimates clocks for the planned pipeline: one instruction a clock; a
taken branch 2 more; stores execute at the accumulator's stage, so only an instruction using a
store's result in the next slot waits 1; indexed register access 1 more; a divide its quotient
bits; a vertex output record is read by an output streamer beside the engine. sams64 2500's
frame, the heaviest capture (4,798 polygons, 2,678 triangles):

| Microcode | Instructions | Clocks (estimate) |
|---|---|---|
| first version | 2,424,410 | |
| constant eye w, sparse projection, straight-line outputs, sign-extending reads | 1,919,288 | |
| linear 1/length for normals | 1,858,784 | |
| strip chunks read the previous polygon in place | 1,759,769 | 2,270,586 (before the pipeline changes) |
| stores at the accumulator stage, output streamer, polygons by call, fan unrolled | 1,700,205 | 2,013,653 |
| the usual path falls through (branch-free flags, per-block scale, palette and scroll) | 1,627,970 | 1,797,720 |

| the clipper as a loop over planes (1,395 words, 10 M10K rather than 20), EMIT's copy counted | 1,562,720 | 1,776,198 |
| the triangle setup (the old gradient unit) in microcode, for area (1,687 words) | 2,021,319 | 2,461,922 |

2.46M clocks; the game renders a 3D frame every other video frame, 4.17M clk2x clocks. About
250 of them a triangle are the setup: the sort, 21 indexed loads, 22 products, the reciprocal's
divide and ten gradients.

**The setup in microcode.** The rasteriser's gradient unit (1,429 ALMs and 10 DSP in the first
full fit) is now the engine's `setup` routine, which EMIT follows with the setup record, 22
words (`geo_engine.setup_record` is the definition; the same arithmetic as before, bit for bit:
`raster_tb` renders sams64 600 and 2500 identically from it). The numerators reach about 64 bits and
their products with the reciprocal about 86, past the multiplier and the accumulator, so each
numerator is split at bit 35 into two products; for det's top bit up to 26 their sum n r fits
the accumulator (under 2^70 for gradients under 2^35), above it the sum is taken as
floor(n r / 2^35), which rounds the same. The simulator stops if a capture breaks either bound.

**The accumulator is 72 bits** (96 before): the widest value measured is 58 bits (sams64 3500).
The simulator checks every accumulator value, and every shifted operand on its way in, against
72 bits; the divide compares the remainder shifted down, so nothing wider is formed.

### The engine RTL (`rtl/3d/hng64_geo.sv`)

Fetch, decode with the register reads (two copies of a 512 x 48 register file, a third for
indexed reads and EMIT's), execute (the ALU, branches, the multiplier's operands) and a fourth
stage for the accumulator, the stores and every register write; forwarding from the last two;
the microcode, tables and entry points loaded from `scripts/geo_ucode.py --export`. A vertex ROM
streamer reads ahead through an hng64_ddram client port; EMIT reads the three vertex records out
and offers the triangle in the rasteriser's input format.

`sim/geo_tb` replays a capture's events (`geo_engine.py --dump`: every clear and upload of the
trace, with the display list and wrap table, and the triangles the simulator emits) and compares
every triangle. sams64 600, 148 events: all 8,367 triangles identical, with the vertex ROM at
latency 1, at 60 with 20% refused and at 150 with 50% refused with the output stalled. Its
clocks at latency 60 with 20% refused: 9,641,327 against the simulator's estimate of 9,411,445
(taken branches are two clocks in both).
sams64 2500, 12,576 events (every upload of its trace): all 1,089,291 triangles identical,
713,012,535 clocks against the estimate's 687,452,179 (latency 60, 20% refused). With the setup in
microcode: all 1,088,030 setup records identical (triangles with a zero determinant are no longer
emitted), 983,993,100 clocks against 966,832,655; sams64 600: 11,733,205 against 11,570,395.

### First standalone fit of the 3D (Quartus 17, 5CSEBA6U23I7, a scratch project)

`hng64_raster` and `hng64_geo` alone, every port a virtual pin, clocked at 125 MHz: 12,536 ALMs
(the virtual pins count), 13,462 registers, 365,564 block memory bits, 27 DSP. Setup slack
-9.692 ns: about 56 MHz. Worst slack into each module, and synthesis's LUT and register counts:

| Module | Slack at 8 ns | LUTs | Registers | DSP | Worst path |
|---|---|---|---|---|---|
| PixelUnit | -9.69 | 1,017 | 1,380 | 10 | the texel product into shift, wrap and address in one stage |
| GeoEngine | -8.50 | 4,884 | 1,570 | 3 | forwarding, then the ALU (NORM, variable shifts) |
| Gradients | -7.70 | 2,950 | 2,832 | 10 | the vertex sort's compares and muxes in one clock |
| SpanWalker | -5.29 | 2,634 | 2,237 | 0 | the next row's step, then its step left, chained |
| RenderBuf | -5.26 | 2,174 | 2,688 | 0 | the compare stage into the line banks |
| TriangleSetup | -5.02 | 1,351 | 2,081 | 4 | the bounding box and offsets in one clock |
| SpanPixels, TexCache | -3.85, -3.71 | 370 | 740 | 0 | ready chained combinationally through the pixel pipeline |

Both need work: pipelining that changes no result, and area (the gradients computed by the
engine, the span walker's parameters out of its five cursors, a narrower accumulator, wide
register buffers into RAM).

### The per-pixel divide and the depth

Texel = (u/w) x recip(1/w), the reciprocal rounded to a number of mantissa bits (`PIX_RCP`), against
the exact divide's 110 on frame 2500: 8 bits 23,942; 12 bits 2,049; 14 bits 573; 16 bits 195;
20 bits 109. SpinalVoodoo's TMU reciprocal is a 256-entry table interpolated linearly to 17 bits
(`Tmu.scala`, `recipTable`), about the 16-bit case: it would need widening, for example one Newton
step.

Depth, z's fraction bits (the model's default is 28, Voodoo's 20.12 of z x 2^16), frames 2500 and
5000: 16 bits 478 and 470; 20 bits 145 and 121; 24 bits 109 and 108; 28 bits 110 and 107. A
24-bit depth buffer: 512 x 512 x 24 bits, 768 KB.

### Widths so far

| Where | What | Width |
|---|---|---|
| geometry | eye coordinates | 26 fraction bits (to 0.41) |
| | clip coordinates | 24 fraction bits |
| | projection matrix | 20 fraction bits (to 2.45) |
| | 1/w | 20 mantissa bits |
| | normalise, light, clipper | 16 mantissa, 8, 12 fraction bits |
| rasteriser | vertices | 12.12 (Voodoo: 12.4, too coarse); fatfurwa 2500: 327 at 12.8, 129 at 12.12, 126 at 12.16 |
| | z | 24 fraction bits |
| | 1/w, u/w, v/w, light/w | Voodoo's formats with a 1/16 scale; wider made no difference |
| setup | reciprocal of the plane determinant, one a triangle | 20 mantissa bits (below) |
| pixel | reciprocal of 1/w | a 10-bit table and one Newton step, 21 fraction bits (below) |

At these widths the in-game frames are within about 100 of 229,376 pixels of MAME, the difference
concentrated on texel edges where MAME's own float rounding decides.

## SpinalVoodoo against HNG64

Formats (SpinalVoodoo `Config.scala`) against the ranges above:

| Voodoo | HNG64 fit |
|---|---|
| vertex 12.4 | too coarse (above); a config value |
| z 20.12 | fits with z * 2^16: 28 bits over the 0.53-0.66 range |
| w 2.30 | 1/w reaches 49: needs a 1/16 scale |
| s, t 14.18 | fits with the same scale, in texels |
| colour 12.12, affine | HNG64's light is interpolated perspective-correct in MAME; affine would differ |
| TMU: 256 x 256 RGB textures | HNG64: 1024-wide paletted pages, 4 or 8 bpp, sub-page wrap masks |
| pixel pipeline: RGB colour combine | HNG64 writes palette index, blend and light to a buffer the mixer reads |

The rasteriser and triangle setup map with format changes; the texel and pixel stages do not.

## Area

The first full fit (stp revision, `94df023`, before the sprite engine's z-buffer moved to MLABs):

| Block | ALMs | M10K | DSP |
|---|---|---|---|
| whole design | 35,048 of 41,910 | 345 of 553 | 43 of 112 |
| MiSTer framework (`ascal` 1,957, `audio_out` 890, the rest) | about 6,900 | 56 | 33 |
| VR4300 (`hng64_cpu`) | 8,296 | 26 | 9 |
| 2D video (`hng64_video`: four tilemaps, sprites, mixer) | 13,248 | 29 | 0 |
| IO MCU | 2,129 | 20 | 0 |
| sprite list and palette RAMs (`hng64_vbus`), main-board I/O, the rest | about 3,100 | 209 | 0 |

Left for the 3D: 6,862 ALMs, 208 M10K, 69 DSP.

An estimate of the 3D pipeline, block by block, unverified until something is synthesised:

| Block | ALMs, estimate | Notes |
|---|---|---|
| display list, command decode, vertex fetch from `verts` (DDR3) | 1,000 | |
| geometry: matrix x vector, normalise, culls, clipper, projection | 2,000-3,000 | sequential over a few DSPs; widths above |
| triangle setup: plane gradients (one divide a triangle) | 1,500 | |
| rasteriser: spans and seven parameter iterators, 32-48 bits | 1,500 | |
| per pixel: reciprocal (table and a Newton step), texel address, 4/8 bpp decode, light, depth test | 2,500-3,000 | DSPs for the reciprocal and the multiplies |
| texture cache, frame and depth buffer traffic, read-out to the mixer | 1,500 | M10K for the cache |
| total | 10,000-11,500 | against 6,862 free |

So the 3D does not fit beside Phase 2 as built. Where area could come from, largest first, none
yet measured: the 2D video's 13,248 (the sprite engine's registers have already gone to MLABs; the
mixer is 5,200 ALUTs of it; four tilemap engines run in parallel for throughput); the framework's
options (`MISTER_SMALL_VBUF`, `MISTER_DOWNSCALE_NN` reduce `ascal`); dropping HDMI rotation; and the
3D's own choices (affine rather than perspective-correct light, a smaller reciprocal).

## Proposed architecture (for approval)

Blocks, in the order a display-list upload flows through them:

1. **Command unit.** On `dl_upload`, walks the 16 packets of the display-list RAM (`hng64_io`'s
   `dl`) as `command3d` does: state packets (camera, projection, lighting, flags) into registers,
   polygon packets onward. The projection matrix's divides are once a packet: a small sequential
   divider.
2. **Geometry.** A sequential datapath over a few 27x27 DSPs at the widths above: vertex fetch from
   `verts` (DDR3, a `hng64_ddram` client), 4x4 matrix x vector, lighting (normalise by a 1/sqrt
   table and a Newton step), the culls, the clipper (six planes, rare), 1/w and the window
   transform. Polygons per 3D frame in game: 4,650-4,800 submitted, 2,800 drawn.
3. **Triangle setup and rasteriser.** Plane gradients (one reciprocal a triangle), then spans
   with seven parameter iterators, MAME's extents (`round_coordinate`). SpinalVoodoo's
   `TriangleSetup` and `Rasterizer`, with its formats widened (vertices 12.12, z 24 bits, w scaled
   by 1/16), or our own on the same plan.
4. **Texture and pixel.** Per pixel: 1/(1/w) to 20 bits (table and a Newton step), the texel
   address in HNG64's 1024-wide pages (4 or 8 bpp, sub-page wrap masks, scroll), a texture cache
   in M10K over `textures0` in DDR3, the 4-bit light, the depth test, the write. Our own:
   SpinalVoodoo's TMU and pixel pipeline do not fit (above).
5. **Render buffer**, 512 x 512: 16 bits of `llll appp pppp pppp` and 24 bits of depth.
6. **Display.** A line of the buffer read into a line buffer ahead of the mixer, which takes it
   as a sixth contributor between the two tilemap priority halves; the 3D palette (16 brightness
   copies, fade 0) is computed from the one palette as the mixer reads it, not stored.

Decisions this needs:

- **Where the render buffer lives.** Per 3D frame in game about 190,000 depth reads and 140,000
  depth and colour writes (1.5 MB), a clear (1.5 MB at 32 bits a pixel), and 27.5 MB/s of display
  read-out: about 120 MB/s at 30 renders a second. SDRAM (16 bits at 125 MHz, 250 MB/s peak) is
  shared with the CPU's main RAM and tile VRAM; DDR3 has the headroom (docs/MEMORY.md: the video's
  reads are 6% of it) if the pixel traffic goes in bursts along spans. Proposed: **DDR3**, with the
  clear replaced by a frame tag in the depth word (a pixel whose tag is old reads as cleared).
- **One buffer or two.** MAME renders straight into the one buffer the screen shows. Hardware that
  takes milliseconds to render would tear against the display unless it renders into a second
  buffer and swaps at the clearing vblank, which puts the 3D one frame behind the 2D relative to
  MAME. Proposed: **two buffers**, logged in HACKS.
- **How much of SpinalVoodoo.** Proposed: triangle setup and rasteriser only, widened; the rest
  ours.

**Decided (user):** the render buffer in DDR3, with a frame tag for the clear; two buffers,
swapped at the clearing vblank (the 3D one frame behind the 2D against MAME, for HACKS when built);
SpinalVoodoo's triangle setup and rasteriser, widened, and the rest ours.

Verification as for the 2D: the fixed-point model (`render_3d_fx.py`) becomes the bit-exact
specification of each block, and each block's RTL is checked against it in Verilator on the
captured frames before it is joined to the next.

### SpinalVoodoo's coverage against MAME's

`render_3d_fx.py --coverage edge` (the default) draws a pixel when its centre gives all three edge
functions >= 0, with the top-left rule and the row range of SpinalVoodoo's `TriangleSetup` /
`SpanWalker`; `--coverage mame` keeps poly.h's `round_coordinate` extents. Both test the pixel
centre against the edges and differ only when a centre lies exactly on an edge. On sams64 600,
2500, 3500, 5000, buriki 2500 and fatfurwa 2500 every triangle's spans are identical in the two
(98,060 spans; `debug/sheet_edge_*.png`), so the frame counts above stand. The start of each span
moves from vertex A to the centre of A's pixel and then by whole pixels, as SpinalVoodoo does; the
whole-pixel steps are multiples of one vertex unit, so the values match MAME's per-span
computation exactly.

## The gradients

The plane gradients were an exact division in the model. The setup does one reciprocal of the
determinant a triangle (`render_3d_fx.py --grad-rcp M`, `_grad_rcp`): |det| truncated to its top
M + 1 bits, a restoring divide into 2^(2M+1), then each numerator times it, rounded. Pixels
differing from MAME:

| M | sams64 600 | 2500 | 3500 | 5000 | buriki 2500 | fatfurwa 2500 |
|---|---|---|---|---|---|---|
| exact | 2,623 | 57 | 58 | 53 | 31 | 129 |
| 12 | 2,617 | 124 | 114 | 94 | 78 | 717 |
| 16 | 2,623 | 60 | 63 | 53 | 34 | 132 |
| 20 | 2,623 | 56 | 60 | 53 | 31 | 128 |
| 24 | 2,623 | 57 | 58 | 53 | 31 | 128 |
| 28 | 2,623 | 57 | 58 | 53 | 31 | 129 |

20 bits, within 2 pixels of the exact divide on each frame; the model's default
(`debug/sheet_grad20_*.png`). Determinants reach 42 bits on these frames.

## The per-pixel reciprocal

The texel and the light divide u/w, v/w and light/w by 1/w at every pixel. The pixel unit takes
the reciprocal of 1/w by a table and one Newton step (`render_3d_fx.py --pix-table T`,
`rcp_newton`): 1/w's top 21 bits, a table of 2^T entries indexed by the T bits after the leading
one, y1 = y0 (2 - wn y0) to 21 fraction bits, then each dividend times y1, truncated toward zero
as MAME's `(int)`. Its largest relative error over the mantissa range: T = 7 2^-15.6, 8 2^-17.4,
9 2^-19.1, 10 2^-19.9. Pixels differing from MAME (gradients at M = 20):

| T | sams64 600 | 2500 | 3500 | 5000 | buriki 2500 | fatfurwa 2500 |
|---|---|---|---|---|---|---|
| exact divide | 2,623 | 56 | 60 | 53 | 31 | 128 |
| 7 | 2,609 | 105 | 82 | 78 | 84 | 415 |
| 8 | 2,633 | 70 | 64 | 55 | 45 | 170 |
| 9 | 2,656 | 58 | 62 | 51 | 34 | 134 |
| 10 | 2,627 | 57 | 60 | 52 | 32 | 122 |

T = 10, within 6 of the exact divide on each frame: 1,024 entries of 12 bits, two M10Ks
(`debug/sheet_pix10_*.png`). The model's default. The sub-page wrap exponents seen are at most 4.

## DDR3 traffic (`scripts/cache_3d.py`)

`render_3d_fx.py --dump` records each capture's fragments in the rasteriser's order: texel byte
address, buffer pixel, drawn (pen not 0), written (depth test passed against the buffer before the
span). `cache_3d.py` replays them through cache models. The DDRAM port is 64 bits a clock at
clk2x: 2,083,333 data clocks in a 60 Hz frame. The video already uses about 21% of it
(docs/MEMORY.md: 208 MB/s), before the CPU's fills and any burst overhead.

Texture cache misses (textures0 as the ROM lays it out, 1,024-byte rows):

| Capture | Fragments | 8 KB, 32 B lines | 16 KB, 32 B | blocked 4 x 8, 32 B, 8 KB | blocked 8 x 8, 64 B, 8 KB |
|---|---|---|---|---|---|
| sams64 2500 | 189,355 | 26,303 | 22,098 | 16,541 | 14,314 |
| sams64 5000 | 172,111 | 37,070 | | 19,601 | 17,174 |
| buriki 2500 | 126,166 | 34,420 | | 19,352 | 18,397 |
| fatfurwa 2500 | 439,009 | 149,554 | 126,327 | 49,929 | 44,519 |

Blocked: the texture image reordered once at start-up so a line holds a W x H block of bytes
rather than a strip of one row. The render buffer's misses do not depend on the cache's size
(about one a span): it streams.

Port data clocks a frame, textures blocked 4 x 8 in 32-byte lines, 8 KB:

| Capture | Immediate: depth plane (32 bits) and colour plane (16) in DDR3, display 2 B a pixel | Tiled 64 x 64: depth on chip, triangles binned in DDR3 (128 B each, read once a tile), colour written once |
|---|---|---|
| sams64 600 | 15% | 5% |
| sams64 2500 | 34% | 12% |
| sams64 3500 | 30% | 12% |
| sams64 5000 | 35% | 12% |
| buriki 2500 | 28% | 9% |
| fatfurwa 2500 | 63% | 17% |

One 64-bit word a pixel instead of two planes costs 7 to 11 points more (display reads 8 B a
pixel). A triangle touches 1.2 to 2.0 tiles of 64 x 64. Unmeasured: DDR3's efficiency on these
bursts, and how often a frame is as heavy as fatfurwa 2500.

**Decided (user):** immediate, depth and colour planes in DDR3; textures blocked 4 x 8 at
start-up. Tiled would put the 3D a second frame behind the 2D (a tile renders only once the whole
frame is binned).

## Rasteriser RTL

`rtl/3d/hng64_raster.v`, generated from `rtl/3d/spinal/` (SpinalHDL): our gradient unit
(`Gradients.scala`, the model's `_grad_rcp`, about 50 clocks a triangle), SpinalVoodoo's triangle
setup, span walker and span rasteriser at HNG64's widths (`rtl/3d/PROVENANCE.md`), then our pixel
unit (`Pixel.scala`, six stages, one pixel a clock). In: a triangle, three vertices 12.12 in any
order with five parameters each, and 67 bits of texture and palette fields carried through. Out:
one fragment a clock at most: position, z, the texel's byte address and nibble, the light, the
colour fields.

Widths (`RasterConfig`), from the dumped frames' largest values: parameters 30, 34, 24, 32, 32 bits
(z, 1/w, light/w, u/w, v/w; largest seen 29, 33, 22, 31, 30); gradients 12 bits more into the
setup, whose `>> 12` needs them; vertices 24 bits (largest seen 23); edge values 51 bits.

`sim/raster_tb` feeds it the triangles `render_3d_fx.py --dump` writes (`raster.txt` in the capture),
reads each fragment's texel from the ROM image, does the colour and depth test in C++ as the model
does, and compares the finished 3D buffer with the model's (`raster_color.bin`). Earlier, before the
pixel unit, it compared every pixel's position and parameters with the model's spans; both passed
on the same captures. Gradients at M = 20, per-pixel table T = 10:

| Capture | Triangles | Fragments | Clocks | 3D buffer |
|---|---|---|---|---|
| sams64 600 | 499 | 124,217 | 224,113 | identical |
| sams64 2500 | 2,644 | 189,355 | 489,653 | identical |
| sams64 3500 | 2,676 | 139,788 | 428,342 | identical |
| sams64 5000 | 2,675 | 172,111 | 510,212 | identical |
| buriki 2500 | 818 | 126,166 | 333,273 | identical |
| fatfurwa 2500 | 867 | 439,009 | 944,443 | identical (and with the output stalled) |

1.8 to 3.1 clocks a pixel, with the output never stalled: the walker's search of the pixels
outside each span, and of rows above the buffer, costs the rest. Before the RecoverLeft fix
(PROVENANCE.md) 5 triangles each drew one pixel more than the model.

### The texture cache

`TexCache.scala`: 8 KB direct mapped, 32-byte lines over the blocked texture copy, prefetching
(tags checked and misses requested on entry, fragments waiting in a 128-deep FIFO, each fill
written at its fragment's turn; Igehy, Eldridge and Proudfoot 1998). Its reads go out as
hng64_ddram's client port, four 8-byte reads a line. The bench serves them from a model of that
port (replies in order, a set latency, a share of requests refused), checks every texel against
the ROM, and the 3D buffer against the model's as before:

| Capture | Texture reads | Clocks: no cache | latency 60, 20% refused | latency 150, 50% refused |
|---|---|---|---|---|
| sams64 600 | 2,792 | 224,113 | 224,267 | |
| sams64 2500 | 66,164 | 489,653 | 492,357 | 504,028 |
| sams64 3500 | 70,760 | 428,342 | 435,563 | |
| sams64 5000 | 78,404 | 510,212 | 516,192 | |
| buriki 2500 | 77,408 | 333,273 | 339,340 | |
| fatfurwa 2500 | 199,716 | 944,443 | 1,038,764 | 1,097,276 |

Every texel right and every buffer identical, also with the output stalled (fatfurwa, latency
100). The reads are four a line missed, matching `cache_3d.py`'s count for the same layout.

### The render buffer

`RenderBuf.scala`: one depth plane (a 32-bit word a pixel: the frame tag in the top 8 bits, z's
top 24 below) and a colour plane (16 bits a pixel) per buffer, in DDR3. A word whose tag is not
the frame's reads as cleared; each frame first rewrites 1/128 of the plane with a tag 128 away,
so no word keeps its tag until the tags come round (256 frames). The colour plane is cleared at
the frame's start (65,536 beats; the display reads colour alone). The depth cache is 1 KB, 2-way,
64-byte lines, write-back and prefetching: tags in registers checked at entry, lines gathered
whole as they arrive and filled in one clock at their fragment's turn, dirty victims drained
behind, and a line not read again until its write-back has left for DDR3. Colour goes through a
one-line write combiner.

Keeping 24 bits of z changes at most 2 pixels against MAME on the six frames (`--z-drop`, 4, the
default; 8 bits dropped, 20 kept, is still within 3): `debug/sheet_z24_*.png`.

`sim/raster_tb` now serves every DDR3 port (texture and depth reads, writes) from one memory
image and renders each frame twice: over noise with the whole depth plane scrubbed (tag 1), then
into the other colour plane over the first frame's depth (tag 2). Both colour planes match the
model's 3D buffer on all six captures, at latency 60 with 20% refused and at 150 with 50%.
Clocks for the second, ordinary frame (latency 60, 20% refused; 2,083,333 in a 60 Hz frame):

| Capture | Texture reads | Depth reads | Writes | Clocks | latency 150, 50% refused |
|---|---|---|---|---|---|
| sams64 600 | 2,792 | 99,200 | 192,787 | 387,291 | |
| sams64 2500 | 66,148 | 248,416 | 296,294 | 697,225 | 1,073,849 |
| sams64 3500 | 70,756 | 211,296 | 254,015 | 608,317 | |
| sams64 5000 | 78,404 | 256,040 | 297,529 | 711,122 | |
| buriki 2500 | 77,380 | 189,808 | 243,123 | 515,881 | |
| fatfurwa 2500 | 199,696 | 440,512 | 507,281 | 1,303,370 | 1,790,468 |

The bench's ports each take one request a clock with no shared limit, so these do not include the
video's and CPU's share of the DDRAM port.

### The texture blocking copy

`TexBlock.scala` copies textures0 into its blocked layout at start-up, from the ROM image the HPS
loaded into a separate region (so a reset without a reload blocks again from an intact source):
eight 1,024-byte rows read into two banks (even and odd rows, 8 M10K), then written out as 256
blocks of four beats. It borrows the texture read port and the writer while the 3D is idle.
`sim/raster_tb` runs it first and compares the result byte for byte with its own blocking: 16 MB,
2,097,152 reads and as many writes, 5,372,447 clocks at latency 60 with 20% refused (43 ms at
125 MHz), identical; the frames then render from the RTL's copy.

## In the core

`rtl/hng64_3d.sv` joins the engine and the rasteriser to the rest, all on clk2x except the CPU side:

- **Uploads are queued.** MAME raises interrupt 3 5,120 CPU cycles after an upload whatever the
  work; the engine takes longer for most uploads. Each upload copies the display list and the
  wrap bytes (129 clk1x clocks) into one of 32 slots (about 16 M10K, unsynthesised), and the engine takes them in
  order. A clearing vblank (tcram 0x50 bit 16 at the window's end, MAME's `screen_vblank`) is an
  event in the same queue. With one slot left interrupt 3 is held back (HACKS).
- **Frames.** Start-up: the blocking copy, the engine's init entry, then a frame into colour
  plane 0 with the whole depth plane scrubbed. A clearing vblank drains the rasteriser, finishes
  the render buffer, and offers the plane to the display; once the display has taken it (in the
  next vblank, before its first line is read) the next frame starts in the other plane and the
  engine runs its clear entry. The 3D is shown one frame behind MAME's (HACKS).
- **Triangles.** The engine's triangles reach the rasteriser through a 256-record FIFO (788
  bits, 20 M10K): handed over one at a time, each side waited on the other (fatfurwa f1600 in
  g3d_tb: 2.01 M clk3d clocks a frame, 1.49 M with the FIFO). The flush waits for it to empty.
- **DDR3.** Three read clients (vertices, textures, depth) and the writer on `hng64_ddram`, which
  now has eight clients; the buffers are at fixed offsets above every set's image
  (`docs/MEMORY.md`).
- **Display.** `rtl/video/hng64_fb3d.sv` is a sixth line engine in `hng64_video`: a pass reads
  the displayed plane's row for the line (128 reads) into a line buffer, the row from a table of
  MAME's vertical stretch rebuilt each frame by a restoring divide and an accumulator; the mixer
  reads it with `fbscroll`'s x offset. The mixer takes it as a sixth contributor after step
  0x10's sprite group, with MAME's 3D palette computed on the way: the modified entry, the
  light nibble << 2 added on each channel, fade 0, and half-alpha for blended pixels. Six
  contributors make a pixel six clocks, about 3,080 of the line's 3,840.

### Timing

The first full fit (`5c7c0da`): 39,693 ALMs (95%), 387 of 553 M10K, 87 of 112 DSP. clk2x
-9.588 ns (20,000+ endpoints failing), clk93 -1.773 (the CPU, accepted), clk1x -0.087. By module
pair (`quartus_sta`, every failing clk2x endpoint):

| Worst | Endpoints | Path | Change |
|---|---|---|---|
| -9.59 | 37 | geometry engine decode, through `hng64_ddram`'s address mux, into the HPS DDRAM port | the arbiter's issue is a register, its grant a registered round robin, each client's ready from its own request only |
| -7.4 | 3,800+ | geometry engine into the tilemap and sprite engines, the BIOS copy, main memory | the same: they met through `hng64_ddram`'s ready |
| -7.45 | 2,131 | geometry engine: W's register compare, the forwarding mux and the ALU into `mVal` | forwarding selects computed a clock early into registers |
| -6.46 | | a tilemap's ROM read, through `hng64_ddram`'s `read_ok` and `DDRAM_RD`, back to the tilemap | the arbiter change |
| -5.55 | 2,908 | RenderBuf: the OR of the combiner's 64 byte enables, through `comb.ready` and `go`, into the depth banks' read address | the flag is a register |
| -5.30 | 206 | mixer: two region modifiers in series in one stage | one modifier a stage |

Each change is behaviour-identical: `geo_tb` on sams64 600 counts the same 9,641,327 clocks
before and after, and every bench the changes touch passes.

`sim/g3d_tb` runs `hng64_3d` behind `hng64_ddram` with a model of the DDRAM port, from a
capture's display-list events (`geo_events.txt`, from the second-last clearing vblank on, then
one more to finish the frame), and compares the plane the display is given with the model's 3D
buffer. sams64 2500, 58 uploads and three clearing vblanks, latency 60 with 20% busy: 0 of
262,144 pixels differ, 10.0M clocks (texture blocking and the first frame's full scrub
included). The reference must come from the same model version as the events: a
`raster_color.bin` dumped before the geometry spec's last two commits gave 3 pixels off by one
in the light nibble. `scripts/video_regress.sh` runs it, and passes with the mixer at six
contributors. Not yet: area and Fmax.

