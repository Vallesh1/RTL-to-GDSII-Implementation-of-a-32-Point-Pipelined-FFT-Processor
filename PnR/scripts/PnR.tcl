# ============================================================================
# FUSION COMPILER PNR SCRIPT - 32-POINT FFT
# ============================================================================
set_host_options -max_cores 8

# ============================================================================
# 1. GLOBAL VARIABLES & PATHS 
# ============================================================================
set DESIGN_NAME "FFT"
set LIBRARY_SUFFIX "_lib"
set DESIGN_LIBRARY "${DESIGN_NAME}${LIBRARY_SUFFIX}"

set OUTPUTS_DIR "./outputs"
if {![file exists $OUTPUTS_DIR]} {file mkdir $OUTPUTS_DIR}

set REFERENCE_LIBRARY "/home1/14_nmts/14_nmts/stdcell_hvt/ndm/saed14hvt_frame_only.ndm \
/home1/14_nmts/14_nmts/stdcell_slvt/ndm/saed14slvt_frame_only.ndm \
/home1/14_nmts/14_nmts/stdcell_rvt/ndm/saed14rvt_frame_only.ndm \
/home1/14_nmts/14_nmts/stdcell_lvt/ndm/saed14lvt_frame_only.ndm"

set LINK_LIBRARY "/home1/14_nmts/14_nmts/stdcell_lvt/db_ccs/saed14lvt_ff0p7vm40c.db \
/home1/14_nmts/14_nmts/stdcell_rvt/db_ccs/saed14rvt_ff0p7vm40c.db \
/home1/14_nmts/14_nmts/stdcell_rvt/db_ccs/saed14rvt_ss0p6v125c.db \
/home1/14_nmts/14_nmts/stdcell_lvt/db_ccs/saed14lvt_ss0p6v125c.db"

set TECH_FILE "/home1/14_nmts/14_nmts/tech/milkyway/saed14nm_1p9m_mw.tf"

set VERILOG_NETLIST "/home1/IITR_PD3/MulukuriVNath/Documents/RTL-to-GDSII-Implementation-of-a-32-Point-Pipelined-FFT-Processor/Synthesis/outputs/FFT.mapped.v"
set SDC_FILE "/home1/IITR_PD3/MulukuriVNath/Documents/RTL-to-GDSII-Implementation-of-a-32-Point-Pipelined-FFT-Processor/Synthesis/scripts/FFT.sdc"
set UPF_FILE "/home1/IITR_PD3/MulukuriVNath/Documents/RTL-to-GDSII-Implementation-of-a-32-Point-Pipelined-FFT-Processor/Synthesis/scripts/FFT.upf"

set_app_var link_library "* $LINK_LIBRARY"
set target_library "$LINK_LIBRARY" ;# CMD-104 Fix: Used 'set' instead of 'set_app_var'

# ============================================================================
# 2. DESIGN SETUP & INGESTION
# ============================================================================
# FILE-005 Fix: Ensure the directory actually exists before creating the library
set WORK_DIR "./work"
if {![file exists $WORK_DIR]} {
    file mkdir $WORK_DIR
}

# Added -force to overwrite if you re-run the script
create_lib -ref_libs $REFERENCE_LIBRARY -technology $TECH_FILE ${WORK_DIR}/${DESIGN_LIBRARY} -force

read_verilog -top $DESIGN_NAME $VERILOG_NETLIST
current_design $DESIGN_NAME
link

# Load Low Power Intent (Golden UPF)
if {[file exists [which $UPF_FILE]]} {
    set_app_options -name mv.upf.enable_golden_upf -value true
    load_upf $UPF_FILE
    puts "Info: Running commit_upf"
    commit_upf
}

read_sdc $SDC_FILE

# ============================================================================
# 3. TLU+ PARASITIC FILES (ARRAY-BASED LOADING)
# ============================================================================
set parasitic1 "tlup_max"
set tluplus_file($parasitic1) "/home1/14_nmts/14_nmts/tech/star_rc/max/saed14nm_1p9m_Cmax.tluplus"
set layer_map_file($parasitic1) "/home1/14_nmts/14_nmts/tech/star_rc/saed14nm_tf_itf_tluplus.map"

set parasitic2 "tlup_min"
set tluplus_file($parasitic2) "/home1/14_nmts/14_nmts/tech/star_rc/min/saed14nm_1p9m_Cmin.tluplus"
set layer_map_file($parasitic2) "/home1/14_nmts/14_nmts/tech/star_rc/saed14nm_tf_itf_tluplus.map"

foreach p [array name tluplus_file] {
    puts "Info: read_parasitic_tech -tlup $tluplus_file($p) -layermap $layer_map_file($p) -name $p"
    read_parasitic_tech -tlup $tluplus_file($p) -layermap $layer_map_file($p) -name $p
}

set_parasitics_parameters \
    -early_spec tlup_min \
    -late_spec tlup_max \
    -early_temperature 40 \
    -late_temperature 125 \
    -corners {ss0p6v125c ff0p7vm40c}

set_voltage 0.6 -object_list {VDD SS_DEFAULT.power}
set_voltage 0.0 -object_list {VSS SS_DEFAULT.ground}
set_operating_conditions -max ss0p6v125c -min ff0p7vm40c

check_mv_design

# ============================================================================
# 4. FLOORPLANNING & TECHNOLOGY RULES
# ============================================================================
# Metal Layer Directions
define_user_attribute -type string -name routing_direction -classes routing_rule
set_attr -objects [get_layers {M2 M4 M6 M8 MRDL}] -name routing_direction -value horizontal
set_attr -objects [get_layers {M1 M5 M7 M9}] -name routing_direction -value vertical

