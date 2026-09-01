# 50 MHz clock — adjust to your board oscillator
create_clock -name clk -period 20.000 [get_ports {clk}]

set_false_path -from [get_ports {rst_n}]
set_input_delay  -clock clk 2.0 [get_ports {sample_en reference_in primary_in}]
set_output_delay -clock clk 2.0 [get_ports {anc_out noise_est output_valid input_ready mu_debug}]
