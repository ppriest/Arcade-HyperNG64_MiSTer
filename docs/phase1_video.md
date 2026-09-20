# Phase 1: the 2D video, and the software model

`scripts/render_model.py` is MAME's 2D video transcribed (`hng64_v.cpp`, `hng64_sprite.ipp`): the
palette, the four tilemaps and the sprite list, from a `scripts/mame_capture.py` capture. It is
the reference the RTL is checked against, and it is only as right as MAME.

```
python scripts/mame_capture.py sams64 --frame 1200 --name attract
python scripts/render_model.py sams64 attract --diff
```

## Agreement with MAME

Pixel-exact on every 2D-only frame found, 512 x 448 (or 512 x 432):

| Capture | Differing pixels |
|---|---|
| `sams64` 400, 800, 1200 (title, attract text) | 0 |
| `buriki` 200 | 0 |
| `fatfurwa` 150, 160 | 0 |
| `xrally` 540 | 0 |
| every other capture | 3D scenes: the model has no 3D layer |

Frames with 3D differ wherever MAME's polygon buffer covers the 2D layers, which is most of the
screen in those scenes. Phase 1 checks only 2D-only frames; the 3D layer is Phase 3.

**2D-only frames are scarce, and that limits what can be claimed.** `scripts/scan_video.py`
samples every video register every frame, so a frame using a given feature is found rather than
guessed; but the 3D layer is on in almost every frame after the first hundred, and MAME offers no
way to turn it off. Four features are therefore transcribed and matched between model and RTL,
but not confirmed against MAME: sprite blending, the sprite-group mixing order, the fade-palette
choice and the `tcram` blanking bit. They are in `docs/MAME_KLUDGES.md` with what would settle
each. `xrally` and `roadedge` are out of the core's first scope but drive the same chip, and
`xrally` frame 540 is the only 2D-only frame found anywhere with additive blending on-screen.

## What the model covers

- **Palette** (`hng64_v.cpp:1279-1375`): `paletteram` 8:8:8, the eight per-region tcram
  modifiers, and the two fade palettes a tilemap can select (`tileregs` bit 7 chooses a fade
  palette, bit 5 which one).
- **Tilemaps** (`:49-685`): four maps, 8x8 or 16x16 tiles, 4 or 8 bpp, per-tile flip, the
  auto-animation mask, wrap, mosaic, all three scroll-register layouts (plain, per line, and the
  rotating "alt" one), and the priority order (0x1f down to 0x10, then the 3D layer, then 0x0f
  down to 0x00; later layers overwrite).
- **Sprites** (`hng64_sprite.ipp`): the 1,536-entry list, chaining, zoom, flip, mosaic,
  checkerboard, the z-buffer and both z-sort senses, 4 and 8 bpp, and the group/blend bits.

Not covered yet: the 3D layer, split-screen scroll modes, additive and alpha blending of
tilemaps and sprites, the `m_screen_dis` and screen-size registers.

## Two things a reader would get wrong

- **The tile ROM is reordered before use.** `init_reorder_gfx` (`hng64.cpp:1814`) interleaves the
  halves of `scrtile` in 32-byte units, because two 4bpp tiles share each 8bpp tile. Decoding the
  region as loaded produces plausible-looking nonsense; `reorder_scrtile()` in the model does it.
  `sprtile` is **not** reordered. The core cannot do the same: an `.mra` with `address=` has the
  HPS write DDR3 directly, and no `<interleave>` works in 32-byte chunks, so the region is stored
  as the ROMs load it and `hng64_video` translates the address instead.
- **The four texture regions are identical copies** and only the first is used, which is also why
  the core stores one (`docs/ROADMAP.md`, memory plan).

## Write timing, and what it decides

`scripts/write_timing.py`, 528-line frame, vblank starts at line 445 (83 lines of vblank):

| Set / state | Sprite RAM | Tile VRAM | Palette |
|---|---|---|---|
| `sams64` attract | 100% in vblank, 4% in the first 2 lines | 52% in vblank, the rest across the next ~100 lines | 100% in vblank, 70% in the first 2 lines |
| `sams64` in play | **100% in the first 2 lines after vblank start** | **0% in vblank**: all of it mid-screen, lines ~160-280 | 285 writes a frame, 91% in the first 2 lines |
| `buriki` attract | 100% in vblank | 89% in vblank, the rest mid-screen | **26% in vblank**: most of it mid-screen |

Decisions this forces, before any RTL:

- **The sprite list is snapshotted at vblank start**, into a double buffer, and the frame is drawn
  from the snapshot. The games write the list in the first two lines *after* vblank start, so a
  copy taken at that moment holds the list MAME's `screen_update` used for the same frame. Reading
  the list live would show a half-written list on every in-play frame.
