# ============================================================================
# File    : run_fft_synth.tcl
# Purpose : High-Performance, Constraint-Driven Synthesis for 32-point FFT
# Design  : FFT (Top) with radix2, ROM_*, shift_* submodules
# Tool    : Synopsys Design Compiler (dc_shell) - Topographical Mode Ready
# Usage   : dc_shell -f scripts/run_fft_synth.tcl | tee logs/synth_fft.log
# ============================================================================

# --- Host Options (Multi-core) ---
set_host_options -max_cores 8

# ============================================================================
# 1. GLOBAL VARIABLES & PROJECT PATHS
# ============================================================================
set DESIGN_NAME "FFT"
set OUTPUTS_DIR "/home1/IITR_PD3/MulukuriVNath/Documents/RTL-to-GDSII-Implementation-of-a-32-Point-Pipelined-FFT-Processor/Synthesis/outputs"
set SCRIPTS "/home1/IITR_PD3/MulukuriVNath/Documents/RTL-to-GDSII-Implementation-of-a-32-Point-Pipelined-FFT-Processor/Synthesis/scripts"

# --- Design Flow Settings ---
set DESIGN_STYLE "flat"                    # Flat synthesis for standalone module
set PHYSICAL_HIERARCHY_LEVEL "top"
set DC_BLOCK_ABSTRACTION_DESIGNS ""
set DDC_HIER_DESIGNS ""
set UPF_MODE "golden"
set UPF_FILE ${SCRIPTS}/${DESIGN_NAME}.upf
set DCRM_NDM_LIBRARY_NAME ${DESIGN_NAME}.ndm

# ============================================================================
# 2. TECHNOLOGY & LIBRARY PATHS [USER: UPDATE THESE]
# ============================================================================
set TECH_FILE "/home1/14_nmts/14_nmts/tech/milkyway/saed14nm_1p9m_mw.tf"
set REFERENCE_LIBRARY "/home1/14_nmts/14_nmts/stdcell_hvt/ndm/saed14hvt_frame_only.ndm \
/home1/14_nmts/14_nmts/stdcell_slvt/ndm/saed14slvt_frame_only.ndm \
/home1/14_nmts/14_nmts/stdcell_rvt/ndm/saed14rvt_frame_only.ndm \
/home1/14_nmts/14_nmts/stdcell_lvt/ndm/saed14lvt_frame_only.ndm"

# ============================================================================
# 3. RTL SOURCE PATHS [USER: UPDATE THIS]
# ============================================================================
set RTL_SOURCE_PATH "/home1/IITR_PD3/MulukuriVNath/Documents/RTL-to-GDSII-Implementation-of-a-32-Point-Pipelined-FFT-Processor/RTL"

# Append to search path
set_app_var search_path "$search_path $RTL_SOURCE_PATH"

# Create output directory
if {![file exists $OUTPUTS_DIR]} {file mkdir $OUTPUTS_DIR}

# ============================================================================
# 4. ENABLE GOLDEN UPF MODE
# ============================================================================
if {$UPF_MODE == "golden"} {
  set_app_var enable_golden_upf true
}

# ============================================================================
# 5. LIBRARY SETUP
# ============================================================================
# [USER: Update target library paths to your SS corner .db files]
set TARGET_LIBRARY_FILES  "/home1/14_nmts/14_nmts/stdcell_rvt/db_ccs/saed14rvt_ss0p6v125c.db \
/home1/14_nmts/14_nmts/stdcell_lvt/db_ccs/saed14lvt_ss0p6v125c.db \
/home1/14_nmts/14_nmts/stdcell_hvt/db_ccs/saed14hvt_ss0p6v125c.db"

set_app_var target_library ${TARGET_LIBRARY_FILES}
set_app_var synthetic_library dw_foundation.sldb
set_app_var link_library "* $target_library $synthetic_library"

# --- Topographical Mode NDM Library Creation ---
if {[shell_is_in_topographical_mode]} {
  if {[info exists view_target] && [file exists $DCRM_NDM_LIBRARY_NAME]} {
    puts "RM-info: Opening existing NDM lib $DCRM_NDM_LIBRARY_NAME"
    open_lib $DCRM_NDM_LIBRARY_NAME
  } else {
    if {[file exists $DCRM_NDM_LIBRARY_NAME]} {
      puts "RM-info: Deleting existing NDM lib $DCRM_NDM_LIBRARY_NAME"
      file delete -force $DCRM_NDM_LIBRARY_NAME
    }
    set create_lib_cmd "create_lib -technology $TECH_FILE $DCRM_NDM_LIBRARY_NAME"
    if {${REFERENCE_LIBRARY} != ""} { append create_lib_cmd " -ref_libs \"${REFERENCE_LIBRARY}\""}
    puts "RM-info: Running $create_lib_cmd"
    eval ${create_lib_cmd}
  }
}

