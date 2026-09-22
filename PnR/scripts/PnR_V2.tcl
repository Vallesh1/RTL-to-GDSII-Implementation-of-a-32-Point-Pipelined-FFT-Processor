# ============================================================================
# FUSION COMPILER: RTL-TO-GDSII FULL BACKEND SCRIPT (SAED 14nm)
# Design: 32-Point Pipelined FFT Processor
# ============================================================================

# ----------------------------------------------------------------------------
# 0. DIRECTORY ARCHITECTURE
# ----------------------------------------------------------------------------
set DESIGN_NAME "FFT"
set DESIGN_LIBRARY "./${DESIGN_NAME}_lib.ndm" ;# Stays in current (work) directory
set OUTPUT_DIR "../outputs"                  ;# Created one directory backward

# Create the external output directory if it does not exist
if {![file exists $OUTPUT_DIR]} { file mkdir $OUTPUT_DIR }

# ----------------------------------------------------------------------------
# 1. DATABASE SETUP & LIBRARY CREATION
# ----------------------------------------------------------------------------
close_lib -all
if {[file exists $DESIGN_LIBRARY]} { file delete -force $DESIGN_LIBRARY }

# Explicitly link technology file to prevent UIED-380
create_lib -ref_libs $REFERENCE_LIBRARY -technology $TECH_FILE $DESIGN_LIBRARY
read_verilog -top $DESIGN_NAME $VERILOG_NETLIST
current_design $DESIGN_NAME
link

# Fix frame-to-tech via regions
derive_design_level_via_regions

# ----------------------------------------------------------------------------
# 2. TLU+ PARASITIC LOADING
# ----------------------------------------------------------------------------
set parasitic1 "tlup_max"
set tluplus_file($parasitic1) "/home1/14_nmts/14_nmts/tech/star_rc/max/saed14nm_1p9m_Cmax.tluplus"
set layer_map_file($parasitic1) "/home1/14_nmts/14_nmts/tech/star_rc/saed14nm_tf_itf_tluplus.map"

set parasitic2 "tlup_min"
set tluplus_file($parasitic2) "/home1/14_nmts/14_nmts/tech/star_rc/min/saed14nm_1p9m_Cmin.tluplus"
set layer_map_file($parasitic2) "/home1/14_nmts/14_nmts/tech/star_rc/saed14nm_tf_itf_tluplus.map"

foreach p [array name tluplus_file] {
    read_parasitic_tech -tlup $tluplus_file($p) -layermap $layer_map_file($p) -name $p
}

# ----------------------------------------------------------------------------
# 3. MCMM TIMING CORNERS & CONSTRAINTS
# ----------------------------------------------------------------------------
create_corner ss0p6v125c
create_corner ff0p7vm40c

set_parasitics_parameters -early_spec tlup_min -late_spec tlup_max \
    -early_temperature -40 -late_temperature 125 \
    -corners {ss0p6v125c ff0p7vm40c}

# Max Corner (Setup)
set_temperature 125 -corner ss0p6v125c
set_voltage 0.6 -object_list {VDD SS_DEFAULT.power} -corner ss0p6v125c
set_voltage 0.0 -object_list {VSS SS_DEFAULT.ground} -corner ss0p6v125c

# Min Corner (Hold)
set_temperature -40 -corner ff0p7vm40c
set_voltage 0.7 -object_list {VDD SS_DEFAULT.power} -corner ff0p7vm40c
set_voltage 0.0 -object_list {VSS SS_DEFAULT.ground} -corner ff0p7vm40c

read_sdc $SDC_FILE

# Bypass SDC parser limits for multicycle paths
set raw_start [get_cells -hierarchical *count_y_reg*]
set raw_end   [get_cells -hierarchical *result_*_reg*]
set icg_cells [get_cells -hierarchical *clk_gate*]
set clean_start [remove_from_collection $raw_start $icg_cells]
set clean_end   [remove_from_collection $raw_end $icg_cells]

