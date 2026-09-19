-- SPDX-License-Identifier: GPL-3.0-or-later
--
-- The N64 core's VR4300 (rtl/cpu/vr4300/cpu.vhd) with HNG64's settings and its per-instruction
-- export flattened into plain ports, so SystemVerilog can instantiate it. N64 debug switches and
-- savestate ports are tied to the values the N64 core ships with (N64.sv:804-812); SS_reset is
-- the reset-state loader (PC = 0xBFC00000) and must pulse while reset is held.
--
-- The loader sets COP0 Status to the N64's 0x3450FF04 (cpu_cop0.vhd:1301), which has the soft-reset
-- bit set; the hng64 BIOS tests it at 0xBFC00004-0xBFC00010. After SS_reset falls, Status is
-- rewritten through the savestate port (COP0 slot 12 = SS_Adr 76) with the VR4300 cold-reset value
-- BEV|ERL = 0x00400004, which is also MAME's (mips3.cpp:1115). Config (slot 16 = SS_Adr 80) is set
-- the same way to MAME's 0x0000E460; the N64's 0x7006E460 has its clock-ratio field set
-- (docs/MAME_KLUDGES.md).

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library work;
use work.pexport.all;

entity hng64_cpu is
   port
   (
      clk1x            : in  std_logic;
      clk93            : in  std_logic;
      clk2x            : in  std_logic;
      reset_1x         : in  std_logic;
      reset_93         : in  std_logic;
      ss_reset         : in  std_logic;
      irq              : in  std_logic;   -- CPU interrupt line (Cause IP2)

      mem_request      : out std_logic;
      mem_rnw          : out std_logic;
      mem_address      : out std_logic_vector(31 downto 0);
      mem_req64        : out std_logic;
      mem_size         : out std_logic_vector(2 downto 0);
      mem_writeMask    : out std_logic_vector(7 downto 0);
      mem_dataWrite    : out std_logic_vector(63 downto 0);
      mem_dataRead     : in  std_logic_vector(63 downto 0);
      mem_done         : in  std_logic;
      rdram_granted2x  : in  std_logic;
      ddr3_DOUT        : in  std_logic_vector(63 downto 0);
      ddr3_DOUT_READY  : in  std_logic;

      -- per-instruction export, valid when export_new is high (clk93). Simulation only: the
      -- CPU's own cpu_done/cpu_export ports are inside translate_off (cpu.vhd:59-62).
-- synthesis translate_off
      export_new       : out std_logic;
      export_pc        : out std_logic_vector(63 downto 0);
      export_opcode    : out std_logic_vector(31 downto 0);
      export_regs      : out std_logic_vector(32 * 64 - 1 downto 0);  -- r0 in bits 63:0
-- synthesis translate_on
      error_any        : out std_logic
   );
end entity;

architecture arch of hng64_cpu is

   signal cpu_export : cpu_export_type;
   signal addr_u     : unsigned(31 downto 0);
   signal size_u     : unsigned(2 downto 0);
   signal e_instr, e_stall, e_fpu, e_exc, e_fifo, e_tlb : std_logic;
   signal ss_reset_q : std_logic := '0';
   signal ss_step    : unsigned(1 downto 0) := "00";
   signal ss_wren    : std_logic := '0';
   signal ss_adr     : unsigned(11 downto 0) := (others => '0');
   signal ss_data    : std_logic_vector(63 downto 0) := (others => '0');

begin

   icpu : entity work.cpu
   port map
   (
      clk1x                => clk1x,
      clk93                => clk93,
      clk2x                => clk2x,
      ce_1x                => '1',
      ce_93                => '1',
      reset_1x             => reset_1x,
      reset_93             => reset_93,
      preNMI               => '0',

      INSTRCACHEON         => '1',
      DATACACHEON          => '1',
      DATACACHESLOW        => "0000",
      DATACACHEFORCEWEB    => '0',
      DATACACHETLBON       => '1',
      RANDOMMISS           => "0000",
      DISABLE_BOOTCOUNT    => '0',
      DISABLE_DTLBMINI     => '0',

      irqRequest           => irq,
      irqCartRequest       => '0',
      cpuPaused            => '0',

      error_instr          => e_instr,
      error_stall          => e_stall,
      error_FPU            => e_fpu,
      error_exception      => e_exc,
      error_fifo           => e_fifo,
      error_TLB            => e_tlb,

      mem_request          => mem_request,
      mem_rnw              => mem_rnw,
      mem_address          => addr_u,
      mem_req64            => mem_req64,
      mem_size             => size_u,
      mem_writeMask        => mem_writeMask,
      mem_dataWrite        => mem_dataWrite,
      mem_dataRead         => mem_dataRead,
      mem_done             => mem_done,
      rdram_granted2x      => rdram_granted2x,
      rdram_done           => '0',
      ddr3_DOUT            => ddr3_DOUT,
      ddr3_DOUT_READY      => ddr3_DOUT_READY,

      ram_done             => '0',
      ram_rnw              => '0',
      ram_dataRead         => x"00000000",

-- synthesis translate_off
      cpu_done             => export_new,
      cpu_export           => cpu_export,
-- synthesis translate_on

      SS_reset             => ss_reset,
      loading_savestate    => '0',
      SS_DataWrite         => ss_data,
      SS_Adr               => ss_adr,
      SS_wren_CPU          => ss_wren,
      SS_rden_CPU          => '0',
      SS_DataRead_CPU      => open,
      SS_idle              => open
   );

   process (clk93)
   begin
      if rising_edge(clk93) then
         ss_reset_q <= ss_reset;
         ss_wren    <= '0';
         if (ss_reset_q = '1' and ss_reset = '0') then
            ss_step <= "01";
         elsif (ss_step = "01") then
            ss_wren <= '1'; ss_adr <= to_unsigned(76, 12); ss_data <= x"0000000000400004";
            ss_step <= "10";
         elsif (ss_step = "10") then
            ss_wren <= '1'; ss_adr <= to_unsigned(80, 12); ss_data <= x"000000000000E460";
            ss_step <= "00";
         end if;
      end if;
   end process;

   mem_address   <= std_logic_vector(addr_u);
   mem_size      <= std_logic_vector(size_u);
   error_any     <= e_instr or e_stall or e_fpu or e_exc or e_fifo or e_tlb;

-- synthesis translate_off
   export_pc     <= std_logic_vector(cpu_export.pc);
   export_opcode <= std_logic_vector(cpu_export.opcode);
   gregs : for i in 0 to 31 generate
      export_regs(i * 64 + 63 downto i * 64) <= std_logic_vector(cpu_export.regs(i));
   end generate;
-- synthesis translate_on

end architecture;
