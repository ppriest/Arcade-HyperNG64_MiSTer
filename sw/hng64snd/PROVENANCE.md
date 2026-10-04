# hng64snd: the sound board, ported from MAME

The V53A, its peripherals, the L7A1045 and the board glue, ported from MAME at commit
`a2d0f76268e` (`E:/mame`, the reference used for the capture). Ported at the user's direction
(ROADMAP Phase 4). Each file keeps its MAME licence and copyright holders in its header.

| File | From | Licence | Changes |
|---|---|---|---|
| `nec/necinstr.hxx`, `nec/nec80inst.hxx`, `nec/necea.h`, `nec/necmodrm.h`, `nec/necinstr.h`, `nec/necmacro.h`, `nec/necpriv.ipp` | `src/devices/cpu/nec/` | BSD-3-Clause (Bryan McPhail) | None. |
| `nec_core.h`, `nec_core.cpp` | `src/devices/cpu/nec/nec.h`, `nec.cpp` | BSD-3-Clause (Bryan McPhail) | A plain class for the V33 alone: the device, state-save and debugger interfaces removed; the program space is `nec_space`, 16 banks of 64 KB; I/O and the interrupt acknowledge are virtual; `execute_run` takes its cycles and returns those used; `abort_slice` is MAME's `abort_timeslice`; the V33's chip type, prefetch size and cycles and divide quirk are constants, and `do_prefetch`'s loops are in closed form (the same results, a byte a cycle). `nec_core.h` was generated from `nec.h` by keeping its member list. |
| `v53.h`, `v53.cpp` | `src/devices/cpu/nec/v5x.cpp` (Patrick Mackinlay), `src/devices/machine/pit8253.cpp` (Wilbert Pol, Nathan Woods), `pic8259.cpp` (Wilbert Pol), `am9517a.cpp` (Curt Coder) | BSD-3-Clause | attotime becomes ticks of the 32 MHz clock; MAME's deferred PIT writes run at once with the write's time; the DMAU's execute loop is one step per DMAU clock on a timer, stopped where MAME suspends it; `install_peripheral_io`'s address-space layout is decoded in `peripheral_at`; the SCU (an i8251) is a stub, as nothing is attached to it on hng64; the V53A's 8237 DMA mode is not emulated (MAME's is not either). |
| `l7a1045.h`, `l7a1045.cpp` | `src/devices/sound/l7a1045_l6028_dsp_a.cpp` | BSD-3-Clause (R. Belmont, O. Galibert) | The stream's output is kept as MAME's integer sum (its `add_int(..., 32768)`); sample n is at tick n x 320000 / 441; the DMA timer runs in 1/1323 ticks. |
| `board.h`, `board.cpp` | `src/mame/snk/hng64_a.cpp`, the sound parts of `hng64.cpp` | LGPL-2.1+ (David Haywood, Angelo Salese, ElSemi, Andrew Gardner) | The run loop MAME's scheduler gave the board. |
| `mame_shim.h`, `endianness.h`, `emu_sched.h`, `bench.cpp`, `Makefile` | ours | GPL-3.0-or-later | |

MAME's behaviour this keeps where it is doubtful is in `docs/MAME_KLUDGES.md`, "Sound".
