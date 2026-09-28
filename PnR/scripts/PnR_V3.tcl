#Working Final Draft Script
# ============================================================================
# FUSION COMPILER: RTL-TO-GDSII FULL BACKEND SCRIPT (SAED 14nm)
# Design: 32-Point Pipelined FFT Processor
# ============================================================================

set_host_options -max_cores 4

################################################################
## Global Variables & Directory Setup
################################################################
set DESIGN_NAME "FFT"
set OUTPUTS_DIR "../outputs"

if {![file exists $OUTPUTS_DIR]} { file mkdir $OUTPUTS_DIR }

set REFERENCE_LIBRARY "/home1/14_nmts/14_nmts/stdcell_hvt/ndm/saed14hvt_frame_only.ndm \
/home1/14_nmts/14_nmts/stdcell_slvt/ndm/saed14slvt_frame_only.ndm \
/home1/14_nmts/14_nmts/stdcell_rvt/ndm/saed14rvt_frame_only.ndm \
/home1/14_nmts/14_nmts/stdcell_lvt/ndm/saed14lvt_frame_only.ndm"

set LINK_LIBRARY "/home1/14_nmts/14_nmts/stdcell_lvt/db_ccs/saed14lvt_ff0p7vm40c.db \
/home1/14_nmts/14_nmts/stdcell_rvt/db_ccs/saed14rvt_ff0p7vm40c.db \
/home1/14_nmts/14_nmts/stdcell_rvt/db_ccs/saed14rvt_ss0p6v125c.db \
/home1/14_nmts/14_nmts/stdcell_lvt/db_ccs/saed14lvt_ss0p6v125c.db "

set TECH_FILE "/home1/14_nmts/14_nmts/tech/milkyway/saed14nm_1p9m_mw.tf"

# User-specific paths updated for FFT architecture
set VERILOG_NETLIST_FILES "/home1/IITR_PD3/MulukuriVNath/Documents/RTL-to-GDSII-Implementation-of-a-32-Point-Pipelined-FFT-Processor/Synthesis/outputs/FFT.mapped.v"
set UPF_FILE "/home1/IITR_PD3/MulukuriVNath/Documents/RTL-to-GDSII-Implementation-of-a-32-Point-Pipelined-FFT-Processor/PnR/scripts/FFT.upf"
set SDC_FILE "/home1/IITR_PD3/MulukuriVNath/Documents/RTL-to-GDSII-Implementation-of-a-32-Point-Pipelined-FFT-Processor/PnR/scripts/FFT.sdc"

set DESIGN_LIBRARY "./${DESIGN_NAME}_lib.ndm"

################################################################
## Library Creation
################################################################
#close_lib -all
if {[file exists $DESIGN_LIBRARY]} { file delete -force $DESIGN_LIBRARY }

set link_library   $LINK_LIBRARY
set target_library $LINK_LIBRARY
create_lib  -ref_libs $REFERENCE_LIBRARY -technology $TECH_FILE $DESIGN_LIBRARY

################################################################
## Read Verilog
################################################################
read_verilog ${VERILOG_NETLIST_FILES}
current_design ${DESIGN_NAME}
link

################################################################
## Design creation : Read UPF file(s)
################################################################
if {[file exists [which $UPF_FILE]]} {
  load_upf $UPF_FILE
  puts "Info: Running commit_upf"
  commit_upf
} elseif {$UPF_FILE != ""} {
  puts "Error: UPF file($UPF_FILE) is invalid. Please correct it."
}

########################################################################
## TLU+ Parasitics & Timing Constraints
########################################################################
set parasitic1              "tlup_max"
set tluplus_file($parasitic1)           "/home1/14_nmts/14_nmts/tech/star_rc/max/saed14nm_1p9m_Cmax.tluplus"
set layer_map_file($parasitic1)         "/home1/14_nmts/14_nmts/tech/star_rc/saed14nm_tf_itf_tluplus.map"

set parasitic2              "tlup_min"
set tluplus_file($parasitic2)           "/home1/14_nmts/14_nmts/tech/star_rc/min/saed14nm_1p9m_Cmin.tluplus"
set layer_map_file($parasitic2)         "/home1/14_nmts/14_nmts/tech/star_rc/saed14nm_tf_itf_tluplus.map"

