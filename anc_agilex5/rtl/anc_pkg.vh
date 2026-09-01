// Shared register offsets, control bits, and mode encodings.
// Keep in sync with software/anc_control/fpga_bridge.py and
// software/baremetal/anc_regs.h

`ifndef ANC_PKG_VH
`define ANC_PKG_VH

// Register offsets (byte addresses on AXI4-Lite)
`define ANC_REG_CONTROL        8'h00
`define ANC_REG_STATUS         8'h04
`define ANC_REG_MU             8'h08
`define ANC_REG_MEM_ADDR       8'h0C
`define ANC_REG_MEM_DATA       8'h10
`define ANC_REG_SAMPLE_COUNT   8'h14
`define ANC_REG_AI_OVERRIDE    8'h18
`define ANC_REG_OUTPUT_GAIN    8'h1C
`define ANC_REG_MEM_SEL        8'h20
`define ANC_REG_LEAK           8'h24
`define ANC_REG_MODE           8'h28
`define ANC_REG_I2C_CTRL       8'h2C
`define ANC_REG_I2C_DATA       8'h30
`define ANC_REG_NOTCH_FREQ     8'h34
`define ANC_REG_VERSION        8'h3C

// CONTROL bits
`define ANC_CTRL_ENABLE        0
`define ANC_CTRL_BYPASS        1
`define ANC_CTRL_RESET_ADAPT   2
`define ANC_CTRL_CODEC_INIT    3
`define ANC_CTRL_NOTCH_EN      4

// MODE values
`define ANC_MODE_HYBRID        32'd0
`define ANC_MODE_FF_FROZEN     32'd1
`define ANC_MODE_FF_VIRTUAL    32'd2
`define ANC_MODE_CALIB         32'd3

// MEM_SEL values
`define ANC_MEM_SECONDARY      32'd0
`define ANC_MEM_ADAPTIVE       32'd1
`define ANC_MEM_PRIMARY        32'd2

// VERSION: major=2 (full design), minor=0
`define ANC_VERSION            32'h0002_0000

`endif
