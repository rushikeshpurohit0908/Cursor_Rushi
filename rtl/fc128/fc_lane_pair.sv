// Bonded pair of system lanes.
// stripe selects the line rate's lane map. 128GFC stripes one client block
// stream even/odd across the two 58G lanes (116G aggregate, about 3.3% above
// the 112.2G line rate). 64GFC and 32GFC keep lane 0 and leave lane 1 empty.
// The async FIFOs absorb the clock ratio. The stripe phase advances only on
// a transfer, so the lane occupancies stay within one block of each other.

module fc_pair_split #(
  parameter int DEPTH = 32
) (
  input  logic             clk_wr,
  input  logic             rst_wr_n,
  input  logic             clk_rd,
  input  logic             rst_rd_n,
  input  logic             stripe,
  input  logic             wr_valid,
  output logic             wr_ready,
  input  logic [1:0]       wr_sync,
  input  logic [63:0]      wr_data,
  output logic [1:0]       rd_valid,
  input  logic [1:0]       rd_ready,
  output logic [1:0][1:0]  rd_sync,
  output logic [1:0][63:0] rd_data
);
  logic             phase;
  logic [1:0]       full;
  logic [1:0]       empty;
  logic [1:0]       push;
  logic [1:0]       pop;
  logic [65:0]      rd_word0;
  logic [65:0]      rd_word1;
  logic [65:0]      wr_word;
  wire              lane = stripe ? phase : 1'b0;

  assign wr_word  = {wr_sync, wr_data};
  assign wr_ready = ~full[lane];
  assign push[0]  = wr_valid && wr_ready && (lane == 1'b0);
  assign push[1]  = wr_valid && wr_ready && (lane == 1'b1);

  always_ff @(posedge clk_wr or negedge rst_wr_n) begin
    if (!rst_wr_n)
      phase <= 1'b0;
    else if (!stripe)
      phase <= 1'b0;
    else if (wr_valid && wr_ready)
      phase <= ~phase;
  end

  fc_async_fifo #(.WIDTH(66), .DEPTH(DEPTH)) u_lane0 (
    .wr_clk   (clk_wr),
    .wr_rst_n (rst_wr_n),
    .wr_push  (push[0]),
    .wr_data  (wr_word),
    .wr_full  (full[0]),
    .rd_clk   (clk_rd),
    .rd_rst_n (rst_rd_n),
    .rd_pop   (pop[0]),
    .rd_data  (rd_word0),
    .rd_empty (empty[0])
  );

  fc_async_fifo #(.WIDTH(66), .DEPTH(DEPTH)) u_lane1 (
    .wr_clk   (clk_wr),
    .wr_rst_n (rst_wr_n),
    .wr_push  (push[1]),
    .wr_data  (wr_word),
    .wr_full  (full[1]),
    .rd_clk   (clk_rd),
    .rd_rst_n (rst_rd_n),
    .rd_pop   (pop[1]),
    .rd_data  (rd_word1),
    .rd_empty (empty[1])
  );

  assign rd_valid[0] = ~empty[0];
  assign rd_valid[1] = ~empty[1];
  assign pop[0]      = rd_valid[0] && rd_ready[0];
  assign pop[1]      = rd_valid[1] && rd_ready[1];
  assign rd_sync[0]  = rd_word0[65:64];
  assign rd_sync[1]  = rd_word1[65:64];
  assign rd_data[0]  = rd_word0[63:0];
  assign rd_data[1]  = rd_word1[63:0];
endmodule

module fc_pair_merge #(
  parameter int DEPTH = 32
) (
  input  logic             clk_wr,
  input  logic             rst_wr_n,
  input  logic             clk_rd,
  input  logic             rst_rd_n,
  input  logic             stripe,
  input  logic [1:0]       wr_valid,
  output logic [1:0]       wr_ready,
  input  logic [1:0][1:0]  wr_sync,
  input  logic [1:0][63:0] wr_data,
  output logic             rd_valid,
  input  logic             rd_ready,
  output logic [1:0]       rd_sync,
  output logic [63:0]      rd_data
);
  logic        phase;
  logic [1:0]  full;
  logic [1:0]  empty;
  logic [1:0]  push;
  logic [1:0]  pop;
  logic [65:0] rd_word0;
  logic [65:0] rd_word1;
  wire         lane = stripe ? phase : 1'b0;

  assign wr_ready[0] = ~full[0];
  assign wr_ready[1] = ~full[1];
  assign push[0]     = wr_valid[0] && wr_ready[0];
  assign push[1]     = wr_valid[1] && wr_ready[1];

  fc_async_fifo #(.WIDTH(66), .DEPTH(DEPTH)) u_lane0 (
    .wr_clk   (clk_wr),
    .wr_rst_n (rst_wr_n),
    .wr_push  (push[0]),
    .wr_data  ({wr_sync[0], wr_data[0]}),
    .wr_full  (full[0]),
    .rd_clk   (clk_rd),
    .rd_rst_n (rst_rd_n),
    .rd_pop   (pop[0]),
    .rd_data  (rd_word0),
    .rd_empty (empty[0])
  );

  fc_async_fifo #(.WIDTH(66), .DEPTH(DEPTH)) u_lane1 (
    .wr_clk   (clk_wr),
    .wr_rst_n (rst_wr_n),
    .wr_push  (push[1]),
    .wr_data  ({wr_sync[1], wr_data[1]}),
    .wr_full  (full[1]),
    .rd_clk   (clk_rd),
    .rd_rst_n (rst_rd_n),
    .rd_pop   (pop[1]),
    .rd_data  (rd_word1),
    .rd_empty (empty[1])
  );

  assign rd_valid = ~empty[lane];
  assign rd_sync  = lane ? rd_word1[65:64] : rd_word0[65:64];
  assign rd_data  = lane ? rd_word1[63:0]  : rd_word0[63:0];
  assign pop[0]   = rd_valid && rd_ready && (lane == 1'b0);
  assign pop[1]   = rd_valid && rd_ready && (lane == 1'b1);

  always_ff @(posedge clk_rd or negedge rst_rd_n) begin
    if (!rst_rd_n)
      phase <= 1'b0;
    else if (!stripe)
      phase <= 1'b0;
    else if (rd_valid && rd_ready)
      phase <= ~phase;
  end
endmodule
