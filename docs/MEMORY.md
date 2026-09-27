# Memory: what lives where, and why it is hard here

Phase 2's first decision. Every sibling core (Psikyo, Fuuki, Seta, MS32, KonamiGX) keeps its ROM
in SDRAM and treats DDR3 as a load-time staging area; `LESSONS_LEARNED` states the rule plainly:
**choose SDRAM over DDRAM for real-time fetch** (~26 cycles measured against a 16-cycle budget in
a Psikyo bench), and the MiSTer documentation calls DDR3 latency unbounded.

This core cannot follow that rule. The numbers below say why, and the rest of the document is
about making real-time DDR3 reads work rather than avoiding them.

## What the hardware needs at run time

From `main_map` (hng64.cpp:1182) and the ROM regions, for the largest in-scope set (`fatfurwa`):

| Region | Size | Access | Notes |
|---|---|---|---|
| main RAM | 16 MB | CPU read/write, cached | `0x00000000` |
| `gameprg` | 16 MB | CPU read, cached | `0x04000000` |
| `bios` | 512 KB | CPU read, cached | `0x1fc00000` |
| sound RAM | 2 MB | CPU write, and read back | `0x60200000`; the BIOS uploads 2 MB and verifies it (Phase 0) |
| `scrtile` | 64 MB | **video, per line** | four tilemap layers |
| `sprtile` | 64 MB | **video, per line** | sprites |
| `textures0` | 16 MB | 3D, per pixel | Phase 3 |
| `verts` | 12 MB | 3D, per polygon | Phase 3 |
| tile VRAM | 512 KB | CPU write, video read per line | `0x20100000`; too big for M10K, see below |
| palette, sprite list, NVRAM, dual-port, line buffers | ~80 KB | video and CPU | on-chip M10K |

Total off-chip: **192.5 MB** for `fatfurwa`, 132.5 MB for `sams64`.

MiSTer SDRAM modules are 32 MB, 64 MB or 128 MB. Even a 128 MB module cannot hold the two tile
regions of a fight set (128 MB) *and* main RAM, so at least one real-time video region must be
read from DDR3 on every set in scope. DDR3 on the DE10-nano is 1 GB, of which the core's window
at `0x30000000` is far more than 192.5 MB.

## What that changes

The sibling cores' fetch pattern - one 8-byte granule at a time, `BURSTCNT = 1`, stall until it
arrives - is what makes DDR3 unusable for real-time work. Three things have to change together:

- **Bursts.** `ddram_phy.sv`, identical in four cores, hard-codes `DDRAM_BURSTCNT = 8'd1`; its own
  header calls wider bursts "the obvious throughput improvement". A tile row is 8 to 32 bytes,
  one to four beats, so a burst amortises one latency over a whole row rather than one granule.
- **Many requests in flight.** The cost that matters is not one read's latency but whether the
  engine waits for each read before issuing the next. A line needs at most 32 tile rows a layer;
  issued back to back against in-order returns, the line costs 32 issues plus one latency, not 32
  latencies. This is the single biggest change and it is why the engines are being restructured
  (below), not merely given a bigger buffer.
- **A line of slack.** Rendering line N+1 into a second set of line buffers while line N is being
  displayed turns a hard per-pixel deadline into a soft per-line one, and gives the arbiter room
  to serve the CPU and the HDMI rotator without tearing.

## The engines, restructured

Measured now (`docs/phase1_video.md`): 8,900-11,200 cycles a line for the whole block against a
2,880-clock line at 93.75 MHz, with a placeholder ROM latency of 8. The engines stall on every
fetch, which is exactly the pattern that fails on DDR3.

The fix separates addressing from pixels, in both engines:

1. **Address pass.** Walk the line and produce the list of tile-row addresses it needs, reading
   only tile VRAM and the sprite list, both on-chip. At most 32 entries a layer.
2. **Fetch.** Issue that list to the memory port back to back, without waiting, and collect the
   returns in order into a FIFO.
3. **Pixel pass.** Expand the returned rows into the line buffer, one pixel a clock.

Passes 2 and 3 overlap, so a layer's line costs about 512 cycles plus one latency, whatever the
latency is. A small tile-row cache sits in front of the fetch: it collapses a repeated tile within
a line, the same tile across layers, and - the case that costs most today - a rotating layer,
which refetches a row per pixel because its y moves across the line (1,556 reads a line against
176 for a normal layer).

