set CLK_PERIOD 5.0
set CLK_NAME   clk

create_clock -name ${CLK_NAME} -period ${CLK_PERIOD} [get_ports clk]

set_clock_latency -source 0.1 [get_clocks ${CLK_NAME}]
set_clock_latency 0.2 [get_clocks ${CLK_NAME}]

set_clock_uncertainty -setup 0.4 [get_clocks ${CLK_NAME}]
set_clock_uncertainty -hold 0.15 [get_clocks ${CLK_NAME}]

set_input_delay -clock ${CLK_NAME} -max 0.7 [get_ports {din_r[*] din_i[*] in_valid}]
set_input_delay -clock ${CLK_NAME} -min 0.2 [get_ports {din_r[*] din_i[*] in_valid}]

set_output_delay -clock ${CLK_NAME} -max 0.8 [get_ports {dout_r[*] dout_i[*] out_valid}]
set_output_delay -clock ${CLK_NAME} -min 0.2 [get_ports {dout_r[*] dout_i[*] out_valid}]

set_input_transition 0.2 [all_inputs]
set_load 0.05 [all_outputs]

set_max_transition 0.3 [current_design]
set_max_capacitance 0.1 [current_design]
set_max_fanout 30 [current_design]

group_path -name CRITICAL_R2R -from [all_registers] -to [all_registers] -weight 2.0
group_path -name IO_IN2OUT -from [all_inputs] -to [all_outputs] -weight 1.0
group_path -name IO_IN2REG -from [all_inputs] -to [all_registers] -weight 1.0
group_path -name IO_REG2OUT -from [all_registers] -to [all_outputs] -weight 1.0

set_false_path -from [get_ports reset] -to [all_registers]

# Removed the submodule wildcard (*/*) and switched to get_cells for robust targeting
set_multicycle_path -setup 2 -from [get_cells *count_y_reg*] -to [get_cells *result_*_reg*]
set_multicycle_path -hold 1 -from [get_cells *count_y_reg*] -to [get_cells *result_*_reg*]

set_clock_gating_check -setup 0.15 -hold 0.05 [get_clocks ${CLK_NAME}]