set_multicycle_path -setup 2 -from $clean_start -to $clean_end
set_multicycle_path -hold 1  -from $clean_start -to $clean_end

save_block -as 1_setup

# ----------------------------------------------------------------------------
# 4. FLOORPLANNING & PIN PLACEMENT
# ----------------------------------------------------------------------------
define_user_attribute -type string -name routing_direction -classes routing_rule
set_attr -objects [get_layers {M2 M4 M6 M8 MRDL}] -name routing_direction -value horizontal
set_attr -objects [get_layers {M1 M5 M7 M9}] -name routing_direction -value vertical

initialize_floorplan -core_utilization 0.55 -core_offset {2}

set_block_pin_constraints -self -allowed_layers {M3 M5} -sides 2
place_pins -ports [get_ports -filter direction==out]
set_block_pin_constraints -self -allowed_layers {M4 M6} -sides 3
place_pins -ports [get_ports -filter direction==in]
set_attr [get_ports *] physical_status fixed

save_block -as 2_floorplan

# ----------------------------------------------------------------------------
# 5. POWER PLANNING (3-TIER PG MESH)
# ----------------------------------------------------------------------------
connect_pg_net -automatic

create_pg_std_cell_conn_pattern m1_rails -layers M1
create_pg_mesh_pattern m5_straps -layers { {vertical_layer: M5 width: 0.2 pitch: 5 offset: 1} }
create_pg_mesh_pattern top_mesh -layers { 
    {horizontal_layer: M8 width: 0.6 pitch: 10 offset: 2} 
    {vertical_layer: M9 width: 1.2 pitch: 20 offset: 4} 
}

set_pg_strategy strat_rails -core -pattern { {name: m1_rails} {nets: {VDD VSS}} }
set_pg_strategy strat_m5 -core -pattern { {name: m5_straps} {nets: {VDD VSS}} }
set_pg_strategy strat_top -core -pattern { {name: top_mesh} {nets: {VDD VSS}} }

# Automatically generates all intermediate vias across the stack
compile_pg -strategies {strat_top strat_m5 strat_rails}

save_block -as 3_powerplan

# ----------------------------------------------------------------------------
# 6. PHYSICAL CELLS & PLACEMENT
# ----------------------------------------------------------------------------
# NOTE: Replace 'TAP_CELL_NAME' and 'ENDCAP_CELL_NAME' with actual SAED14 physical cell names
# set_boundary_cell_rules -left_boundary_cell ENDCAP_CELL_NAME -right_boundary_cell ENDCAP_CELL_NAME
# compile_boundary_cells
# create_tap_cells -lib_cell TAP_CELL_NAME -distance 30

check_design -checks pre_placement_stage
place_opt

save_block -as 4_placement

# ----------------------------------------------------------------------------
# 7. CLOCK TREE SYNTHESIS (CTS)
# ----------------------------------------------------------------------------
check_design -checks pre_clock_tree_stage
clock_opt

save_block -as 5_cts

# ----------------------------------------------------------------------------
# 8. ROUTING & POST-ROUTE OPTIMIZATION
# ----------------------------------------------------------------------------
check_design -checks pre_route_stage
route_auto
route_opt

save_block -as 6_routed

# ----------------------------------------------------------------------------
# 9. FINISHING, PHYSICAL VERIFICATION & EXPORTS
# ----------------------------------------------------------------------------
# Insert standard cell fillers (Replace generic names with SAED14 specific fillers)
# create_stdcell_fillers -lib_cells {FILLER_1 FILLER_2 FILLER_4 FILLER_8}
# connect_pg_net -automatic

check_routes

save_block -as 7_final

# Export final files to the external output directory (../outputs)
write_gds -design $DESIGN_NAME -merge_files $REFERENCE_LIBRARY $OUTPUT_DIR/${DESIGN_NAME}_final.gds
write_parasitics -format SPEF -output $OUTPUT_DIR/${DESIGN_NAME}_final.spef
write_verilog -include {pg_netlist} $OUTPUT_DIR/${DESIGN_NAME}_final_pg.v