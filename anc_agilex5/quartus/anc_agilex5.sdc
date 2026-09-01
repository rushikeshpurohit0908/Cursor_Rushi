# Timing constraints — Agilex 5 ANC (100 MHz fabric, 48 kHz I2S)

create_clock -name sys_clk -period 10.000 [get_ports sys_clk]

# Generated audio clocks (approximate integer divide from 100 MHz)
create_generated_clock -name mclk -source [get_ports sys_clk] \
    -divide_by 8 [get_ports mclk]
create_generated_clock -name bclk -source [get_ports sys_clk] \
    -divide_by 32 [get_ports bclk]
create_generated_clock -name lrck -source [get_ports sys_clk] \
    -divide_by 2083 [get_ports lrck]

set_clock_groups -asynchronous \
    -group [get_clocks sys_clk] \
    -group [get_clocks {mclk bclk lrck}]

set_false_path -from [get_ports i2s_adc_data]
set_false_path -to   [get_ports i2s_dac_data]
set_false_path -from [get_ports reset_n]
set_false_path -to   [get_ports {anc_active_led clip_led codec_ready_led}]
set_false_path -to   [get_ports {i2c_scl i2c_sda}]
set_false_path -from [get_ports {i2c_scl i2c_sda}]

set_input_delay  -clock bclk -max 2.0 [get_ports i2s_adc_data]
set_output_delay -clock bclk -max 2.0 [get_ports i2s_dac_data]