foreach p [array name tluplus_file] {
  puts "Info: read_parasitic_tech -tlup $tluplus_file($p) -layermap $layer_map_file($p) -name $p"
  read_parasitic_tech -tlup $tluplus_file($p) -layermap $layer_map_file($p) -name $p
}

create_corner ss0p6v125c
create_corner ff0p7vm40c

set_parasitics_parameters \
  -early_spec tlup_min \
  -late_spec tlup_max \
  -early_temperature -40 \
  -late_temperature 125 \
  -corners {ss0p6v125c ff0p7vm40c}

set_voltage 0.6 -object_list {VDD SS_DEFAULT.power}
set_voltage 0.0 -object_list {VSS SS_DEFAULT.ground}
set_operating_conditions -max ss0p6v125c -min ff0p7vm40c

#Before Directly Running the SDC File I have Tried Creating the Mode and a Specific Corner for a Smooth SDC Read
#create_mode func
#create_scenario -mode func -corner ss0p6v125c -name func_ss

# 4. Create Scenarios and apply physical timing constraints
create_mode func
create_scenario -mode func -corner ss0p6v125c -name func_ss
create_scenario -mode func -corner ff0p7vm40c -name func_ff

current_scenario func_ss
read_sdc $SDC_FILE

current_scenario func_ff
read_sdc $SDC_FILE

# 5. Define Scenario Optimization Roles (Fixes the place_opt FLW-8004 crash)
set_scenario_status func_ss -active true -setup true -hold false -leakage_power true -dynamic_power true
set_scenario_status func_ff -active true -setup false -hold true -leakage_power false -dynamic_power false

# Load physical timing constraints from external SDC
read_sdc $SDC_FILE

########################################################################
##  Metal Layer Directions & Attributes
########################################################################
define_user_attribute -type string -name routing_direction  -classes routing_rule
set_attr -objects [get_layers {M2 M4 M6 M8 MRDL}] -name routing_direction -value horizontal
set_attr -objects [get_layers {M1 M5 M7 M9}] -name routing_direction -value vertical

