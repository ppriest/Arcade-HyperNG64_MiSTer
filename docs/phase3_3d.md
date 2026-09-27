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
| pixel | reciprocal of 1/w | 20 mantissa bits (Voodoo: about 16) |

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
