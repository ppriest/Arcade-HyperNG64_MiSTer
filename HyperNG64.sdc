derive_pll_clocks
derive_clock_uncertainty

# core specific constraints

# One PLL, VCO 750 MHz: general[0] clk93 (93.75), general[1] clk1x (62.5), general[2] clk2x (125),
# general[3] the SDRAM clock (125 at 180 degrees). All four share the VCO and the design relies on
# it: clk2x is exactly twice clk1x (hng64_core.sv) and the VR4300 crosses clk1x/clk93 as the N64
# core does. So no clock groups: every crossing is timed as synchronous.

# SDRAM: the daughterboard's chip, clocked by general[3] through the SDRAM_CLK pin. The block and
# its numbers are the MS32 and Seta cores', which took them from Psikyo, where they held on
# hardware at 96 MHz. Here the clock is 125 MHz and nothing has been compiled: the first report
# says whether the 180-degree phase and the two-cycle capture below close (docs/HACKS.md).
set sdram_tAC   6.0    ;# memory CLK -> data valid, max
set sdram_tOH   2.7    ;# memory CLK -> data hold, min
set sdram_tDS   1.5    ;# memory input setup
set sdram_tDH   0.8    ;# memory input hold
set sdram_board 0.5    ;# trace + pin, max, each direction
set sdram_board_min 0.1
create_generated_clock -name sdram_clk_pin -source [get_pins -compatibility_mode {*pll|pll_inst|altera_pll_i|general[3].gpll~PLL_OUTPUT_COUNTER|divclk}] [get_ports {SDRAM_CLK}]
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