The sprite engine's problem is different and was measured separately: 66 reads and 4,654 cycles,
so it is not fetch-bound at all. Its costs are the 512-cycle z-buffer clear, the per-sprite serial
products and one clock per pixel drawn including overdraw. The products become per-sprite
accumulators carried line to line (adds, so still WORKFLOW 14), the clear overlaps the previous
line, and what remains is overdraw.

## The on-chip RAM budget, which decides where tile VRAM goes

The 5CSEBA6 has 553 M10K blocks, 5,662,720 bits. Counted in blocks:

| Store | Bits | M10K | Note |
|---|---|---|---|
| tile VRAM | 4,194,304 | **410** | 512 KB |
| sprite list | 393,216 | 39 | 48 KB, doubled for the vblank snapshot: 78 |
| palette | 131,072 | 13 | six copies: five for the mixer's read ports, each needing its other port for the CPU's writes, and one for the CPU's reads: 78 |
| NVRAM | 131,072 | 13 | 16 KB |
| CPU caches and TLBs | 207,872 | 26 | measured, Phase 0 |
| line buffers | 40,960 | 4 | 5 x 512 x 16, doubled for line-ahead: 8; plus the 2 x 512 x 24 output buffer: 3 |
| z-buffer, dual-port RAM | ~11,000 | 2 | |

Everything except tile VRAM comes to about 220 blocks, 40% of the device, before the 3D
pipeline of Phase 3 asks for anything. **Tile VRAM alone would be 74%**, which does not leave
room for a rasteriser, and the 3D framebuffers (2 x 384 KB) could never have been on-chip either.

So tile VRAM goes in SDRAM, next to main RAM. It is small (512 KB) and the traffic is light:
about 12 scroll words and 32 tile words a line a layer, some 176 reads a line in all, against
main RAM's cache fills. It is read live per line rather than buffered, because the games write it
mid-screen (`docs/phase1_video.md`), so the engines treat it exactly as they treat the tile ROM:
issue the read, do not wait for it.

## Bandwidth, which is not the problem

All five engines together want about 800 reads a line, 6.4 KB, or 208 MB/s. The DE10-nano's DDR3
is 32-bit at 400 MHz, 3.2 GB/s peak. The video is about 6% of it. The CPU's cache fills, the
3D texture reads of Phase 3 and the HDMI rotator share the same port, and the sum is still far
from the limit. **Latency and the number of outstanding requests decide this design; bandwidth
does not.**

## The split (user decision)

**SDRAM holds everything the CPU writes; DDR3 holds everything that is read-only at run time.**

That keeps the CPU's writes and its cache fills off the port the video depends on, and it means
the DDR3 side can be a read-only burst engine with no write path and no read-after-write hazard.
It needs 22.3 MB, so the common 32 MB module is enough and no user is excluded.

The N64 core runs a VR4300 with its main RAM in DDR3, so the CPU path would tolerate DDR3; this
is a contention decision, not a correctness one.

### SDRAM, 32 MB module

| Offset | Size | Region | Access |
|---|---|---|---|
| `0x000000` | 16 MB | main RAM | CPU read/write, cached |
| `0x1000000` | 2 MB, in a 4 MB slot | sound RAM | CPU writes it and reads it back; no sound CPU yet (`HACKS.md`) |
| `0x1400000` | 1 MB | `bios` | CPU read, cached; copied here from DDR3 at start-up |
| `0x1500000` | 512 KB | tile VRAM | CPU write, video read per line; too big for M10K |
| `0x1580000` | 384 KB | 3D buffer A | CPU read/write (`0x30100000`); the 3D pipeline's, Phase 3 |
| `0x15e0000` | 384 KB | 3D buffer B | CPU read/write (`0x30200000`) |
| | | end `0x1640000`, 22.3 MB of 32 MB | |

The bridge sends only MAME's 512 KB BIOS window here, so the BIOS slot's second half is never
read; it is sized to MAME's declared region, which is what the `.mra` carries.