# --- Library Quality Checks ---
set set_check_library_cmd "set_check_library_options -mcmm"
if {$UPF_MODE != "none"} {lappend set_check_library_cmd -upf}
eval ${set_check_library_cmd}
redirect -file ${OUTPUTS_DIR}/${DESIGN_NAME}.check_library.rpt {check_library}

# ============================================================================
# 6. LIBRARY MODIFICATIONS (DONT_USE / OPTIMIZATION PREFS)
# ============================================================================
# [USER: Optional: source ${SCRIPTS}/dont_use.tcl if you have one]

# ============================================================================
# 7. TOOL SETTINGS & MESSAGE HANDLING
# ============================================================================
set_app_var sh_new_variable_message false
set_app_var auto_insert_level_shifters_on_clocks all
set_app_var spg_enable_via_resistance_support true

# --- Fix for Multiple Port Nets (Crucial for FFT to avoid netlist corruption) ---
set_fix_multiple_port_nets -all -buffer_constants

# --- Formality / LEC Setup ---
set_app_var simplified_verification_mode true
set_svf ${OUTPUTS_DIR}/${DESIGN_NAME}.mapped.svf

# ============================================================================
# 8. READ RTL DESIGN (ANALYZE & ELABORATE)
# ============================================================================
# Note: Order doesn't strictly matter for analyze, but top-level FFT.v is listed first for clarity.
#analyze -f verilog [glob $opensparc/lib/m1/*]
#analyze -f verilog [list \
    ${RTL_SOURCE_PATH}/FFT.v \
    ${RTL_SOURCE_PATH}/radix2.v \
    ${RTL_SOURCE_PATH}/ROM_16.v \
    ${RTL_SOURCE_PATH}/ROM_8.v \
    ${RTL_SOURCE_PATH}/ROM_4.v \
    ${RTL_SOURCE_PATH}/ROM_2.v \
    ${RTL_SOURCE_PATH}/shift_16.v \
    ${RTL_SOURCE_PATH}/shift_8.v \
    ${RTL_SOURCE_PATH}/shift_4.v \
    ${RTL_SOURCE_PATH}/shift_2.v \
    ${RTL_SOURCE_PATH}/shift_1.v ]

