# ============================================================================
# FFT.sdc (Pure SDC 2.1 Format)
# Complete SDC Constraints for 32-Point Pipelined FFT Processor
# ============================================================================
set_units -time ns -resistance MOhm -capacitance fF -voltage V -current uA

create_clock -name clk -period 5.0 [get_ports clk]

set_clock_latency -source 0.1 [get_clocks clk]
set_clock_latency 0.2 [get_clocks clk]

set_clock_uncertainty -setup 0.4 [get_clocks clk]
set_clock_uncertainty -hold 0.15 [get_clocks clk]

set_input_delay -clock clk -max 0.7 [get_ports {din_r[*] din_i[*] in_valid}]
set_input_delay -clock clk -min 0.2 [get_ports {din_r[*] din_i[*] in_valid}]

set_output_delay -clock clk -max 0.8 [get_ports {dout_r[*] dout_i[*] out_valid}]
set_output_delay -clock clk -min 0.2 [get_ports {dout_r[*] dout_i[*] out_valid}]

set_input_transition 0.2 [all_inputs]
set_load 0.05 [all_outputs]

set_max_transition 0.3 [current_design]
set_max_capacitance 0.1 [current_design]

group_path -name CRITICAL_R2R -from [all_registers] -to [all_registers] -weight 2.0
group_path -name IO_IN2OUT -from [all_inputs] -to [all_outputs] -weight 1.0
group_path -name IO_IN2REG -from [all_inputs] -to [all_registers] -weight 1.0
group_path -name IO_REG2OUT -from [all_registers] -to [all_outputs] -weight 1.0

set_false_path -from [get_ports reset] -to [all_registers]

set_multicycle_path -setup 2 -from [get_cells -hierarchical *count_y_reg*] -to [get_cells -hierarchical *result_*_reg*]
set_multicycle_path -hold 1  -from [get_cells -hierarchical *count_y_reg*] -to [get_cells -hierarchical *result_*_reg*]

set_clock_gating_check -setup 0.15 -hold 0.05 [get_clocks clk]