- **Tile VRAM, palette and the video registers are read live, per line.** In play, `sams64` writes
  no tile VRAM in vblank at all and `buriki` writes most of its palette mid-screen: these are
  raster effects, and buffering them whole-frame would lose them. MAME cannot show them because it
  renders the whole frame once at vblank (`docs/MAME_KLUDGES.md`).
- **Comparisons against MAME captures therefore use frames whose tile VRAM and palette are written
  in vblank** (the 2D screens used above). A frame with mid-screen writes is not a fair
  comparison, and a difference there is not automatically an RTL fault.

## The scroll registers have three layouts

`tilemap_draw_roz_core_line` (`hng64_v.cpp:143-318`) picks between them per layer per line, and a
model that implements only the common one will agree with the RTL and disagree with the hardware:

| Layout | Selected by | Increments |
|---|---|---|
| Plain | `tileregs` bit 11 set, `videoregs[0]` bit 26 clear | x and y step down the screen only |
| Per line | bit 11 clear, bit 26 clear | same, from this line's four words |
| Alt, rotating | bit 26 set | `xalt`/`yalt` add a second term, so y also steps across the line |

`videoregs[0]` bit 26 is global: it changes the *meaning* of every layer's scroll words at once.
`buriki`'s title screen uses it for the rotating logo, `fatfurwa` at various points. In line mode
with bit 26 set, y steps across the line instead of down it. In line mode a line's x words are
used only when their low byte is 0, otherwise the layer's base words stand
(`hng64_v.cpp:298`); the y words are always the line's.

Two details of MAME's loops are load-bearing and neither is a per-pixel test:

- Without rotation or wrap it **skips to the first in-range pixel and stops at the first one past
  the map**, so a line cannot re-enter after leaving it.
- The mosaic run starts at the first *drawn* pixel, not at screen x 0.

## RTL: the tilemap line engine

`rtl/video/hng64_tilemap.sv` draws one line of one layer: it reads the layer's scroll entry, forms
the 16.16 steps (the one product, `line * ystep`, is a serial shift-add), then walks 512 pixels,
fetching a tile word from VRAM and up to four ROM words per tile row.

`sim/tilemap_tb` (Verilator, C++ driver) serves VRAM and the tile ROM from a capture and compares
every pixel with the model's per-layer dump (`render_model.py --dump`).

`rtl/video/hng64_sprite.sv` is the other engine: a pre-pass over the 1,536-entry list at frame
start collects the sprites that touch the frame, then each line walks them into a 512-entry
z-buffer. Its three products (`rely * dy`, `ytile * (chainx+1)`, `(dstwidth-1) * dx`) are serial
shift-adds.

`rtl/video/hng64_mixer.sv` is the third. MAME walks priority 0x1f down to 0x00, drawing the
layers at each step and one sprite group every fourth step (`hng64_v.cpp:838-846`), so a sprite
group sits *between* two tilemap priorities rather than above or below all of them. That matters
because a layer or a sprite can be additive or half-alpha, and then what is under it shows
through. The mixer therefore ranks a pixel's up-to-five contributors - four layer indices and the
sprite that won its z-buffer - by the key that walk implies, and composites them in that order.
Five palette lookups happen at once, so the palette is three dual-port M10K copies.

`sim/mixer_tb` feeds it the model's own per-layer dumps, so it checks the mixer alone against the
model's finished RGB frame.

`rtl/video/hng64_video.sv` is the block: the four tilemap engines and the sprite engine writing
five line buffers, then the mixer reading them, with a sequencer that runs them one after
another. `sim/video_tb` gives it nothing but the capture - tile VRAM, both tile ROMs, the sprite
list, the palette - and compares the whole frame, so nothing from the model sits in the middle.

Two faults only this bench could find, both in the seams rather than in any engine:

- **Every port's read latency has to be the same in every bench.** The three module benches each
  served a RAM at a different point in the C++ tick, so the same port had zero, one or two cycles
  of latency depending on which bench was running. Each module passed; the block was a pixel out.
  The contract now, stated in each module's header and served the same way everywhere: line
  buffers, tile VRAM, the sprite list and the palette all answer one cycle after the address; the
  two tile ROMs answer with `rom_valid`.
- **The sprite engine's frame-start pre-pass outlasts a line.** It walks all 1,536 entries, and
  the block reported itself idle while it ran, so line 0 could start against an unfinished
  candidate list. `busy` now covers it.

`scripts/video_regress.sh` runs all three benches over every capture and every enabled layer:

```
scripts/video_regress.sh              # 21 captures, 127 checks
```

**127 of 127 at 0 of 229,376 pixels differing**, over 21 captures of `sams64`,
`fatfurwa`, `buriki` and `xrally`: each tilemap layer, the sprites, the mixer, and the whole
block end to end. Exercised across those: 8x8
and 16x16 tiles, 4 and 8 bpp, per-tile flip, wrap and non-wrap clipping, mosaic in x and y, all
three scroll layouts including rotation, per-line scroll and zoom, auto-animation (`buriki` tm3
has 692 animated tiles, `sams64` tm2 has 186), sprite chaining, zoom, both z-sort senses, the
group and blend bits, additive and half-alpha blending, the eight tcram region modifiers and both
fade palettes.

