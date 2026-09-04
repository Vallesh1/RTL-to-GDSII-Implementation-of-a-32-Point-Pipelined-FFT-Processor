# ============================================================================
# FUSION COMPILER PNR SCRIPT - 32-POINT FFT
# ============================================================================
set_host_options -max_cores 8

# ============================================================================
# 1. GLOBAL VARIABLES & PATHS (USER DEFINED)
# ============================================================================
set DESIGN_NAME "FFT"
set LIBRARY_SUFFIX "_lib"
set DESIGN_LIBRARY "${DESIGN_NAME}${LIBRARY_SUFFIX}"

set REFERENCE_LIBRARY "<ADD_HVT_NDM_PATH> \
<ADD_SLVT_NDM_PATH> \
<ADD_RVT_NDM_PATH> \
<ADD_LVT_NDM_PATH>"

set LINK_LIBRARY "<ADD_LVT_DB_PATH> \
<ADD_RVT_DB_PATH>"

set TECH_FILE "<ADD_TF_PATH>"
set VERILOG_NETLIST "<ADD_MAPPED_V_PATH>"
set SDC_FILE "<ADD_SDC_PATH>"
set UPF_FILE "<ADD_UPF_PATH>"

set_app_var link_library "* $LINK_LIBRARY"
set_app_var target_library "$LINK_LIBRARY"

# ============================================================================
# 2. DESIGN SETUP & INGESTION
# ============================================================================
create_lib -ref_libs $REFERENCE_LIBRARY -technology $TECH_FILE ./work/${DESIGN_LIBRARY}
read_verilog -top $DESIGN_NAME $VERILOG_NETLIST
current_design $DESIGN_NAME
link

# Load Low Power Intent (Golden UPF)
if {[file exists [which $UPF_FILE]]} {
    set_app_options -name mv.upf.enable_golden_upf -value true
    load_upf $UPF_FILE
    commit_upf
}

# Load Constraints
read_sdc $SDC_FILE

# Load Parasitic Technology (TLU+)
set parasitic_max_tlup "<ADD_MAX_TLUP_PATH>"
set parasitic_min_tlup "<ADD_MIN_TLUP_PATH>"
set layer_map_file "<ADD_MAP_PATH>"

read_parasitic_tech -tlup $parasitic_max_tlup -layermap $layer_map_file -name tlup_max
read_parasitic_tech -tlup $parasitic_min_tlup -layermap $layer_map_file -name tlup_min

set_parasitics_parameters -early_spec tlup_max -late_spec tlup_max \
    -early_temperature 125 -late_temperature 125 -corners {ss0p6v125c}

check_mv_design

# ============================================================================
# 3. FLOORPLANNING
# ============================================================================
initialize_floorplan -core_utilization 0.55 -shape R -side_length_ratio {1.0 1.0} -core_offset 2.0

set_block_pin_constraints -self -allowed_layers {M3 M5} -sides 2
place_pins -ports [get_ports -filter direction==out]
set_block_pin_constraints -self -allowed_layers {M4 M6} -sides 3
place_pins -ports [get_ports -filter direction==in]
set_attr [get_ports *] physical_status fixed

set_boundary_cell_rules \
    -top_boundary_cells [get_lib_cells */*CAPT2] \
    -bottom_boundary_cells [get_lib_cells */*CAPB2] \
    -right_boundary_cell [get_lib_cells */*CAPBIN13] \
    -left_boundary_cell [get_lib_cells */*CAPBTAP6] \
    -prefix ENDCAP
compile_targeted_boundary_cells -target_objects [get_voltage_areas]
add_tap_cells -lib_cell <ADD_TAP_CELL_NAME> -distance 20

check_legality -cells [get_cells bound*]
check_legality -cells [get_cells tap*]
save_block -as 1_floorplan

# ============================================================================
# 4. POWER PLANNING (PG MESH)
# ============================================================================
set_attr [get_lib_cells */*TIE*] dont_touch false
set_lib_cell_purpose -include optimization [get_lib_cells */*TIE*]

create_pg_mesh_pattern Mesh_Upper -layers { \
    { {horizontal_layer: M9} {width: 0.12} {spacing: interleaving} {pitch: 4.8} {offset: 1.6} {trim:true} } \
    { {vertical_layer: M8} {width: 0.12} {spacing: interleaving} {pitch: 4.8} {offset: 1.6} {trim:true} } }
set_pg_strategy Strategy_Upper -core -pattern { {name: Mesh_Upper} {nets:{VDD VSS}} } -extension { {{stop:design_boundary_and_generate_pin}}}
compile_pg -strategies { Strategy_Upper }
create_pg_vias -nets {VDD VSS} -from_layers M5 -to_layers M9 -drc no_check

create_pg_std_cell_conn_pattern Stdcell -rail_width 0.094 -layers M1
set_pg_strategy StdCell_strat -pattern {{name: Stdcell} {nets: "VDD VSS"}} -core
compile_pg -strategies StdCell_strat
create_pg_vias -nets {VDD VSS} -from_layers M1 -to_layers M8 -drc no_check

check_pg_connectivity
check_pg_drc
save_block -as 2_powerplan

# ============================================================================
# 5. PLACEMENT & FUSION OPTIMIZATION
# ============================================================================
# FC-specific datapath & congestion controls
set_app_options -name place.coarse.max_density -value 0.65
set_app_options -name place.coarse.congestion_driven_max_util -value 0.70
set_app_options -name opt.common.enable_datapath_optimization -value true

set_attr [get_lib_cells *lvt*/*] threshold_voltage_group LVT
set_threshold_voltage_group_type -type low_vt LVT
set_multi_vth_constraint -low_vt_percentage 15 -cost cell_count

create_placement -congestion
check_legality -verbose

# place_opt automatically leverages Fusion Compiler's logic restructuring
place_opt
save_block -as 3_placed

# ============================================================================
# 6. CLOCK TREE SYNTHESIS (CTS)
# ============================================================================
set_app_options -name cts.common.max_fanout -value 32
set_app_options -name clock_opt.flow.enable_hold_routing -value true
set_app_options -name clock_opt.flow.enable_ccd -value true ;# Enable Concurrent Clock and Data optimization

# Define Clock NDRs for shift-register crosstalk mitigation
create_routing_rule CLK_NDR -widths {M3 0.1 M4 0.1 M5 0.1} -spacings {M3 0.1 M4 0.1 M5 0.1}
set_clock_routing_rules -clocks [get_clocks *] -rules CLK_NDR -min_routing_layer M3 -max_routing_layer M7

clock_opt
save_block -as 4_cts

# ============================================================================
# 7. ROUTING & TIMING CLOSURE
# ============================================================================
set_app_options -name route.detail.timing_driven -value true
set_app_options -name route.track.timing_driven -value true
set_app_options -name route.track.crosstalk_driven -value true
set_app_options -name time.si_enable_analysis -value true
set_app_options -name route.detail.insert_diodes_during_routing -value true

set_ignored_layers -max_routing_layer M8 -min_routing_layer M2

route_auto
route_opt -cleanup
save_block -as 5_routed

# ============================================================================
# 8. SIGNOFF & DATABASE EXPORT
# ============================================================================
create_stdcell_filler -lib_cells <ADD_FILLER_CELLS>
connect_pg_net -automatic

report_qor -summary > ./reports/fft_qor.rpt
report_timing > ./reports/fft_timing.rpt
report_constraints -all_violators > ./reports/fft_violators.rpt

write_verilog ./outputs/${DESIGN_NAME}_routed.v
write_gds ./outputs/${DESIGN_NAME}.gds