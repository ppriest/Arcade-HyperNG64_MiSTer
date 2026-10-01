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

Each modified file has its unmodified copy beside it as `*_upstream_reference.vhd`.

Checked: all 15 files compile in ModelSim-Intel 10.5b (Quartus 17.0) with `vmap mem work`, and
the boot bench (`sim/boot_tb`) runs 20,000 BIOS instructions matching MAME's trace in PC and all
31 registers.
