# Phase 0 criterion 4. One PLL feeds all three clocks in the real core (the N64 core's
# 62.5 / 93.75 / 125 MHz), so they are declared as generated from one source: as independent
# create_clocks the analyser assumes worst-case alignment between the domains and the
# cross-domain paths read as large negative slack.
create_clock -name clk2x -period 8.000 [get_ports clk2x]
create_generated_clock -name clk1x -source [get_ports clk2x] -divide_by 2 [get_ports clk1x]
create_generated_clock -name clk93 -source [get_ports clk2x] -multiply_by 3 -divide_by 4 [get_ports clk93]
derive_clock_uncertainty
set_false_path -from [get_ports {reset din}] -to *
set_false_path -from * -to [get_ports dout]
