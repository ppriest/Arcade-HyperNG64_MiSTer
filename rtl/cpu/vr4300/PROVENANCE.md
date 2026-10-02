# VR4300 (from the MiSTer N64 core)

- Upstream: https://github.com/MiSTer-devel/N64_MiSTer, `rtl/`
- Commit: adbf9b5d41bcc8b6dc3ad00821e2cd062847ab4f
- Licence: GPL-3.0 (the repository's `LICENSE`; the files carry no headers of their own)
- Author: Robert Peip (FPGAzumSpass), per the N64 core

## Files

Copies, unmodified except `cpu_mul.vhd` (below):

| File | Role |
|---|---|
| `functions.vhd` | package `pFunctions` |
| `export.vhd` | package `pexport` (`cpu_export_type`), simulation-only `export` entity |
| `dpram.vhd` | `dpram`, `dpram_dif` (altsyncram) |
| `RamMLAB.vhd` | MLAB RAM, used as library `mem` |
| `SyncFifoFallThroughMLAB.vhd` | FIFO, used as library `mem` |
| `divider.vhd`, `cpu_mul.vhd` | integer divide and multiply |
| `cpu_cop0.vhd`, `cpu_TLB_instr.vhd`, `cpu_TLB_data.vhd` | COP0, TLBs |
| `cpu_instrcache.vhd`, `cpu_datacache.vhd` | caches |
| `cpu_FPU.vhd`, `cpu_FPU_sqrt.vhd` | COP1 |
| `cpu.vhd` | top entity `cpu` |

Compile order is the order in `vr4300.qip` and `sim/vhdl.files`: the TLBs before `cpu_cop0.vhd`,
which instantiates them.

## Library `mem`

Several files instantiate `entity mem.RamMLAB`, `mem.SyncFifoFallThroughMLAB`, `mem.dpram`.
The N64 project assigns no library, and Quartus resolves `mem` to `work`. ModelSim needs
`vmap mem work` (done in `scripts/run_sim.sh`).

## Local changes

- `cpu_mul.vhd`: added `LIBRARY altera_lnsim; USE altera_lnsim.altera_lnsim_components.all;`
  inside `-- synthesis translate_off`. It instantiates `altera_mult_add`, which ModelSim's
  `altera_mf` does not declare; Quartus's does, so outside the pragma the two declarations clash
  ("more than one Use Clause imports a declaration"). Simulation only, no logic change.

- `cpu_datacache.vhd`, `cpu_FPU.vhd`: their simulation-only `goutput` blocks are disabled
  (`if 1 = 0 generate`). Both open a fixed path on an `R:` drive and abort the simulation when it
  does not exist. No synthesised logic: the blocks are inside `translate_off`.
- `cpu_cop0.vhd`: two COP0 reset values changed so the CPU comes up as a bare VR4300 rather than
  as the N64 after its boot ROM. `COP0_16_CONFIG_systemClockRatio` now comes from `ss_in(16)`
  instead of being fixed to `"111"`, and Config's read-only bits 23:16 read 0 instead of
  `"00000110"`, which is what MAME reports (docs/MAME_KLUDGES.md). Status and Config are then set
  through the savestate port by `rtl/cpu/hng64_cpu.vhd`.

- `cpu_cop0.vhd`: a TLB-translated physical address is kept at 32 bits (`TLB_fetchAddrOutMasked`).
  Upstream masks it to 29 bits, the N64's physical space; the HNG64 BIOS maps its devices above
  0x20000000 through the TLB (the sound mailbox at 0x68000000 by a 16 MB page, the 3D registers at
  0x20300000), and with the mask those accesses landed in main RAM. Found on hardware: the BIOS
  polled 0x2030021A, seen by the CPU port as 0x0030021A (ISSP instance T), until nothing else ran.
  Unmapped (kseg0/kseg1) addresses are masked to 29 bits where they are formed, as before.

- `cpu.vhd`: a `debug_pc` output, the fetch PC's low 32 bits, read by the `HyperNG64_stp`
  revision's ISSP probe P. No logic changes.

- `cpu_cop0.vhd`: a `debug_regs` output, BadVAddr, Status, Cause and EPC (low words, MIPS
  layout); `cpu.vhd` passes it out as `debug_cop0`, for the stp revision's probe P. (The upstream
  `cop0_export` is simulation-only.)
- `cpu.vhd`: a `mem_idle` output, high when the write FIFO is empty and the memory port is idle,
  used by `rtl/cpu/hng64_cpu.vhd` to hold the interrupt line off while a store is pending
  (docs/HACKS.md); and an `irqHold` input, which keeps the decode stage from taking an
  interrupt (`irqTrigger` and `blockIRQ` as before, and `irqHold` low). Cause is unchanged.

- `cpu.vhd`: the instruction fetch's region check (`TLB_instrMapped`) is computed for each of the
  two candidate fetch addresses (`TLB_instrMapped1`/`2`), each candidate's tag-compare address
  takes its own, and the selected one is a mux of the two. Upstream derives it from the selected
  `FetchAddr`, which puts the branch decision in front of both tag compares. Same function;
  for timing at 93.75 MHz (user decision, docs/ROADMAP.md).

- `cpu_cop0.vhd`: an exception's address (BadVAddr, EntryHi's VPN and region, Context's and
  XContext's BadVPN) is written a clock after the exception is found, through `excQ_we`/`excQ_addr`.
  The exception flushes the pipeline, so the handler reads them clocks later. For timing at
  93.75 MHz (user decision). The boot bench takes no address or TLB exception in its 20,000
  instructions, so this is checked only by inspection so far.

- `cpu.vhd`: the branch compares (`cmpEqual`, `cmpZero`) are worked out for every pair of the
  operands' sources (execute's result, writeback's, the decoded value) and selected by the same
  forward flags that build `value1`/`value2`, instead of comparing after the forward mux. Same
  function; for timing at 93.75 MHz (user decision).
- `cpu_cop0.vhd`: the TLB search passes over an entry whose valid bit for the page is clear, as
  MAME's vtlb does, instead of stopping at it with TLB invalid (docs/MAME_KLUDGES.md).

Each modified file has its unmodified copy beside it as `*_upstream_reference.vhd`.

Checked: all 15 files compile in ModelSim-Intel 10.5b (Quartus 17.0) with `vmap mem work`, and
the boot bench (`sim/boot_tb`) runs 20,000 BIOS instructions matching MAME's trace in PC and all
31 registers.