Two paths are written but no frame anywhere exercises them: the alt 256x64 map dimensions and
split-screen scroll. Both are in-game effects of the drive boards and of `buriki` player
entrances; `scripts/scan_video.py` found neither in 1,500 frames of any of the five sets. The
model stops with an error rather than rendering split-screen wrongly.

## The per-line budget, and how it was met (Phase 2)

A frame is 528 lines at 61.65 Hz, so a line is 30.7 us: **2,880 clocks at 93.75 MHz**. The block
as Phase 1 left it took 8,912 cycles a line. Four changes, each verified against the same 127
checks, brought it inside the budget:

| | sams64 attract | buriki f900 | buriki f1200 |
|---|---|---|---|
| Phase 1: engines in turn, each stalling per fetch | 8,912 | - | - |
| Tilemap engine pipelined (issue, never wait) | 5,664 | - | - |
| Sprite engine asks for a whole chain at once | - | - | - |
| Five engines at once, behind arbiters | 2,124 | 3,771 | - |
| Sprite chain walked once, not twice | 1,688 | 2,643 | 2,880 |
| A line ahead, so the mixer overlaps the engines | **1,171** | **2,126** | **2,363** |

Worst lines are 1,573 / 2,837 / 3,150. Only buriki f1200's worst line exceeds 2,880, by 9%, and
the line ahead absorbs it: the lines around it are 500 cycles under.

The figures use the benches' placeholder latencies (8 cycles for the tile ROM, 4 for tile VRAM).
The point of the rewrite is that they no longer scale with latency the way stalling did: the
whole block stays pixel-exact with the ROM at 100 cycles, and the tilemap engine's own cost is
512 cycles plus one latency rather than one latency per tile row.

What is not yet in the figures: contention with the CPU's cache fills and with the HDMI rotator
on the same DDR3 port, and whatever the real transport's latency turns out to be.

## How it looked before (Phase 1)

A frame is 528 lines at 61.65 Hz, so a line is 30.7 us: 2,880 clocks at the 93.75 MHz CPU clock.
The benches report cycles and fetches a line, with their placeholder ROM latency of 8 cycles:

| Engine, capture | Cycles, worst | Cycles, mean | ROM reads, worst |
|---|---|---|---|
| whole block, `sams64` attract | 10,515 | 8,912 | - |
| whole block, `buriki` f1200 | 22,471 | 11,163 | - |
| tilemap, `sams64` tm0, 8x8 4bpp | 1,235 | 1,235 | 64 |
| tilemap, `buriki` f900 tm3, 16x16 8bpp | 2,203 | 2,203 | 176 |
| tilemap, `buriki` f900 tm1, rotating | 15,317 | 3,121 | 1,556 |
| sprites, `sams64` attract | 2,948 | 1,969 | 86 |
| sprites, `buriki` f900 | 4,654 | 3,476 | 66 |

Four layers and the sprites in sequence is 20,000 cycles in the worst line against a budget of
2,880. The fetch counts say the two engines miss it for opposite reasons, and that neither is
short of bandwidth: about 800 reads a line across all five is 6.4 KB, 208 MB/s, 6% of the
DE10-nano's 3.2 GB/s DDR3, one read every 3.6 clocks.

- **The tilemap engine is latency-bound.** 176 reads at 8 cycles is 1,760 of its 2,203 cycles
  spent waiting, because it stalls on each tile-row read instead of fetching the next tile while
  emitting the current one's 16 pixels. Prefetching puts the floor at one pixel a clock, ~512
  cycles a layer, and four layers then fit in sequence. Parallel engines do not address this:
  they would stall four at once.
- **The rotating layer refetches a row per pixel**, 1,556 reads, because its y moves across the
  line and the engine keeps only the current row. Its y step is small, so a direct-mapped cache
  of 16-32 rows in one M10K brings it near a normal layer's 176.
- **The sprite engine is not fetch-bound at all**: 66 reads and 4,654 cycles, so almost all of it
  is the 512-cycle z-buffer clear, the per-sprite serial products and one clock per pixel drawn
  including overdraw. The products can become per-sprite accumulators carried line to line (adds,
  so still WORKFLOW 14), and the z-clear can overlap the previous line. What is left is overdraw,
  and that is the one place parallelism is the answer: two or four units each owning a slice of x
  with its own z-buffer bank.

This was deferred to Phase 2 by the user and is the work the table above records. The budget
also scales with whatever clock the video block gets, and a faster one competes with a CPU that
does not yet close 93.75 MHz.

