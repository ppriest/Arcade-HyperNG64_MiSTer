# `sdram.sv` — provenance and modifications

## Chain of custody

| Stage | What |
|---|---|
| Upstream | Sorgelig's `sdram.v`, GPL-3.0-or-later, from `MiSTer-devel/Arcade-Jackal_MiSTer/rtl/ram_rom/sdram.sv`. Kept beside it as `sdram_upstream_reference.sv` for diffing. |
| Then | `Arcade-Psikyo_MiSTer` — extended to burst-4 reads, so one 64-bit granule is one transaction rather than four. Proved on a DE10-nano. |
| Then | `Arcade-Fuuki_MiSTer` — carried across, the surrounding stack widened to 26-bit addresses for a 128 MB module. |
| Then | `Arcade-Seta_MiSTer` — copied from that Fuuki tree untouched. |
| Here | Copied from the Seta tree **untouched**. Do not edit. |

Its own header and the Seta tree's `PROVENANCE.md` record what changed from upstream and why.
Nothing in this repository modifies it; if it ever has to change, the change is recorded here
with the reason and the evidence, as `rtl/cpu/vr4300/PROVENANCE.md` does for the CPU.

## Why this controller

`docs/ROADMAP.md`, component reuse map: the SDRAM controller comes from a sibling core rather
than being written. Three fixed-priority ports (0 preempts 1 preempts 2), 64-bit burst-4 reads,
single 16-bit writes with byte lanes, 26-bit byte addressing.

## What this core asks of it that the siblings did not

The sibling cores keep only ROM in SDRAM and write it once, during the download. This core keeps
16 MB of main RAM there, which the CPU reads and writes while the game runs (`docs/MEMORY.md`),
so the single-word write path is on the critical path rather than a load-time convenience. The
controller supports it as it stands - `wrl`/`wrh` with `din` on any port - but it is the first
core in the family to lean on it, so it is worth saying plainly.

## The bench model

`sim/common/sdram_chip_model_wide.sv` is copied unchanged from `Arcade-JalecoMS32_MiSTer`, which
widened the row address from the shared model's 8 bits to the real 13 to stop regions aliasing.
Its own header records that. It models CAS latency and burst length, so a bench that drives this
controller through it is testing the protocol, not a memory abstraction.
