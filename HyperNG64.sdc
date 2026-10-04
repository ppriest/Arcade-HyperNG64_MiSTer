derive_pll_clocks
derive_clock_uncertainty

# clk3d (the main PLL's counter[0]) is treated as not related to the others: everything between them
# crosses through hng64_3d's Gray-coded pointers, synchronisers and hng64_afifo (hng64_3d_bridge).
# The CPU's three (rtl/pll/pll_cpu.v) likewise, through hng64_cpu_cdc and synchronisers.
set_clock_groups -asynchronous -group [get_clocks {*|pll|pll_inst|*cyclonev_pll|counter[0]*}] -group [get_clocks {*pll_cpu*}] -group [get_clocks {*|pll|pll_inst|*cyclonev_pll|counter[1]* *|pll|pll_inst|*cyclonev_pll|counter[2]* *|pll|pll_inst|*cyclonev_pll|counter[3]* *|pll|pll_inst|*cyclonev_pll|counter[4]* sdram_clk_pin}]

# core specific constraints

# clk1x (hps_io, and sys's clk_sys) and CLK_VIDEO: what passes between them is configuration, static
# while it is used and unsynchronised in sys -- the OSD's status bits, sys's OSD and HDMI settings,
# cfg_done, video_calc's once-a-frame measurements. The pixels cross from clk2x (hng64_vidcdc.sv).
# The two clocks' closest edges are 4 ns apart; timed, a different set of these registers failed
# with each placement (bad3a3a, 527dbba seed 2).
set_false_path -from [get_clocks {*|pll|pll_inst|*cyclonev_pll|counter[1]*}] -to [get_clocks {*|pll|pll_inst|*cyclonev_pll|counter[4]*}]
set_false_path -from [get_clocks {*|pll|pll_inst|*cyclonev_pll|counter[4]*}] -to [get_clocks {*|pll|pll_inst|*cyclonev_pll|counter[1]*}]

# The main PLL, VCO 1000 MHz: counter[0] clk3d (100), counter[1] clk1x (62.5), counter[2] clk2x (125),
# counter[3] the SDRAM clock (125 at 180 degrees), counter[4] CLK_VIDEO (50). clk1x, clk2x, the SDRAM
# clock and CLK_VIDEO rely on sharing it: clk2x is exactly twice clk1x (hng64_core.sv), and the
# display crosses from clk2x to CLK_VIDEO through registers only (hng64_vidcdc.sv). clk3d and the CPU's own three (pll_cpu, kept in
# their 3:2:4 by the VR4300's own crossings) are in the asynchronous groups above.

# SDRAM: the daughterboard's chip, clocked by counter[3] through a DDIO output to the SDRAM_CLK pin. The
# chip numbers are the MS32 and Seta cores', from Psikyo (CL2; which part they are for is not recorded).
# Reads do not close at 125 MHz, and no capture phase would: docs/HACKS.md.
set sdram_tAC   6.0    ;# memory CLK -> data valid, max
set sdram_tOH   2.7    ;# memory CLK -> data hold, min
set sdram_tDS   1.5    ;# memory input setup
set sdram_tDH   0.8    ;# memory input hold
set sdram_board 0.5    ;# trace + pin, max, each direction
set sdram_board_min 0.1
create_generated_clock -name sdram_clk_pin -source [get_pins -compatibility_mode {*pll|pll_inst|altera_pll_i|cyclonev_pll|counter[3].output_counter|divclk}] [get_ports {SDRAM_CLK}]
# read data crosses the board twice: the clock out to the chip, the data back
set_input_delay -clock sdram_clk_pin -max [expr {$sdram_tAC + 2 * $sdram_board}]     [get_ports {SDRAM_DQ[*]}]
set_input_delay -clock sdram_clk_pin -min [expr {$sdram_tOH + 2 * $sdram_board_min}] [get_ports {SDRAM_DQ[*]}]
# dq_in: rtl/memory/sdram/sdram.sv captures the bus there, every cycle, in the I/O cell, on the clk2x edge
# 12 ns after the chip edge that drives the data (the READ reaches the pins a clock after cmd_q; CL2;
# dq_in, dq_in2, then the lane at STATE_READ0). No hold multicycle: a burst changes the data every
# clock, so the hold check belongs on the edge before that one, the default.
set sdram_dq_regs [get_registers {*sdram:u_sdram|dq_in[*]}]
if {[get_collection_size $sdram_dq_regs] > 0} {
    set_multicycle_path -setup 2 -from [get_clocks {sdram_clk_pin}] -to $sdram_dq_regs
} else {
    post_message -type critical_warning "HyperNG64.sdc: no sdram dq_in registers matched -- SDRAM read multicycle NOT applied"
}
set sdram_outs [get_ports {SDRAM_A[*] SDRAM_BA[*] SDRAM_DQ[*] SDRAM_DQML SDRAM_DQMH SDRAM_nRAS SDRAM_nCAS SDRAM_nWE SDRAM_nCS SDRAM_CKE}]
set_output_delay -clock sdram_clk_pin -max [expr {$sdram_tDS + $sdram_board}]      $sdram_outs
set_output_delay -clock sdram_clk_pin -min [expr {-$sdram_tDH + $sdram_board_min}] $sdram_outs