set_attr [get_lib_cells */*AO*] dont_use true
set_app_var simplified_verification_mode true
set_svf ${OUTPUTS_DIR}/${DESIGN_NAME}.mapped.svf

save_block -as fft_init_design

################################################################
## FLOORPLAN
################################################################
initialize_floorplan -core_utilization 0.50 -core_offset {1}

set_block_pin_constraints -self -allowed_layers {M3 M5} -sides 2
place_pins -ports [get_ports -filter direction==out]
set_block_pin_constraints -self -allowed_layers {M4 M6} -sides 3
place_pins -ports [get_ports -filter direction==in]

set_attr  [get_ports *] physical_status fixed

# M1 Track Definition
remove_track -layer M1
create_track -layer M1 -coord  1.111 -space 0.037
report_track

connect_pg_net -automatic

set_attr [get_cells -physical_context -filter design_type==macro] physical_status fixed

#################################################################
## Boundary and Tap cells
#################################################################
set_boundary_cell_rules \
  -top_boundary_cells [get_lib_cells */*CAPT2] \
  -bottom_boundary_cells [get_lib_cells */*CAPB2] \
  -right_boundary_cell [get_lib_cells */*CAPBIN13] \
  -left_boundary_cell [get_lib_cells */*CAPBTAP6] \
  -prefix ENDCAP

compile_targeted_boundary_cells -target_objects [get_voltage_areas]

create_tap_cells -lib_cell saed14lvt_ff0p7vm40c/SAEDLVT14_CAPTTAP6 -distance 30 -skip_fixed_cells

check_legality -cells [get_cells bound*]
check_legality -cells [get_cells tap*]

save_block -as fft_fpd

################################################################
## POWERPLAN (Integrated 3-Tier Architecture)
################################################################
set_attr [get_lib_cells */*TIE*] dont_touch false
set_lib_cell_purpose -include optimization [get_lib_cells */*TIE*]

# 1. Top Mesh (M8/M9)
create_pg_mesh_pattern Mesh_Upper -layers { \
  { {horizontal_layer: M8} {width: 0.12} {spacing: interleaving} {pitch: 4.8} {offset: 1.6} {trim:true} } \
  { {vertical_layer: M9} {width: 0.12} {spacing: interleaving} {pitch: 4.8} {offset: 1.6} {trim:true} } \
}

# 2. Intermediate Vertical Strap (M5) - Required to prevent PGR-049 depth failures
create_pg_mesh_pattern Mesh_Mid -layers { \
  { {vertical_layer: M5} {width: 0.12} {spacing: interleaving} {pitch: 4.8} {offset: 1.6} {trim:true} } \
}

# 3. Standard Cell Rails (M1)
create_pg_std_cell_conn_pattern Stdcell -rail_width 0.094 -layers M1

set_pg_strategy Strategy_Upper -core -pattern { {name: Mesh_Upper} {nets:{VDD VSS}} } -extension { {{stop:design_boundary_and_generate_pin}}}
set_pg_strategy Strategy_Mid -core -pattern { {name: Mesh_Mid} {nets:{VDD VSS}} }
set_pg_strategy StdCell_strat -core -pattern {{name: Stdcell} {nets: "VDD VSS"}} 

# Compile entire 3-tier grid simultaneously to auto-generate all vias (M9->M8->M5->M1)
compile_pg -strategies {Strategy_Upper Strategy_Mid StdCell_strat}

check_pg_connectivity
check_pg_drc

save_block -as fft_ppd

################################################################
## PLACEMENT
################################################################
set_app_options -name place.coarse.max_density -value 0.6
set_app_options -name place.coarse.continue_on_missing_scandef -value true

catch {add_buffer [get_nets -of [get_ports]] [get_lib_cells */*SAEDRVT*BUF_20] }
magnet_placement [get_ports *]
set_attr [get_cells eco_cell*] physical_status fixed

# 1. Run coarse placement (cells are floating)
create_placement -congestion

# 2. Snap the cells into the legal site rows FIRST
legalize_placement

# 3. THEN verify that the placement is completely legal
check_legality -verbose

set_attr [get_lib_cells *lvt*/*] threshold_voltage_group LVT
set_threshold_voltage_group_type -type low_vt LVT
set_multi_vth_constraint -low_vt_percentage 8 -cost cell_count

place_opt -to final_opto
connect_pg_net

save_block -as fft_pd

################################################################
## CTS (Clock Tree Synthesis)
################################################################
set_app_options -name cts.common.user_instance_name_prefix -value clock_opt_cts_
set_app_options -name opt.common.user_instance_name_prefix -value clock_opt_cts_opt_
set_app_options -name cts.common.max_fanout -value 32

clock_opt
connect_pg_net

################################################################
## ROUTING
################################################################
set_app_options -name route.detail.timing_driven -value true
set_app_options -name route.track.timing_driven -value true
set_app_options -name route.track.crosstalk_driven -value true
set_app_options -name route.global.timing_driven -value true
set_app_options -name route.common.global_min_layer_mode -value allow_pin_connection
set_app_options -name route.common.global_max_layer_mode -value soft
set_app_options -name time.si_enable_analysis -value true
set_app_options -name time.enable_si_timing_windows -value true
set_app_options -name time.enable_ccs_rcv_cap -value true
set_ignored_layers -max_routing_layer M8 -min_routing_layer M2

route_auto
report_qor -summary
route_opt
connect_pg_net

save_block -as fft_route

################################################################
## OUTPUT GENERATION
################################################################
# Export final deliverables to the external outputs directory
write_gds -design $DESIGN_NAME -merge_files $REFERENCE_LIBRARY $OUTPUTS_DIR/${DESIGN_NAME}_final.gds
write_parasitics -format SPEF -output $OUTPUTS_DIR/${DESIGN_NAME}_final.spef
write_verilog -include {pg_netlist} $OUTPUTS_DIR/${DESIGN_NAME}_final_pg.v