Everything in this table is plain memory in MAME as well, so all of it goes through the bridge's
backing-store path (`hng64_bus.sv`, `is_store`) and `hng64_mainmem`, rather than through the I/O
port: the I/O port is on the CPU's `clk1x` and SDRAM on `clk2x`, and the bridge already crosses
between them. `sim/mainmem_tb` fills each region at its SDRAM offset and reads it through the CPU
path, so a wrong base fails there.

### DDR3, the core window at `0x30000000`

Every region is stored at the size MAME declares for it, filled with MAME's erase byte where the
ROMs do not reach (`buriki`'s `scrtile` stops 8 MB short and has an 8 MB hole at `0x1800000`),
and otherwise exactly as the ROMs load it. Two transforms MAME applies are undone in the core
rather than in the image:

- `init_reorder_gfx` (`hng64.cpp:1814`) interleaves `scrtile`'s two halves in 32-byte units. An
  `.mra` cannot express that - with `address=` the HPS writes DDR3 without the core seeing the
  bytes, and `<interleave>` does not work in 32-byte chunks - so `rtl/video/hng64_video.sv`
  translates the address, given `scr_half`, half the DECLARED region size.
- `region_post_process` byte-swaps a region whose declared endianness is not the host's, so that
  MAME's native accessors work. The CPU here reads bytes in address order, which is the image
  before that swap.

**The layout is packed per set, not fixed.** `scrtile` and `sprtile` differ by 32 MB between
`sams64` and the others, and `scr_half` is per set in any case, so padding every set to the
largest would cost 64 MB of load time and fixing the bases in RTL would need an RTL edit per set.
`<rom index="1">` carries the bases and sizes instead - the generalisation of the mod byte - and
`scripts/build_mra.py` emits both from one `layout()`, so they cannot drift.

| Offset | Size | Region | Access at run time |
|---|---|---|---|
| `0x0000000` | 32 MB | `gameprg` | CPU read, cached |
| `0x2000000` | 1 MB | `bios` | CPU read; copied to SDRAM at start-up |
| `0x2100000` | 32 or 64 MB | `scrtile` | tilemap engines, per line |
| ... | 32 or 64 MB | `sprtile` | sprite engine, per line |
| | | `textures0` | 3D, Phase 3; appends here |
| | | `verts` | 3D, Phase 3; appends here |

`sams64` ends at `0x6100000` (97 MB); `sams64_2`, `fatfurwa` and `buriki` at `0xa100000`
(161 MB). Phase 3 appends `textures0` (16 MB) and `verts` (12 MB or 24 MB).

Index 1's blob is `"HNG1"` then a 32-bit base and a 32-bit size, big-endian, for `gameprg`,
`bios`, `scrtile`, `sprtile`, `textures0`, `verts` in that order. A size of zero means the
`.mra` does not carry that region.

The HDMI rotator is a separate window outside this one, as in the MS32 core
(`0x24000000`, three 8 MB buffers), and is the only DDR3 writer at run time. Its one-clock pixel
writes are queued in `rtl/memory/hng64_wfifo.sv` (256 entries) and issued by `hng64_ddram` when
no read is, or before reads once the queue is half full. It writes only when Orientation is CW or
CCW: 229,376 single-beat writes a frame, 14 M a second, scattered a column apart.

Collision check: every module driving `DDRAM_ADDR` is listed here with its window, and the
windows are shown disjoint. `DDRAM_ADDR` has one driver, `rtl/memory/hng64_ddram.sv`: reads at
`0x30000000` + the layout above (`scrtile`, `sprtile`, `gameprg`, the BIOS copy), writes from the
rotator at `0x24000000`-`0x257fffff`. `sim/sys_tb` stops on a write outside that window.

## Loading

The HPS writes the whole image into DDR3 from the `.mra`, so the core never sees those bytes on
the ioctl port. Two modules pick it up:

- `rtl/memory/hng64_romcfg.sv` latches `<rom index="1">`, which arrives first, and hands out each
  region's base and size.
- `rtl/memory/hng64_romload.sv` copies `bios` from DDR3 into SDRAM once, out of reset, at 6.7
  cycles a byte (`sim/romload_tb`) - 75 ms for 1 MB at 93.75 MHz. Nothing else is copied: the
  video reads its tile ROM from DDR3 every line and the CPU reads `gameprg` from it.

`sim/romload_tb` runs the blob in on the real byte path, the copy through the real DDR3 transport
and the real SDRAM controller, and reads the result back through `hng64_mainmem` - the path the
CPU uses. It also checks that the granule past the region was not written, which is what would
catch a copy that runs long.

## The transport, and what it measures

`rtl/memory/hng64_ddram.sv` drives the port the way its Avalon interface allows: a new read on
any cycle `DDRAM_BUSY` is low, without waiting for the last one, with the replies coming back in
order and a queue of requester numbers routing them. Burst count stays 1, because nothing here
reads consecutive granules - a tile row's four words are 32, 128 and 160 bytes apart, and a
sprite's two rows 128 - so what buys the throughput is depth in flight, not width.

`sim/video_tb` drives the whole video block through it against a model of the DDRAM port, with
`+romlat` for the latency and `+ddrbusy` for the percentage of cycles the controller refuses a
read. Cycles a line, mean, against a budget of 2,880:

| latency / refused | `sams64` attract | `buriki` f1200 |
|---|---|---|
| 8, 20% | 1,192 | 2,407 |
| 40, 20% | 1,196 | 2,579 |
| 40, 50% | 1,283 | 2,733 |
| 100, 50% | 1,325 | 3,150 |

Ordinary content barely notices the memory. `buriki` f1200 is the rotating title screen, whose
layer wants a tile a pixel and is therefore fetch-bound; at 100 cycles of latency with half the
cycles refused it is 9% over budget on average. A tile-row cache is the fix if the real transport
turns out that bad - the same row is refetched for consecutive pixels.

Not in these numbers: the CPU's cache fills and the HDMI rotator, which share the port.

## SDRAM, and what tile VRAM costs there

`rtl/memory/sdram/sdram.sv` is vendored unchanged from the Seta core, which took it from
Fuuki, which took it from Psikyo, which extended Sorgelig's original to burst-4 reads
(`PROVENANCE.md` beside it). Three fixed-priority ports; this core uses port 0 for tile VRAM,
port 1 for the CPU (not wired yet) and port 2 for the download.

The controller runs **one transaction at a time per port**, so the four tilemap engines
queue behind each other for tile words in a way they do not for tile rows. Two things make
that affordable: a granule is 64 bits, which is two consecutive tile words, and a line walks
tiles in order; and the port keeps the last four granules, one for each engine, because a
single entry is evicted by the next engine before its owner comes back to it.

Mean cycles a line with tile VRAM in SDRAM behind the real controller and a chip model
(`sim/common/sdram_chip_model_wide.sv`), with the tile ROM still through DDR3:

| | idealised VRAM | SDRAM, one granule cached | SDRAM, four |
|---|---|---|---|
| `sams64` attract | 1,192 | 2,496 | **1,583** |
| `buriki` f900 | 2,126 | 2,624 | **2,215** |

Worst lines: 1,642 and 3,068. Tile VRAM in SDRAM costs about 400 cycles a line over an
idealised memory, and stays inside the 2,880-clock budget.

The bench fills tile VRAM through the download port and the video reads it back through the
video path, so the byte order is asserted by the test rather than argued: the region image
goes in byte for byte with the even byte in the low lane, and a big-endian 32-bit word comes
back byte-reversed, which `swap32` undoes.

## The CPU's side

`rtl/memory/hng64_mainmem.sv` meets the bridge's `st_*` contract (`rtl/hng64_bus.sv`): 1, 2
or 4 beats of 64 bits from a byte address, beats in address order. Main RAM and the BIOS come
from SDRAM, `gameprg` from DDR3, and a write outside main RAM is swallowed as the hardware
swallows it. Beats go to SDRAM one at a time, because the port serves one transaction, and
are pipelined to DDR3, because it does not.

`sim/mainmem_tb` fills both memories with an address-dependent pattern - through the real
download port for SDRAM - and reads every combination back: 1, 2 and 4 beats from each
region, byte-enabled writes to main RAM read back through the same path, and a write to the
BIOS checked to have changed nothing. 1,169 beats, none differing.

Byte order on this path needs no swap: a granule is four 16-bit words in ascending address
order with the even byte in the low lane, which is exactly "byte k at bits [8k+7:8k]", the
order the bridge expects.
