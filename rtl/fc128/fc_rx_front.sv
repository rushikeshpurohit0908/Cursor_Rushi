// Descramble one SerDes lane, force a short warmup to IDLE, and track block lock.
// Sync headers are not scrambled. Warmup still advances the descrambler so the
// LFSR is filled with real line bits before the frame parser sees payload.
module fc_rx_front #(
  parameter int LOCK_TH   = 8,
  parameter int UNLOCK_TH = 4,
  parameter int WARMUP    = 2
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        scrambler_en,
  // Packed 257-bit beats use sync 00 as a group marker. Count those
  // toward block lock; the recovered header is checked after decode.
  input  logic        sync_relax,
  input  logic        valid,
  input  logic        ready,
  input  logic [1:0]  sync_in,
  input  logic [63:0] data_in,
  output logic [1:0]  sync_out,
  output logic [63:0] data_out,
  output logic        locked
);
  `include "fc128_defs.vh"

  logic [63:0] descrambled;
  logic [7:0]  good_cnt;
  logic [7:0]  bad_cnt;
  logic [7:0]  warm_cnt;
  logic        step;
  logic        sync_ok;

  fc_scrambler u_descramble (
    .clk        (clk),
    .rst_n      (rst_n),
    .en         (scrambler_en),
    .descramble (1'b1),
    .step       (step),
    .din        (data_in),
    .dout       (descrambled)
  );

  assign step    = valid && ready;
  assign sync_ok = sync_relax ||
                   (sync_in == FC_SYNC_DATA) || (sync_in == FC_SYNC_CTRL);

  always_comb begin
      if (warm_cnt < WARMUP) begin
      sync_out = FC_SYNC_CTRL;
      data_out = {32'h0, FC_IDLE};
    end else begin
      sync_out = sync_in;
      data_out = descrambled;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      good_cnt <= '0;
      bad_cnt  <= '0;
      warm_cnt <= '0;
      locked   <= 1'b0;
    end else if (step) begin
      if (warm_cnt < WARMUP)
        warm_cnt <= warm_cnt + 8'd1;

      if (!locked) begin
        if (sync_ok) begin
          if (good_cnt + 8'd1 >= LOCK_TH) begin
            locked   <= 1'b1;
            good_cnt <= '0;
            bad_cnt  <= '0;
          end else begin
            good_cnt <= good_cnt + 8'd1;
          end
        end else begin
          good_cnt <= '0;
        end
      end else if (!sync_ok) begin
        if (bad_cnt + 8'd1 >= UNLOCK_TH) begin
          locked   <= 1'b0;
          bad_cnt  <= '0;
          good_cnt <= '0;
        end else begin
          bad_cnt <= bad_cnt + 8'd1;
        end
      end else begin
        bad_cnt <= '0;
      end
    end
  end
endmodule