# Floorplan Initialization
initialize_floorplan -core_utilization 0.55 -core_offset {2}

# Pin Constraints
set_block_pin_constraints -self -allowed_layers {M3 M5} -sides 2
place_pins -ports [get_ports -filter direction==out]
set_block_pin_constraints -self -allowed_layers {M4 M6} -sides 3
place_pins -ports [get_ports -filter direction==in]
set_attr [get_ports *] physical_status fixed

# Boundary & Tap Cells
set_boundary_cell_rules \
    -top_boundary_cells [get_lib_cells */*CAPT2] \
    -bottom_boundary_cells [get_lib_cells */*CAPB2] \
    -right_boundary_cell [get_lib_cells */*CAPBIN13] \
    -left_boundary_cell [get_lib_cells */*CAPBTAP6] \
    -prefix ENDCAP
compile_targeted_boundary_cells -target_objects [get_voltage_areas]

# Tap cell instantiation targeting specific library cell
create_tap_cells -lib_cell saed14lvt_ff0p7vm40c/SAEDLVT14_CAPTTAP6 -distance 30 -skip_fixed_cells

check_legality -cells [get_cells bound*]
check_legality -cells [get_cells tap*]
save_block -as 1_floorplan

# ============================================================================
# 5. POWER PLANNING (PG MESH)
# ============================================================================
set_attr [get_lib_cells */*TIE*] dont_touch false
set_lib_cell_purpose -include optimization [get_lib_cells */*TIE*]
set_attr [get_lib_cells */*AO*] dont_use true

connect_pg_net -automatic

# Upper Metal Mesh
create_pg_mesh_pattern Mesh_Upper -layers { \
    { {horizontal_layer: M9} {width: 0.12} {spacing: interleaving} {pitch: 4.8} {offset: 1.6} {trim:true} } \
    { {vertical_layer: M8} {width: 0.12} {spacing: interleaving} {pitch: 4.8} {offset: 1.6} {trim:true} } }
set_pg_strategy Strategy_Upper -core -pattern { {name: Mesh_Upper} {nets:{VDD VSS}} } -extension { {{stop:design_boundary_and_generate_pin}}}
compile_pg -strategies { Strategy_Upper }
create_pg_vias -nets {VDD VSS} -from_layers M5 -to_layers M9 -drc no_check

# Std Cell Rails
create_pg_std_cell_conn_pattern Stdcell -rail_width 0.094 -layers M1
set_pg_strategy StdCell_strat -pattern {{name: Stdcell} {nets: "VDD VSS"}} -core
compile_pg -strategies StdCell_strat
create_pg_vias -nets {VDD VSS} -from_layers M1 -to_layers M8 -drc no_check

check_pg_connectivity
check_pg_drc
save_block -as 2_powerplan

# ============================================================================
# 6. PLACEMENT & FUSION OPTIMIZATION
# ============================================================================
set_app_options -name place.coarse.max_density -value 0.65
set_app_options -name opt.common.enable_datapath_optimization -value true

set_attr [get_lib_cells *lvt*/*] threshold_voltage_group LVT
set_threshold_voltage_group_type -type low_vt LVT
set_multi_vth_constraint -low_vt_percentage 15 -cost cell_count

create_placement -congestion
check_legality -verbose

place_opt -to final_opto
connect_pg_net -automatic
save_block -as 3_placed

# ============================================================================
# 7. CLOCK TREE SYNTHESIS (CTS)
# ============================================================================
set_app_options -name cts.common.user_instance_name_prefix -value clock_opt_cts_
set_app_options -name opt.common.user_instance_name_prefix -value clock_opt_cts_opt_
set_app_options -name cts.common.max_fanout -value 32
set_app_options -name clock_opt.flow.enable_hold_routing -value true
set_app_options -name clock_opt.flow.enable_ccd -value true

clock_opt
connect_pg_net -automatic
save_block -as 4_cts

# ============================================================================
# 8. ROUTING & TIMING CLOSURE
# ============================================================================
set_app_options -name route.detail.timing_driven -value true
set_app_options -name route.track.timing_driven -value true
set_app_options -name route.track.crosstalk_driven -value true
set_app_options -name route.global.timing_driven -value true
set_app_options -name time.si_enable_analysis -value true
set_app_options -name time.enable_si_timing_windows -value true

set_ignored_layers -max_routing_layer M8 -min_routing_layer M2

route_auto
report_qor -summary
route_opt
connect_pg_net -automatic
save_block -as 5_routed

# ============================================================================
# 9. SIGNOFF & EXPORT
# ============================================================================
# Automatically grab SAED14 filler cells to fill gaps and prevent DRC errors
set filler_cells [get_lib_cells */*FILL* -filter "design_type == pad"]
if {[sizeof_collection $filler_cells] > 0} {
    create_stdcell_filler -lib_cells $filler_cells
    connect_pg_net -automatic
}

report_qor -summary > ${OUTPUTS_DIR}/${DESIGN_NAME}_qor.rpt
report_timing > ${OUTPUTS_DIR}/${DESIGN_NAME}_timing.rpt
report_constraints -all_violators > ${OUTPUTS_DIR}/${DESIGN_NAME}_violators.rpt

write_verilog ${OUTPUTS_DIR}/${DESIGN_NAME}_routed.v
write_gds ${OUTPUTS_DIR}/${DESIGN_NAME}.gds