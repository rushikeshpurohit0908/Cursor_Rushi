// AI-ANC FPGA global parameters
`ifndef ANC_PKG_V
`define ANC_PKG_V

`define ANC_DATA_W      16
`define ANC_FRAC_BITS   15
`define ANC_FILTER_TAPS 32
`define ANC_BLOCK_SIZE  512
`define ANC_NUM_FEAT    8
`define ANC_HIDDEN      16
`define ANC_MLP_OUT     2
`define ANC_ACC_W       40

// mu = 0.001 + 0.199 * sigmoid(out0)  in Q1.15
`define ANC_MU_MIN_Q15   16'd33
`define ANC_MU_SPAN_Q15  16'd6522

// gain = 0.90 + 0.20 * sigmoid(out1)
`define ANC_GAIN_MIN_Q15  16'd29491
`define ANC_GAIN_SPAN_Q15 16'd6554

`define ANC_NORM_EPS     24'd64

`endif
