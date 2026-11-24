# create_project.tcl - rebuild the vivado project from the repo sources.
#
#   vivado -mode batch -source vivado/create_project.tcl      (from repo root)
#   or, in the vivado tcl console:  source <repo>/vivado/create_project.tcl
#
# creates <repo>/vivado_proj/ (git-ignored). sources are referenced in place,
# not copied, so edits in vivado change the files in rtl/ and tb/.
#
# PART is a spartan-7 placeholder until the board is chosen.
# the individual commands were run in vivado 2025.2. this script form (repo-
# relative paths) was dry-run in tclsh with stubbed commands, not yet in vivado.

set PART xc7s50csga324-1
set root [file normalize [file join [file dirname [info script]] ..]]

create_project lfsr_dice [file join $root vivado_proj] -part $PART -force

add_files -norecurse [glob [file join $root rtl *.v]]
set_property top top_module [current_fileset]

add_files -fileset constrs_1 -norecurse [file join $root constraints timing.xdc]

add_files -fileset sim_1 -norecurse [glob [file join $root tb *.v]]
set_property top lfsr_tb [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "project created in [file join $root vivado_proj]"
puts "sim top = lfsr_tb; change it under Simulation Sources -> sim_1 -> Set as Top"
