`timescale 1ns/1ps
// RS(544,514) on packed 257-bit groups: bypass, a clean pair of codewords,
// one corrected symbol, and an uncorrectable word that is forwarded.
module tb_fc_rs544_stream;
  `include "fc128_defs.vh"
  `include "fc_xcode.vh"

  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;

  logic        en;
  logic        in_valid, in_ready, out_valid, out_ready;
  logic [1:0]  in_sync, out_sync;
  logic [63:0] in_data, out_data;
  logic        corr_pulse, fail_pulse;
  logic [4:0]  corr_nerr;

  fc_rs544_tx u_tx (
    .clk(clk), .rst_n(rst_n), .en(en),
    .in_valid(in_valid), .in_ready(in_ready),
    .in_sync(in_sync), .in_data(in_data),
    .out_valid(out_valid), .out_ready(out_ready),
    .out_sync(out_sync), .out_data(out_data)
  );

  logic        rx_valid, rx_ready, rx_out_valid;
  logic [1:0]  rx_sync, rx_out_sync;
  logic [63:0] rx_data, rx_out_data;

  fc_rs544_rx u_rx (
    .clk(clk), .rst_n(rst_n), .en(en),
    .in_valid(rx_valid), .in_ready(rx_ready),
    .in_sync(rx_sync), .in_data(rx_data),
    .out_valid(rx_out_valid), .out_ready(out_ready),
    .out_sync(rx_out_sync), .out_data(rx_out_data),
    .corr_pulse(corr_pulse), .corr_nerr(corr_nerr), .fail_pulse(fail_pulse)
  );

  reg [65:0] src [0:159];
  reg [65:0] wire_b [0:169];
  reg [65:0] gold_w [0:169];
  reg [65:0] got [0:159];
  integer nsrc;
  integer errors;
  integer corr_seen;
  integer fail_seen;
  integer corr_sum;

  task automatic add_word(
    input [1:0] s0, input [63:0] d0,
    input [1:0] s1, input [63:0] d1,
    input [1:0] s2, input [63:0] d2,
    input [1:0] s3, input [63:0] d3
  );
    reg [256:0] x;
    reg [263:0] p;
    begin
      x = fc_xcode_enc(s0, d0, s1, d1, s2, d2, s3, d3);
      p = fc_xcode_pack(x);
      src[nsrc]   = p[65:0];
      src[nsrc+1] = p[131:66];
      src[nsrc+2] = p[197:132];
      src[nsrc+3] = p[263:198];
      nsrc = nsrc + 4;
    end
  endtask

  task automatic build_src;
    integer w;
    reg [63:0] d0, d1, d2, d3;
    begin
      nsrc = 0;
      for (w = 0; w < 40; w = w + 1) begin
        d0 = {32'hA000_0000, w[15:0], 16'h0001};
        d1 = {32'hB000_0000, w[15:0], 16'h0002};
        d2 = {32'hC000_0000, w[15:0], 16'h0003};
        d3 = {1'b1, 15'h1000, w[15:0], 32'h0000_0004};
        if ((w % 20) == 3)
          add_word(FC_SYNC_CTRL, {32'h0, FC_IDLE}, FC_SYNC_DATA, d1,
                   FC_SYNC_DATA, d2, FC_SYNC_DATA, d3);
        else if ((w % 20) == 11)
          add_word(FC_SYNC_DATA, d0, FC_SYNC_CTRL, {32'h0, FC_RRDY},
                   FC_SYNC_DATA, d2, FC_SYNC_CTRL, {32'h0, FC_OLS});
        else
          add_word(FC_SYNC_DATA, d0, FC_SYNC_DATA, d1,
                   FC_SYNC_DATA, d2, FC_SYNC_DATA, d3);
      end
    end
  endtask

  task automatic run_tx;
    input integer nin;
    input integer nout;
    integer ti, to, guard;
    reg took;
    begin
      ti = 0;
      to = 0;
      guard = 0;
      in_valid = 0;
      while ((ti < nin || to < nout) && guard < 30000) begin
        @(negedge clk);
        if (ti < nin && in_ready) begin
          in_valid = 1'b1;
          in_sync  = src[ti][65:64];
          in_data  = src[ti][63:0];
        end else begin
          in_valid = 1'b0;
        end
        #1;
        took = in_valid && in_ready;
        if (out_valid && out_ready && to < nout) begin
          wire_b[to] = {out_sync, out_data};
          to = to + 1;
        end
        @(posedge clk);
        if (took)
          ti = ti + 1;
        guard = guard + 1;
      end
      if (ti != nin || to != nout) begin
        $display("FAIL tx count in %0d/%0d out %0d/%0d", ti, nin, to, nout);
        errors = errors + 1;
      end
    end
  endtask

  task automatic run_rx;
    input integer nin;
    input integer nout;
    integer ti, to, guard;
    reg took;
    begin
      ti = 0;
      to = 0;
      guard = 0;
      corr_seen = 0;
      fail_seen = 0;
      corr_sum = 0;
      rx_valid = 0;
      while ((ti < nin || to < nout) && guard < 80000) begin
        @(negedge clk);
        if (ti < nin && rx_ready) begin
          rx_valid = 1'b1;
          rx_sync  = wire_b[ti][65:64];
          rx_data  = wire_b[ti][63:0];
        end else begin
          rx_valid = 1'b0;
        end
        #1;
        took = rx_valid && rx_ready;
        if (rx_out_valid && out_ready && to < nout) begin
          got[to] = {rx_out_sync, rx_out_data};
          to = to + 1;
        end
        if (corr_pulse) begin
          corr_seen = corr_seen + 1;
          corr_sum = corr_sum + corr_nerr;
        end
        if (fail_pulse)
          fail_seen = fail_seen + 1;
        @(posedge clk);
        if (took)
          ti = ti + 1;
        guard = guard + 1;
      end
      if (ti != nin || to != nout) begin
        $display("FAIL rx count in %0d/%0d out %0d/%0d", ti, nin, to, nout);
        errors = errors + 1;
      end
    end
  endtask

  task automatic expect_eq;
    input integer n;
    input integer src_off;
    integer i;
    begin
      for (i = 0; i < n; i = i + 1) begin
        if (got[i] !== src[src_off + i]) begin
          $display("FAIL beat %0d got %h exp %h", i, got[i], src[src_off + i]);
          errors = errors + 1;
        end
      end
    end
  endtask

  integer i;
  integer guard;

  initial begin
    errors = 0;
    en = 0;
    in_valid = 0;
    rx_valid = 0;
    out_ready = 1;
    in_sync = 0;
    in_data = 0;
    rx_sync = 0;
    rx_data = 0;
    build_src;
    if (nsrc != 160) begin
      $display("FAIL src %0d", nsrc);
      errors = errors + 1;
    end

    repeat (4) @(posedge clk);
    rst_n = 1;
    @(negedge clk);

    // Bypass keeps the beat and does not invent a trailer.
    run_tx(8, 8);
    for (i = 0; i < 8; i = i + 1) begin
      if (wire_b[i] !== src[i]) begin
        $display("FAIL bypass %0d", i);
        errors = errors + 1;
      end
    end

    en = 1;
    rst_n = 0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
    run_tx(160, 170);
    for (i = 0; i < 80; i = i + 1) begin
      if (wire_b[i] !== src[i]) begin
        $display("FAIL tx data %0d", i);
        errors = errors + 1;
      end
    end
    for (i = 80; i < 85; i = i + 1) begin
      if (wire_b[i][65:64] !== 2'b11) begin
        $display("FAIL trailer sync %0d %h", i, wire_b[i][65:64]);
        errors = errors + 1;
      end
    end
    for (i = 0; i < 80; i = i + 1) begin
      if (wire_b[85 + i] !== src[80 + i]) begin
        $display("FAIL tx data2 %0d", i);
        errors = errors + 1;
      end
    end
    for (i = 0; i < 170; i = i + 1)
      gold_w[i] = wire_b[i];

    run_rx(170, 160);
    expect_eq(160, 0);
    if (corr_seen != 0 || fail_seen != 0) begin
      $display("FAIL clean status corr %0d fail %0d", corr_seen, fail_seen);
      errors = errors + 1;
    end

    // One payload bit. Word 0 bit 0 is symbol 0.
    for (i = 0; i < 170; i = i + 1)
      wire_b[i] = gold_w[i];
    wire_b[0][0] = ~wire_b[0][0];
    rst_n = 0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
    run_rx(170, 160);
    expect_eq(160, 0);
    if (corr_seen != 1 || corr_sum != 1 || fail_seen != 0) begin
      $display("FAIL correct corr %0d sum %0d fail %0d", corr_seen, corr_sum, fail_seen);
      errors = errors + 1;
    end

    // Sixteen symbols: bit 0 of sixteen group starts, each a different symbol.
    for (i = 0; i < 170; i = i + 1)
      wire_b[i] = gold_w[i];
    for (i = 0; i < 16; i = i + 1)
      wire_b[i * 4][0] = ~wire_b[i * 4][0];
    rst_n = 0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
    run_rx(170, 160);
    if (fail_seen != 1 || corr_seen != 0) begin
      $display("FAIL uncorrectable fail %0d corr %0d", fail_seen, corr_seen);
      errors = errors + 1;
    end
    if (got[0][0] === src[0][0]) begin
      $display("FAIL uncorrectable word was repaired");
      errors = errors + 1;
    end

    if (errors == 0)
      $display("PASS tb_fc_rs544_stream");
    else
      $display("FAIL tb_fc_rs544_stream errors=%0d", errors);
    $finish;
  end
endmodule