analyze -f verilog [glob $RTL_SOURCE_PATH/*.v]
elaborate ${DESIGN_NAME}
current_design ${DESIGN_NAME}
link

# ============================================================================
# 9. LOAD LOW-POWER INTENT (GOLDEN UPF)
# ============================================================================
set upf_create_implicit_supply_sets false

if {$UPF_MODE != "none"} {
  if {$UPF_FILE != ""} {
    set load_upf_cmd "load_upf ${UPF_FILE}"
    if {$UPF_MODE == "golden"} {lappend load_upf_cmd -strict_check true}
    puts "RM-info: Running $load_upf_cmd"
    eval ${load_upf_cmd}
  }
}

# ============================================================================
# 10. APPLY VOLTAGES (SUPPLEMENTAL UPF EQUIVALENT)
# ============================================================================
set_voltage 0.6 -object_list {VDD SS_DEFAULT.power}
set_voltage 0.0 -object_list {VSS SS_DEFAULT.ground}

# --- Multi-Voltage Integrity Check ---
set check_mv_design_failed false
if {[shell_is_in_topographical_mode]} {
  set current_scenario_saved [current_scenario]
  foreach scenario [all_active_scenarios] {
    current_scenario ${scenario}
    if {![check_mv_design -power_nets]} { set check_mv_design_failed true; break }
  }
  current_scenario ${current_scenario_saved}
} else {
  if {![check_mv_design -power_nets]} { set check_mv_design_failed true }
}
if {$check_mv_design_failed} {
  puts "RM-error: Supply nets missing voltage definitions. Exiting."
  exit 1
}

# ============================================================================
# 11. LOAD TIMING CONSTRAINTS (SDC)
# ============================================================================
# [USER: You must create ${SCRIPTS}/${DESIGN_NAME}.sdc]
# --- Example constraint inside that file (for reference):
#   create_clock -name clk -period 5.0 [get_ports clk]
#   set_input_delay -clock clk -max 0.5 [all_inputs]
#   set_output_delay -clock clk -max 0.5 [all_outputs]
#   set_max_area 0
# ---
source ${SCRIPTS}/${DESIGN_NAME}.sdc

# ============================================================================
# 12. PRE-COMPILE CHECKS & PATH GROUPING
# ============================================================================
check_design > ${OUTPUTS_DIR}/${DESIGN_NAME}.check_design.rpt
check_timing > ${OUTPUTS_DIR}/${DESIGN_NAME}.check_timing.rpt

# --- Group Paths for focused optimization ---
group_path -from [all_registers] -to [all_registers] -name reg2reg
group_path -from [all_registers] -to [all_outputs] -name reg2out
group_path -from [all_inputs] -to [all_registers] -name in2reg
group_path -from [all_inputs] -to [all_outputs] -name in2out

# ============================================================================
# 13. ANALYZE MV FEASIBILITY (CHECK PM CELL MAPPING)
# ============================================================================
#analyze_mv_feasibility > ${OUTPUTS_DIR}/${DESIGN_NAME}.analyze_mv_feasibility.rpt

# ============================================================================
# 14. HIGH-CONSTRAINT SYNTHESIS COMPILE
# ============================================================================
# IMPORTANT: -retime is intentionally omitted.
# The FFT relies on fixed 16/8/4/2/1 delay pipelines. Retiming would break
# these shift registers. -gate_clock is enabled for dynamic power reduction.
# -scan is enabled for ATPG / DFT readiness.

set compile_ultra_cmd "compile_ultra -gate_clock -scan"
if {[shell_is_in_topographical_mode]} {lappend compile_ultra_cmd -spg}
puts "RM-info: Running $compile_ultra_cmd (Note: -retime is disabled to preserve pipeline structure)"
eval ${compile_ultra_cmd}

# ============================================================================
# 15. POST-COMPILE NETLIST CLEANUP
# ============================================================================
if {$DESIGN_STYLE == "hier" && $PHYSICAL_HIERARCHY_LEVEL == "bottom"} {
  set_app_var uniquify_naming_style "${DESIGN_NAME}_%s_%d"
  uniquify -force
}

# --- Rename to Verilog-compliant syntax ---
change_names -rules verilog -hierarchy

# ============================================================================
# 16. WRITE REPORTS & ANALYZE QOR
# ============================================================================
write_parasitics -output ${OUTPUTS_DIR}/${DESIGN_NAME}.mapped.spef
write_link_library -out ${OUTPUTS_DIR}/${DESIGN_NAME}.link_library.tcl

# --- Comprehensive Timing Reports (per path group) ---
report_timing -group reg2reg -max_paths 100 > ${OUTPUTS_DIR}/${DESIGN_NAME}.reg2reg.rpt
report_timing -group in2reg -max_paths 100  > ${OUTPUTS_DIR}/${DESIGN_NAME}.in2reg.rpt
report_timing -group in2out -max_paths 100  > ${OUTPUTS_DIR}/${DESIGN_NAME}.in2out.rpt
report_timing -group reg2out -max_paths 100 > ${OUTPUTS_DIR}/${DESIGN_NAME}.reg2out.rpt

# --- Area, Power, and QoR Reports ---
report_area -hierarchy > ${OUTPUTS_DIR}/${DESIGN_NAME}.area.rpt
report_power > ${OUTPUTS_DIR}/${DESIGN_NAME}.power.rpt
report_qor > ${OUTPUTS_DIR}/${DESIGN_NAME}.qor.rpt

# --- Constraint Coverage Report ---
report_constraint -all_violators > ${OUTPUTS_DIR}/${DESIGN_NAME}.constraint_violators.rpt

# ============================================================================
# 16.5 CLEANUP FOR PHYSICAL DESIGN (FIX VO-4)
# ============================================================================
# Prevent tri-state logic and equation outputs
set verilogout_no_tri true
set verilogout_equation false
set verilogout_show_unconnected_pins true

# Re-apply the port net fix globally right before writing
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]

compile_ultra -incremental

change_names -rules verilog -hierarchy

# ============================================================================
# 17. WRITE FINAL MAPPED NETLISTS
# ============================================================================
# Power-aware netlist (with PG pins)
if {$UPF_MODE == "golden"} {
  write_file -format verilog -hierarchy -pg -output ${OUTPUTS_DIR}/${DESIGN_NAME}.mapped.pg.v
}

# Standard Verilog netlist (for simulation / synthesis)
write_file -format verilog -hierarchy -output ${OUTPUTS_DIR}/${DESIGN_NAME}.mapped.v

# DDC format (for Design Compiler / IC Compiler)
write_file -format ddc -hierarchy -output ${OUTPUTS_DIR}/${DESIGN_NAME}.mapped.ddc

# ============================================================================
# 18. SAVE UPDATED UPF & CLOSE SVF
# ============================================================================
if {$UPF_MODE != "none"} {
  set save_upf_cmd "save_upf"
  if {$UPF_MODE == "golden"} {
    lappend save_upf_cmd -include_supply_exceptions
    lappend save_upf_cmd -supplemental ${OUTPUTS_DIR}/${DESIGN_NAME}.supplement.upf
  } elseif {$UPF_MODE == "prime"} {
    lappend save_upf_cmd ${OUTPUTS_DIR}/${DESIGN_NAME}.mapped.upf
  }
  puts "RM-info: Running $save_upf_cmd"
  eval ${save_upf_cmd}
}

set_svf -off

# --- Save the physical NDM library (Topographical mode) ---
if {[shell_is_in_topographical_mode]} { save_lib }

puts "======================================================================"
puts "SYNTHESIS COMPLETED SUCCESSFULLY FOR DESIGN: ${DESIGN_NAME}"
puts "Reports Location: ${OUTPUTS_DIR}"
puts "Netlist Location: ${OUTPUTS_DIR}/${DESIGN_NAME}.mapped.v"
puts "======================================================================"