# MAME kludges this core reproduces

This project follows MAME, including where MAME is wrong (ROADMAP, "Design decisions"), so the
software model and the RTL reproduce MAME's guesses on purpose. This file lists each one that
touches an in-scope set: where it is in MAME, what the core does, and what would settle the real
behaviour.

It also records where a vendored, silicon-derived module disagrees with MAME and the module was
kept (ROADMAP, "Where a vendored module and MAME disagree").

This core's own approximations are not here; they are in `HACKS.md`.

Source references are to `src/mame/snk/hng64_v.cpp` unless named. MAME 0.285, commit
`5ae594bafe9`.

**Core column:** *copies* MAME; *differs* (and why); *n/a* (not in the core's scope);
*not checked*.

Every `hng64` set is `MACHINE_IMPERFECT_GRAPHICS | MACHINE_IMPERFECT_SOUND`.

## CPU and timing

| Kludge | MAME | Core | Would settle it |
|---|---|---|---|
| COP0 Config bits 23:16 | MAME sets Config to `0x6460` for the VR4300 (`mips3com.cpp:191-210`), leaving bits 23:16 at 0, though its own comment says the field is `0000010`. | Reads 0, as MAME does (`rtl/cpu/vr4300/cpu_cop0.vhd`, local change). | The VR4300 manual, or a read of Config on the board. Nothing in the BIOS uses the field. |
| COP0 Config clock ratio (bits 30:28) | MAME reports 0. The board wires DivMode0/1 high (hng64.cpp:107), so a real VR4300 reports its own ratio; the N64 core hard-codes `111`. | Set from the reset state to MAME's 0. | A read of Config on the board. |
| Frame rate by window height | A write setting a 448-line window reconfigures the screen at 59.43 Hz ("appears to sync with hardware"), any other height at 61.65 Hz, both with the 768 x 528 totals (`tcram_w`, hng64_v.cpp:1408-1413). | Differs, by user decision: the core stays at 25 MHz, 768 x 528, 61.65 Hz, 3.7% faster than MAME's 448-line games, because MAME's rate is not taken as the board's. | A frame-rate measurement on a board. |
| Whole-frame rendering, except at video register writes | MAME renders at vblank from the state then (`screen_update`, hng64_v.cpp:745), except that a write that changes a video register draws the lines above the beam first (`vregs_w`, `hng64.cpp:1119-1135`, `update_partial(vpos - 1)`): fatfurwa swaps its sky and floor tilemaps at line 244 this way every frame. Tile VRAM, palette, sprite and 3D-buffer writes mid-screen do not split the frame, so they show over the whole of it (the 3D buffer as it stood at each split). | The core renders per line from live tile VRAM, palette and video registers; only the sprite list is snapshotted (vblank start). The models draw the parts from the write log's beam positions (`scripts/render_3d.py`, `render_in_parts`). | A PCB capture of a frame with mid-screen tile or palette writes. `scripts/write_timing.py` shows both games making them in play. |

## Main board I/O

`rtl/hng64_io.sv` is MAME's `hng64.cpp` I/O handlers transcribed. `sim/io_tb` replays MAME's bus
trace to frame 900 through it and compares every read whose answer does not depend on timing -
3,098 of them, none differing - and every write MAME's handlers make as a side effect.

| Kludge | MAME | Core | Would settle it |
|---|---|---|---|
| The IO board's error code at dual-port `0x600` | `dualport_r` returns `m_no_machine_error_code` (0x01 for the fight sets) for offset `0x600` unless the MIPS has written `0x0c` to sysreg `0x1084` (`hng64.cpp:1025`), with the comment "hack, this should just be put in ram at 0x600 by the MCU". MAME's own notes say the MCU should read the code over serial. | Copies. | The IO MCU's serial link, and what the IO board sends on it. |
| Sysreg reads | `0x1c` reads 0 whatever was written ("0x00000040 must not be set or games won't boot") and `0x1084` reads 2 (`hng64.cpp:958`). | Copies. | A board. |
| Odd sprite clear | `sprite_clear_odd_w` clears three of each sprite's four odd dwords: the `+0x0c` write is commented out because it "erases part of the slash palette in the sams64 2nd intro" (`hng64.cpp:1105`). The even form clears all four, and tests only bits 8-15 for its second sprite where the odd form tests 0-15. | Copies all three differences. | What the clear registers do on a board. |
| Interrupt controller | Sources OR into a pending word, `0x1f701104` reads the lowest set bit, a write to `0x1f70111c` clears, and the CPU line follows "anything pending"; MAME's own TODO lists sources, priority and masking as unknown (`hng64.cpp:1871`). The level holds its last value once nothing is pending. | Copies. | A board, or the BIOS's use of bits MAME never raises. |
| Interrupt timing | Vblank (bit 0) at line 224 of 264, network (bit 11) at 240, raster (bit 1) at `m_raster_irq_pos[0] + 8` (`hng64.cpp:2128`); the MCU command pulse is held 1,000 main-CPU cycles (`tempio_irqoff_callback`); a display-list upload raises bit 3 after `0x200 * 8` cycles (`dl_upload_w`). | Copies: 1,250 and 5,120 cycles of the 62.5 MHz bus clock, which is exact against MAME's 50 MHz. | A board. |
| DMA | Instant: the whole copy happens inside the CPU's write to the length register (`do_dma`, `hng64.cpp:811`); the status register always reads 0. | Holds that write unacknowledged until the copy is done, so the CPU cannot tell. | Whether the BIOS polls a busy bit the board really has. |
| 3D status | `dl_vreg_r` always reads 0, so every wait loop on it passes at once (`hng64_3d.ipp:121`). | Copies. | Phase 3, against a board. |
| Sound mailbox trigger | A trigger write stalls the main CPU 5 us to let the V53A catch up (`spin_until_time`, `hng64.cpp:1172`). | Copies the stall, though there is no V53A to catch up. | Phase 4. |

## IO MCU (TLCS-870)

`rtl/io/hng64_tlcs870.sv` is MAME's `src/devices/cpu/tlcs870/` transcribed, so it reproduces
these. Line numbers are that directory's. `sim/iomcu_tb` agrees with MAME's trace for 3,000,000
instructions, but that window does not run every instruction below: `CALLV` and `RETN`, for
two, never appear in it.

| Kludge | MAME | Core | Would settle it |
|---|---|---|---|
| ADD/ADDC/SUB/SUBB carry | Each ends with `is_ZF() ? set_CF() : clear_CF()` under a comment that says "JF is copied from CF" (`tlcs870_ops_helper.cpp:280, 318, 355, 388`). The manual's own table, a few lines above, gives ADD as `C Z C H`. So MAME overwrites the carry with zero-ness and never touches JF. | Copies. A `jr` after an add branches on it, so this is not cosmetic. | The Toshiba manual is already explicit; it needs a board to confirm which behaviour the chip has. Nothing in the IO ROM's first 3M instructions depends on it. |
| ADDC/SUBB operand width | `do_alu_8bit` adds the carry to the source operand as a `uint16_t` before an 8-bit operation (`:531`), so `ADDC A,0xff` with the carry set compares against `0x100` and sets the carry whatever A holds. | Copies, by keeping the operands 17 bits wide. | Same. |
| `IL` high-byte write | `il_h_w` writes `m_IL = (m_EIR & 0x00ff) \| (data << 8)` - the low byte comes from EIR, not IL (`tlcs870.cpp:887`). A read-modify-write of `0x3d` therefore corrupts the interrupt latch's low half. | Copies. | The manual. This one is visibly a typo. |
| `CALLV n` | Jumps to `0xffc0 + n*2`, the vector's own address, rather than to the address stored there (`tlcs870_ops.cpp:985`). | Copies. | The manual. The IO ROM does not use `CALLV` in the traced 3M instructions. |
| `RETN` PSW source | Reads the PSW from `sp+2`, the same byte as the return address's high half, where `RETI` reads `sp+3` (`tlcs870_ops_reg.cpp:150`). | Copies. | The manual. |
| Register-prefix `LD`/`XCH rr,gg` | The dispatcher sends `0x10-0x13` to `XCH rr,gg` and `0x14-0x17` to `LD rr,gg`; each handler's own comment block says the opposite (`tlcs870_ops_reg.cpp:65`). | Follows the dispatcher, which is what executes. | The manual. The base table has `0x10-0x13` as `INC rr` and `0x14-0x17` as `LD rr,mn`, which makes the comments look right and the dispatch look wrong. |
| Source-prefix ALU cycle count | `ALUOP (src),(HL)` and `ALUOP (src),n` take one cycle off when they write the result back (`m_cycles -= 1`, `tlcs870_ops_src.cpp:534, 630`), so CMP - which writes nothing - costs one MORE than the other seven. | Copies. | The manual. Not checked by `sim/iomcu_tb`: see below. |

The MCU's peripherals are MAME's too, which is less than the chip has. `rtl/io/hng64_iomcu.sv`
copies each of these:

| Kludge | MAME | Core | Would settle it |
|---|---|---|---|
| Timer 2 period | Fires INTTC2 every 1,500 MCU cycles while TC2S is set, whatever TREG2 and the clock select say (`tc2_reload`, `tlcs870.cpp:342`, "TODO: use real value"). The ROM writes TREG2 = 1 and TC2CR = 0x24. | Copies. `sim/iomcu_tb` takes all 1,560 of its interrupts from this timer and agrees with MAME's trace throughout; with a period of 1,499 it diverges at the second. | The TMP87PH40 manual's TC2 timer mode with those settings, or the interval measured on a board. The ROM's INTTC2 handler writes 0xff to port 3, the lamp and input bus. |
| Timers 1, 3, 4, the time base, the watchdog | Their callbacks are empty and their control writes are stored and nothing else (`tlcs870.cpp:284, 391, 428, 457, 665`). The ROM has handlers for INTTC1 (`d00b`) and INTWDT (`d348`) that therefore never run. | Copies: registers only. | The manual, and whether the board's ROM ever enables them. |
| Serial 1 | A transmit shifts one bit every 1,000 cycles, the first at once, and raises INTSIO1 after the last byte; receive modes do nothing (`tlcs870.cpp:577`). The bits go to `hng64_state::sio0_w`, which discards them. | Copies the timing; there is nowhere for the bits to go. | The network board, which this core does not have. INTSIO1 has a handler (`d30c`); the traced window never starts a transfer. |
| ADC | A start samples the selected input at once, and ADCCR always reads "finished" (`tlcs870.cpp:787`). | Copies. | Only the drive sets use it, and they are out of scope. |
| `m_read_input_port` | Which read-modify-write instructions see a port's output latch rather than its pins is set per handler (`tlcs870_ops*.cpp`), and not uniformly: CLR and CPL (pp).g see the latch, SET (pp).g the pins. | Copies, through the core's `mem_latch`. | The manual. Not exercised by the bench, where the inputs are idle. |

**Cycle counts: verified along the executed path.** Each instruction is charged the count in its
handler's own comment block. `sim/iomcu_tb` now takes every interrupt from the subsystem's own
timer rather than from the trace, so an instruction charged one cycle too many or too few before
an interrupt moves that interrupt to a different instruction. 1,560 land where MAME's do across
3,000,000 instructions. What it cannot see is a wrong count on an instruction the ROM never runs
in that window.

## Video

MAME admits most of the mixing is guesswork. The model and the RTL copy each guess; where a
capture settles one either way it is said so here, because "copies MAME" and "known right" are
not the same claim.

| Kludge | MAME | Core | Would settle it |
|---|---|---|---|
| Tilemap additive blending | `:595-613` `get_blend_mode`: "this is based on xrally and sams64/sams64_2 use, it could be incorrect". `tcram[0x0c]` bit 2 for layers with `tileregs` bit 5 set, bit 26 for the rest; 1 plain, 2 additive. | copies, `blend_mode()` and `hng64_mixer.sv`. **Verified against MAME** on `xrally` frame 540, a 2D-only frame: 0 of 229,376 pixels differ as transcribed, all 229,376 differ with additive forced off. | The blend bits' real meaning on hardware; the capture confirms MAME is self-consistent, not that the chip agrees. |
| Sprite blending: additive or half-alpha | `:697` `spriteblendtype = BIT(m_tcram[0x4c/4], 16)`, with the comment "would be an odd place for it, after the 'vblank' flag but...". Blended sprites (`bit 15`) are `alpha_blend_r32(..., 0x80)` when set, `add_blend_r32` when not. | copies, `render()` and `hng64_mixer.sv`. **Unverified**: no 2D-only frame in hand has a blended sprite. `fatfurwa` and `buriki` set the bits only from frame ~510, by which point the 3D layer covers the screen. | A 2D-only capture with blended sprites, or the register's real meaning. |
| Sprite groups mixed between tilemap priorities | `:838-846`: the priority walk draws one sprite group every fourth step, so a group sits between two tilemap priorities rather than above or below all of them. | copies, `render()` and `hng64_mixer.sv`. **Unverified**: `sams64` attract has groups 1 and 4, but forcing every sprite to draw last changes no pixel there, and no other 2D-only capture has sprites at all. | A 2D-only capture with sprites in two groups straddling a tilemap's priority. |
| Which fade palette a layer selects | `:337-346`: "allow one of the 2 pairs of fade values to be used (complete guess! ...)" and "which one depends on target layer? (also complete guess!)". `tileregs` bit 7 enables, bit 5 picks. | copies, `palettes()` and `hng64_mixer.sv`. | MAME's own comment says buriki's intro suggests it is wrong. A PCB capture of a fade. |
| `tcram[0x24]` bit 17 blanks the frame | `:777`: "set during transitions, could be 'disable all palette output'?" returns before anything is drawn. | copies, `render()`. Not in the RTL mixer yet; it is a frame-level gate. | A PCB capture of a transition. |
| Split-screen scroll | `:667-677`: `videoregs[0]` bit 0 draws each half of the screen with its own offset from `videoregs[0x09]`/`[0x0a]`, "used when a single tilemap gets 'split' on Buriki player entrances?". | **not implemented**; the model stops with an error if the bit is set. No frame in 1,500 of `sams64`, `fatfurwa`, `buriki`, `roadedge` or `xrally` sets it (`scripts/scan_video.py`); `xrally` sets bit 1 only. | An in-game capture of a buriki player entrance. |
| Video registers power up as `0xdeadbeef` | `hng64.cpp:2174-2177`, `machine_start`: every `m_videoregs` word but the first set to `0xdeadbeef`, a debugging fill. The BIOS read-modifies-writes registers `0x10` and `0x14` before setting them whole, so MAME keeps bits of the fill there (`0xc000`, `0x9000`, `0xe000` against `0`, `0x1000`, `0x2000` from zero). | copies, `hng64_vbus.sv` reset; with it the texture-wrap table's `0x08` fill (`:2179`, `hng64_io.sv`). | What the board's registers hold at power-up. |
| Alt 256x64 map dimensions | `:619`: `videoregs[0]` bits 25:24 select them, annotated "road edge alt 1 / alt 2". | written in the model and the RTL, **unexercised**: the bits are 0 in every frame scanned, including `roadedge`'s. | An in-game `roadedge` capture. |

<!-- Examples of the shape, from sibling cores:
| "Tokkae shadow masking (INACCURATE)" | `konamigx_v.cpp`, primodes 4 and 5: a shadow's priority is raised to the highest priority of a layer that SHD_ON excludes | copies, `mixer_shadow_setup` | The K055555 SHD_ON behaviour on hardware (MAME calls it a HACK) |
| Unhandled priority mask 0xc0: MAME draws `machine().rand()` pixels and pops a message | `ms32_v.cpp:522-526` | differs: not reproduced | — |
| Watchdog not implemented | `jaleco_ms32_sysctrl.cpp:104` | copies (ignored) | — |
| Equal z-code tie-break | No silicon source found; MAME draws back to front and skips when the stored z is lower | copies: the line buffer writes when (z, priority) is strictly lower, in RAM order | A PCB capture of two overlapping equal-z sprites |
-->

## 3D

`scripts/render_3d.py` transcribes MAME's 3D in float32 and copies every item below: it is exact
against MAME's frames (sams64 BIOS logo, frames 500-652; in-game frame 2500), which is what makes
it the reference for the fixed-point design. The RTL's column is open until that design is made;
each row says what the RTL would have to do to copy MAME. References are to `hng64_3d.ipp` unless
named. Items marked **error** make no sense as hardware and read as slips in MAME's code rather
than guesses about the board.

| Kludge | MAME | Model | Would settle it |
|---|---|---|---|
| **error:** model scale axes swapped | With packet bit `0x0040`, vertex x is scaled by `m_modelscalez`, y by `m_modelscaley`, z by `m_modelscalex` (`:383-385`). MAME's own comment says the scale is only seen on roadedge/xrally's Hyper 64 logo, at `0x100` (no scale). | Copies. | A logo frame from roadedge or xrally with a scale other than `0x100`; not in scope for the fight sets. |
| **error:** a chunk with a non-zero top byte stalls the walk | `if (chunkOffset[0] & 0xff00) continue;` (`:582`) skips the `chunkOffset += chunkLength` at the loop's end (`:951`), so the same chunk is read again for every remaining count of the block and nothing after it in the block is drawn. | Copies. | A ROM chunk with that byte set; none is known. |
| **error:** an unknown chunk type still draws | The `default` case (`:793-797`) logs and sets the length to 3, and the polygon is still marked visible and drawn, from whatever the reused polygon array held from an earlier packet. | Copies, including the reused array, except across the frames the model skips (those before the last clearing vblank). No capture has an unknown type: sams64 frames 500-5000 use 04, 05, 0e, 0f, 87, 96, 97, c7 and d7 only. | A ROM chunk of an unknown type. |
| **error:** the rasteriser's clip rectangle is 513 x 513 | `visibleArea.set(0, 512, 0, 512)` (`:1465`) is inclusive, so spans reach x = 512, and the scanline functions write `x & 511` (`:1405`, `:1437`): the pixel right of the last column lands in column 0 of the same line. Line 512 is dropped by the `scanline > 511` test. | Copies (x = 512 is written after the span, as MAME's loop order has it). | The board's frame buffer width; the 3D buffer is 512 wide in MAME's own notes. |
| Behind-camera cull tests one vertex | A triangle is dropped whole if its vertex 0 is behind the camera (`:877`), although the frustum clipper after it handles partly visible triangles; a triangle with vertex 0 in front and the others behind is clipped instead. | Copies. | A board frame with geometry crossing the camera plane. |
| Flat colour not masked | A flat polygon writes `palOffset + colorIndex` unmasked (`:1437`), so a sum past `0x7ff` sets the blend and light bits of the buffer word; textured pixels are masked to 11 bits (`:1401`). | Copies. | Flat polygons with a large palette offset on a board. |
| Perspective-correct texturing | Texture coordinates and light are divided by w per pixel (`:1347-1350`, `drawShaded`); MAME's comment says the board very likely does not do this. | Copies. | Texture swim on a board frame with a steep polygon. |
| Light added, not multiplied, and 4-bit | The 3D palette adds `intensity << 2` to each channel (`hng64_v.cpp:1288-1302`, "unlikely"), and only the top 4 bits of the interpolated light are kept (`/ 16`, `:1399`). The light itself is `dot * strength * 128 * 128`, clamped to 255 (`:835-837`); the comment's "[0.0, 2.0]" does not describe that range. | Copies. | Lit polygons on a board. |
| 3D fades with fade register 0 only | The 3D palette is built through `tcram 0x18` and its modes whatever the game wants (`hng64_v.cpp:1305-1307`, "very unlikely"). | Copies. | buriki's discipline intro, which MAME's comment says it gets wrong. |
| sams64 camera ignored | `init_ss64` sets `m_samsho64_3d_hack`, and the camera matrix is left out of the model view (`:812`); sams64 does send camera packets. | Copies. | sams64 in-game frames on a board. |
| 3D buffer stretched by 447 | The blit's vertical step is `(512 << 16) / (max_y - min_y)`, 447 for 448 lines (`hng64_v.cpp:877-881`), so the 512 buffer lines are sampled a fraction too far apart. | Copies. | A board frame; the board draws 264 lines a field, not 448. |
| **error:** the blit adds `cliprect.min_x` twice | `src[((cliprect.min_x + x) + xscroll)]` with x already starting at `min_x` (`hng64_v.cpp:904`). No effect while the whole screen is drawn in one update, as it is now. | n/a: the model draws whole frames. | None needed. |
| Float rounding decides quantised values on exact boundaries | The light kept is `(u8)(rCorrect / 16.0f)` and the texel `(int)textureS` (`:1376-1400`), both truncations of float32 results. Where the true value is a whole number - constant light at a multiple of 16, a texel coordinate on an edge - float rounding puts it either side: on sams64's logo (frame 600) 109,001 of 111,164 drawn pixels have light/16 within 0.001 of a whole number, and MAME's truncation lands below and above about equally (`docs/phase3_3d.md`). | Copies (it is MAME's float32). A fixed-point design gives one side consistently and differs from MAME there. | Nothing to settle: MAME's value there is noise. |
| Comment slip in the clipper | `frustum_clip_all` labels its +Y clip "W <= +X" (`devices/video/poly.h:1470`); the code clips Y. | n/a | None needed. |

## Vendored modules that disagree with MAME

| Module | MAME says | The module does | Kept because | Would settle it |
|---|---|---|---|---|
| None yet. The VR4300's differences from MAME are reset state, and are in the CPU table above. | | | | |
