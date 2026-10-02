derive_pll_clocks
derive_clock_uncertainty

# clk3d (the main PLL's counter[0]) is treated as not related to the others: everything between them
# crosses through hng64_3d's Gray-coded pointers, synchronisers and hng64_afifo (hng64_3d_bridge).
# The CPU's three (rtl/pll/pll_cpu.v) likewise, through hng64_cpu_cdc and synchronisers.
set_clock_groups -asynchronous -group [get_clocks {*|pll|pll_inst|*cyclonev_pll|counter[0]*}] -group [get_clocks {*pll_cpu*}] -group [get_clocks {*|pll|pll_inst|*cyclonev_pll|counter[1]* *|pll|pll_inst|*cyclonev_pll|counter[2]* *|pll|pll_inst|*cyclonev_pll|counter[3]* sdram_clk_pin}]

# core specific constraints

# The main PLL, VCO 1000 MHz: counter[0] clk3d (100), counter[1] clk1x (62.5), counter[2] clk2x (125),
# counter[3] the SDRAM clock (125 at 180 degrees). clk1x, clk2x and the SDRAM clock rely on sharing
# it: clk2x is exactly twice clk1x (hng64_core.sv). clk3d and the CPU's own three (pll_cpu, kept in
# their 3:2:4 by the VR4300's own crossings) are in the asynchronous groups above.

# SDRAM: the daughterboard's chip, clocked by counter[3] through a DDIO output to the SDRAM_CLK pin. The block and
# its numbers are the MS32 and Seta cores', which took them from Psikyo, where they held on
# hardware at 96 MHz. Here the clock is 125 MHz and nothing has been compiled: the first report
# says whether the 180-degree phase and the two-cycle capture below close (docs/HACKS.md).
set sdram_tAC   6.0    ;# memory CLK -> data valid, max
set sdram_tOH   2.7    ;# memory CLK -> data hold, min
set sdram_tDS   1.5    ;# memory input setup
set sdram_tDH   0.8    ;# memory input hold
set sdram_board 0.5    ;# trace + pin, max, each direction
set sdram_board_min 0.1
create_generated_clock -name sdram_clk_pin -source [get_pins -compatibility_mode {*pll|pll_inst|altera_pll_i|cyclonev_pll|counter[3].output_counter|divclk}] [get_ports {SDRAM_CLK}]
set_input_delay -clock sdram_clk_pin -max [expr {$sdram_tAC + $sdram_board}]     [get_ports {SDRAM_DQ[*]}]
set_input_delay -clock sdram_clk_pin -min [expr {$sdram_tOH + $sdram_board_min}] [get_ports {SDRAM_DQ[*]}]
# dq_in: rtl/memory/sdram/sdram.sv captures the bus there, every cycle, in the I/O cell
set sdram_dq_regs [get_registers {*sdram:u_sdram|dq_in[*]}]
if {[get_collection_size $sdram_dq_regs] > 0} {
    set_multicycle_path -setup 2 -from [get_clocks {sdram_clk_pin}] -to $sdram_dq_regs
    set_multicycle_path -hold  1 -from [get_clocks {sdram_clk_pin}] -to $sdram_dq_regs
} else {
    post_message -type critical_warning "HyperNG64.sdc: no sdram dq_in registers matched -- SDRAM read multicycle NOT applied"
}
set sdram_outs [get_ports {SDRAM_A[*] SDRAM_BA[*] SDRAM_DQ[*] SDRAM_DQML SDRAM_DQMH SDRAM_nRAS SDRAM_nCAS SDRAM_nWE SDRAM_nCS SDRAM_CKE}]
set_output_delay -clock sdram_clk_pin -max [expr {$sdram_tDS + $sdram_board}]      $sdram_outs
set_output_delay -clock sdram_clk_pin -min [expr {-$sdram_tDH + $sdram_board_min}] $sdram_outs
