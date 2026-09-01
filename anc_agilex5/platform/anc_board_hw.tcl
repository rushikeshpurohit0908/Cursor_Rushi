# Platform Designer _hw.tcl — wrap anc_board as a custom Qsys component.
# File → New Component → load this TCL, or:
#   qsys-script --script=anc_platform.tcl

package require -exact qsys 24.3

set_module_property NAME anc_board
set_module_property VERSION 2.0
set_module_property DISPLAY_NAME "Agilex 5 ANC Board"
set_module_property DESCRIPTION "Real-time FxLMS ANC with I2S, I2C codec, AI classifier"
set_module_property GROUP "DSP/Audio"
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE true

add_fileset QUARTUS_SYNTH QUARTUS_SYNTH "" ""
set_fileset_property QUARTUS_SYNTH TOP_LEVEL anc_board
add_fileset_file anc_pkg.vh              VERILOG PATH ../rtl/anc_pkg.vh
add_fileset_file audio_clock_gen.v       VERILOG PATH ../rtl/audio_clock_gen.v
add_fileset_file i2s_rx.v                VERILOG PATH ../rtl/i2s_rx.v
add_fileset_file i2s_tx.v                VERILOG PATH ../rtl/i2s_tx.v
add_fileset_file audio_sync_fifo.v       VERILOG PATH ../rtl/audio_sync_fifo.v
add_fileset_file fir_mac_engine.v        VERILOG PATH ../rtl/fir_mac_engine.v
add_fileset_file secondary_path_fir.v    VERILOG PATH ../rtl/secondary_path_fir.v
add_fileset_file fxlms_engine.v          VERILOG PATH ../rtl/fxlms_engine.v
add_fileset_file spectral_features.v     VERILOG PATH ../rtl/spectral_features.v
add_fileset_file ai_noise_classifier.v   VERILOG PATH ../rtl/ai_noise_classifier.v
add_fileset_file notch_iir.v             VERILOG PATH ../rtl/notch_iir.v
add_fileset_file i2c_master.v            VERILOG PATH ../rtl/i2c_master.v
add_fileset_file codec_init.v            VERILOG PATH ../rtl/codec_init.v
add_fileset_file anc_control_regs.v      VERILOG PATH ../rtl/anc_control_regs.v
add_fileset_file anc_top.v               VERILOG PATH ../rtl/anc_top.v
add_fileset_file anc_board.v             VERILOG PATH ../rtl/anc_board.v

add_parameter CODEC_SEL INTEGER 0
set_parameter_property CODEC_SEL DISPLAY_NAME "Codec"
set_parameter_property CODEC_SEL ALLOWED_RANGES {"0:SSM2518" "1:WM8960" "2:Pmod I2S2 (no I2C)"}
set_parameter_property CODEC_SEL HDL_PARAMETER true

add_interface clk clock end
add_interface_port clk sys_clk clk Input 1

add_interface reset reset end
set_interface_property reset associatedClock clk
add_interface_port reset reset_n reset_n Input 1

add_interface s_axi axi4lite end
set_interface_property s_axi associatedClock clk
set_interface_property s_axi associatedReset reset
add_interface_port s_axi s_axi_awvalid awvalid Input 1
add_interface_port s_axi s_axi_awready awready Output 1
add_interface_port s_axi s_axi_awaddr  awaddr  Input 8
add_interface_port s_axi s_axi_wvalid  wvalid  Input 1
add_interface_port s_axi s_axi_wready  wready  Output 1
add_interface_port s_axi s_axi_wdata   wdata   Input 32
add_interface_port s_axi s_axi_wstrb   wstrb   Input 4
add_interface_port s_axi s_axi_arvalid arvalid Input 1
add_interface_port s_axi s_axi_arready arready Output 1
add_interface_port s_axi s_axi_araddr  araddr  Input 8
add_interface_port s_axi s_axi_rvalid  rvalid  Output 1
add_interface_port s_axi s_axi_rready  rready  Input 1
add_interface_port s_axi s_axi_rdata   rdata   Output 32

add_interface audio conduit end
add_interface_port audio mclk         mclk         Output 1
add_interface_port audio bclk         bclk         Output 1
add_interface_port audio lrck         lrck         Output 1
add_interface_port audio i2s_adc_data i2s_adc_data Input  1
add_interface_port audio i2s_dac_data i2s_dac_data Output 1
add_interface_port audio i2c_scl      i2c_scl      Bidir  1
add_interface_port audio i2c_sda      i2c_sda      Bidir  1

add_interface leds conduit end
add_interface_port leds anc_active_led  anc_active_led  Output 1
add_interface_port leds clip_led        clip_led        Output 1
add_interface_port leds codec_ready_led codec_ready_led Output 1
