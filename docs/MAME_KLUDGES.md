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
| Whole-frame rendering | MAME renders at vblank from the state then (`screen_update`, hng64_v.cpp:745), so a write made mid-screen appears over the whole frame, and raster effects cannot show. Its own comment notes `fatfurwa` uses a raster interrupt to swap tilemap enables mid-screen. | The core renders per line from live tile VRAM, palette and video registers; only the sprite list is snapshotted (vblank start). | A PCB capture of a frame with mid-screen tile or palette writes. `scripts/write_timing.py` shows both games making them in play. |

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
| Alt 256x64 map dimensions | `:619`: `videoregs[0]` bits 25:24 select them, annotated "road edge alt 1 / alt 2". | written in the model and the RTL, **unexercised**: the bits are 0 in every frame scanned, including `roadedge`'s. | An in-game `roadedge` capture. |

<!-- Examples of the shape, from sibling cores:
| "Tokkae shadow masking (INACCURATE)" | `konamigx_v.cpp`, primodes 4 and 5: a shadow's priority is raised to the highest priority of a layer that SHD_ON excludes | copies, `mixer_shadow_setup` | The K055555 SHD_ON behaviour on hardware (MAME calls it a HACK) |
| Unhandled priority mask 0xc0: MAME draws `machine().rand()` pixels and pops a message | `ms32_v.cpp:522-526` | differs: not reproduced | — |
| Watchdog not implemented | `jaleco_ms32_sysctrl.cpp:104` | copies (ignored) | — |
| Equal z-code tie-break | No silicon source found; MAME draws back to front and skips when the stored z is lower | copies: the line buffer writes when (z, priority) is strictly lower, in RAM order | A PCB capture of two overlapping equal-z sprites |
-->

## Vendored modules that disagree with MAME

| Module | MAME says | The module does | Kept because | Would settle it |
|---|---|---|---|---|
| None yet. The VR4300's differences from MAME are reset state, and are in the CPU table above. | | | | |
