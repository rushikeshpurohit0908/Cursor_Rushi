# Generate Platform Designer system: Agilex 5 HPS + LWH2F + anc_board.
#
#   qsys-script --script=anc_platform.tcl --quartus-project=../quartus/anc_agilex5.qpf
#
# After generation, add the exported I2S/I2C/LED conduits to the board top
# and compile in Quartus.

package require -exact qsys 24.3

create_system anc_platform

set_project_property DEVICE_FAMILY "Agilex 5"
set_project_property DEVICE A5ED065BB32AE4S

# Clock
add_instance sys_clk clock_source
set_instance_parameter_value sys_clk clockFrequency {100000000}
set_instance_parameter_value sys_clk clockFrequencyKnown {true}
set_instance_parameter_value sys_clk resetSynchronousEdges {DEASSERT}

# HPS (Agilex 5 hard processor) — lightweight H2F exported for CSR
# Component name may be "intel_agilex_5_soc_hps" depending on Quartus version.
# If the IP name differs, add HPS from the GUI and reconnect lwh2f_axi_master.
add_instance anc anc_board
set_instance_parameter_value anc CODEC_SEL {0}

# Connect clock / reset
add_connection sys_clk.clk       anc.clk
add_connection sys_clk.clk_reset anc.reset

# Export interfaces
set_interface_property clk      EXPORT_OF sys_clk.clk_in
set_interface_property reset    EXPORT_OF sys_clk.clk_in_reset
set_interface_property s_axi    EXPORT_OF anc.s_axi
set_interface_property audio    EXPORT_OF anc.audio
set_interface_property leds     EXPORT_OF anc.leds

set_connection_parameter_value sys_clk.clk/anc.clk endError {1}
set_module_assignment embeddedsw.configuration.generateDeviceTreeOverlay {1}

save_system anc_platform.qsys

puts "Wrote anc_platform.qsys — open in Platform Designer to attach Agilex 5 HPS"
puts "LWH2F master -> anc.s_axi at offset 0x0000_0000 (HPS phys 0x2000_0000)"
