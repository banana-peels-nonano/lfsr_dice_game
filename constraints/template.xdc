## template.xdc - PLACEHOLDERS ONLY. every line is commented out on purpose.
## replace <PIN>, <IOSTD> and the clock period from YOUR board's master XDC,
## then uncomment. no pin here is real.

## ---- clock ----  (period must match the CLK_HZ parameter of top_module)
#set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD <IOSTD> } [get_ports clk]
#create_clock -name sys_clk -period <PERIOD_NS> [get_ports clk]

## ---- buttons ----
#set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD <IOSTD> } [get_ports btn_new_game]
#set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD <IOSTD> } [get_ports btn_roll]

## ---- seed switches (repeat for 0..15, or fewer if the board has fewer) ----
#set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD <IOSTD> } [get_ports {sw_seed[0]}]
#set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD <IOSTD> } [get_ports {sw_seed[1]}]
## ... sw_seed[2] .. sw_seed[15]

## ---- leds (repeat for 0..15) ----
#set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD <IOSTD> } [get_ports {led[0]}]
## ... led[1] .. led[15]

## ---- seven-segment: seg[0]=a ... seg[6]=g ----
#set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD <IOSTD> } [get_ports {seg[0]}]
## ... seg[1] .. seg[6]
#set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD <IOSTD> } [get_ports dp]
#set_property -dict { PACKAGE_PIN <PIN> IOSTANDARD <IOSTD> } [get_ports {an[0]}]
## ... an[1] .. an[3]    (an[0] = rightmost digit)

## ---- asynchronous human i/o (see README) ----
#set_false_path -from [get_ports {btn_new_game btn_roll sw_seed[*]}]
#set_false_path -to   [get_ports {led[*] seg[*] dp an[*]}]

## ---- configuration (values from the board manual) ----
#set_property CFGBVS <VCCO or GND> [current_design]
#set_property CONFIG_VOLTAGE <3.3 or 1.8> [current_design]
