// 32GFC rate match on the 66-bit block stream.
//
// A 28.05G client rides one 58G system lane. fc_rate_tx inserts one IDLE
// after every block; fc_rate_rx removes that IDLE by position. The IDLE is a
// legal control block, so block lock stays up, and it is deleted before the
// link machine and the frame pipe. 64GFC and 128GFC leave both sides as wires.
// The insert sits in front of the 256b/257b transcode, so a packed group is
// still four beats and the RS(544,514) codeword stays contiguous.
// fc_port resets both sides before it changes half, so the phase restarts
// on a block boundary with the lane FIFOs empty.

module fc_rate_tx (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        half,
  input  logic        in_valid,
  output logic        in_ready,
  input  logic [1:0]  in_sync,
  input  logic [63:0] in_data,
  output logic        out_valid,
  input  logic        out_ready,
  output logic [1:0]  out_sync,
  output logic [63:0] out_data
);
  `include "fc128_defs.vh"

  logic phase;

  assign in_ready  = half ? (!phase && out_ready) : out_ready;
  assign out_valid = half ? (phase || in_valid) : in_valid;
  assign out_sync  = (half && phase) ? FC_SYNC_CTRL : in_sync;
  assign out_data  = (half && phase) ? {32'h0, FC_IDLE} : in_data;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      phase <= 1'b0;
    else if (!half)
      phase <= 1'b0;
    else if (out_valid && out_ready)
      phase <= ~phase;
  end
endmodule

module fc_rate_rx (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        half,
  input  logic        in_valid,
  output logic        in_ready,
  input  logic [1:0]  in_sync,
  input  logic [63:0] in_data,
  output logic        out_valid,
  input  logic        out_ready,
  output logic [1:0]  out_sync,
  output logic [63:0] out_data
);
  logic phase;

  assign in_ready  = half ? (phase ? 1'b1 : out_ready) : out_ready;
  assign out_valid = half ? (!phase && in_valid) : in_valid;
  assign out_sync  = in_sync;
  assign out_data  = in_data;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      phase <= 1'b0;
    else if (!half)
      phase <= 1'b0;
    else if (in_valid && in_ready)
      phase <= ~phase;
  end
endmodule
