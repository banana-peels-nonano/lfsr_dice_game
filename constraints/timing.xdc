## timing.xdc - board-independent timing constraint.
## assumes a 100 MHz system clock, matching top_module's default CLK_HZ.
## if the board's clock differs, change the period here AND CLK_HZ.
## used for the vivado 2025.2 run in reports/vivado_results.md
## (xc7s50csga324-1 placeholder part, WNS +5.057 ns).
create_clock -period 10.000 -name sys_clk [get_ports clk]

## suggested, NOT yet verified: these should clear the 46 methodology
## warnings (expected to be TIMING-18, missing input/output delay) because
## the inputs are synchronised and the outputs only drive leds/display.
## uncomment, rerun implementation, and check report_methodology.
#set_false_path -from [get_ports {btn_new_game btn_roll sw_seed[*]}]
#set_false_path -to   [get_ports {led[*] seg[*] dp an[*]}]
