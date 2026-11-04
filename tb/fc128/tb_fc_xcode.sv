`timescale 1ns/1ps
// Clause 119 256b/257b map, K28.5 restoration, and the streaming gearbox.
module tb_fc_xcode;
  `include "fc128_defs.vh"
  `include "fc_xcode.vh"

  integer errors;
  integer stream_errors;
  integer i;
  integer mask;
  integer t;
  integer nseen;
  integer show_n;
  reg [256:0] x;
  reg [256:0] y;
  reg [263:0] blk;
  reg [263:0] xpack;
  reg [1:0] s0, s1, s2, s3;
  reg [63:0] d0, d1, d2, d3;
  reg [65:0] sent [0:63];

  logic clk = 0;
  logic rst_n = 0;
  logic en = 0;
  logic stream_run = 0;
  logic in_valid = 0;
  logic in_ready;
  logic [1:0] in_sync = 0;
  logic [63:0] in_data = 0;
  logic mid_valid;
  logic mid_ready;
  logic [1:0] mid_sync;
  logic [63:0] mid_data;
  logic out_valid;
  logic out_ready;
  logic [1:0] out_sync;
  logic [63:0] out_data;
  logic ready_tog;

  always #5 clk = ~clk;

  fc_xcode_tx u_tx (
    .clk(clk), .rst_n(rst_n), .en(en),
    .in_valid(in_valid), .in_ready(in_ready),
    .in_sync(in_sync), .in_data(in_data),
    .out_valid(mid_valid), .out_ready(mid_ready),
    .out_sync(mid_sync), .out_data(mid_data)
  );

  fc_xcode_rx u_rx (
    .clk(clk), .rst_n(rst_n), .en(en),
    .in_valid(mid_valid), .in_ready(mid_ready),
    .in_sync(mid_sync), .in_data(mid_data),
    .out_valid(out_valid), .out_ready(out_ready),
    .out_sync(out_sync), .out_data(out_data)
  );

  assign out_ready = ready_tog;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
      ready_tog <= 1'b1;
    else
      ready_tog <= ~ready_tog;
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n || !stream_run) begin
      show_n   <= 0;
      in_valid <= 1'b0;
    end else if (in_valid && in_ready && show_n < 64) begin
      show_n <= show_n + 1;
      if (show_n + 1 < 64) begin
        in_valid <= 1'b1;
        in_sync  <= sent[show_n + 1][65:64];
        in_data  <= sent[show_n + 1][63:0];
      end else begin
        in_valid <= 1'b0;
      end
    end else if (show_n < 64) begin
      in_valid <= 1'b1;
      in_sync  <= sent[show_n][65:64];
      in_data  <= sent[show_n][63:0];
    end else begin
      in_valid <= 1'b0;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n || !stream_run) begin
      nseen <= 0;
    end else if (out_valid && out_ready) begin
      if (nseen < 64 &&
          (out_sync !== sent[nseen][65:64] || out_data !== sent[nseen][63:0])) begin
        $display("FAIL stream[%0d] %b %h", nseen, out_sync, out_data);
        stream_errors <= stream_errors + 1;
      end
      nseen <= nseen + 1;
    end
  end

  function automatic [65:0] blk_of(input [263:0] w, input integer n);
    begin
      case (n)
        0: blk_of = w[65:0];
        1: blk_of = w[131:66];
        2: blk_of = w[197:132];
        default: blk_of = w[263:198];
      endcase
    end
  endfunction

  initial begin
    errors = 0;
    stream_errors = 0;

    d0 = 64'h0001_0203_0405_0607;
    d1 = 64'h1111_2222_3333_4444;
    d2 = 64'h5555_6666_7777_8888;
    d3 = 64'h9999_AAAA_BBBB_CCCC;
    x = fc_xcode_enc(FC_SYNC_DATA, d0, FC_SYNC_DATA, d1,
                     FC_SYNC_DATA, d2, FC_SYNC_DATA, d3);
    y = {d3, d2, d1, d0, 1'b1};
    if (x !== y) begin
      $display("FAIL all-data word");
      errors = errors + 1;
    end
    blk = fc_xcode_dec(x);
    if (blk !== {FC_SYNC_DATA, d3, FC_SYNC_DATA, d2,
                 FC_SYNC_DATA, d1, FC_SYNC_DATA, d0}) begin
      $display("FAIL all-data decode");
      errors = errors + 1;
    end

    d0 = 64'h0123_4567_89AB_CDBC;
    d1 = 64'h1111_1111_1111_1111;
    d2 = 64'h2222_2222_2222_2222;
    d3 = 64'h3333_3333_3333_3333;
    x = fc_xcode_enc(FC_SYNC_CTRL, d0, FC_SYNC_DATA, d1,
                     FC_SYNC_DATA, d2, FC_SYNC_DATA, d3);
    y = {d3, d2, d1, d0[63:8], 4'hC, 4'b1110, 1'b0};
    if (x !== y) begin
      $display("FAIL control word %h", x);
      errors = errors + 1;
    end
    blk = fc_xcode_dec(x);
    if (blk !== {FC_SYNC_DATA, d3, FC_SYNC_DATA, d2,
                 FC_SYNC_DATA, d1, FC_SYNC_CTRL, d0}) begin
      $display("FAIL K28.5 restore %h", blk);
      errors = errors + 1;
    end

    d0 = {56'h0123456789ABCD, 8'h1E};
    x = fc_xcode_enc(FC_SYNC_CTRL, d0, FC_SYNC_DATA, d1,
                     FC_SYNC_DATA, d2, FC_SYNC_DATA, d3);
    blk = fc_xcode_dec(x);
    if (blk[65:0] !== {FC_SYNC_CTRL, d0}) begin
      $display("FAIL 0x1E restore %h", blk[65:0]);
      errors = errors + 1;
    end

    x = fc_xcode_enc(FC_SYNC_CTRL, 64'h0, FC_SYNC_DATA, d1,
                     FC_SYNC_DATA, d2, FC_SYNC_DATA, d3);
    blk = fc_xcode_dec(x);
    if (blk[65:64] !== 2'b11 || blk[63:0] !== 64'h0) begin
      $display("FAIL unknown nibble %h", blk[65:0]);
      errors = errors + 1;
    end

    d0 = 64'h0123456789ABCDEF;
    x = fc_xcode_enc(2'b00, d0, FC_SYNC_DATA, d1, FC_SYNC_DATA, d2, 2'b11, d3);
    blk = fc_xcode_dec(x);
    if (blk !== {2'b11, d3, 2'b00, d2, 2'b11, d1, 2'b00, {d0[63:8], 8'h0F}}) begin
      $display("FAIL invalid sync %h", blk);
      errors = errors + 1;
    end

    for (mask = 0; mask < 16; mask = mask + 1) begin
      s0 = mask[0] ? FC_SYNC_CTRL : FC_SYNC_DATA;
      s1 = mask[1] ? FC_SYNC_CTRL : FC_SYNC_DATA;
      s2 = mask[2] ? FC_SYNC_CTRL : FC_SYNC_DATA;
      s3 = mask[3] ? FC_SYNC_CTRL : FC_SYNC_DATA;
      d0 = mask[0] ? {8'(mask), 8'h10, 16'hBEEF, FC_IDLE} : {32'hA000_0000 + mask, 32'h1111_0001};
      d1 = mask[1] ? {8'(mask), 8'h11, 16'hBEEF, FC_RRDY} : {32'hA000_0000 + mask, 32'h2222_0002};
      d2 = mask[2] ? {8'(mask), 8'h12, 16'hBEEF, FC_OLS}  : {32'hA000_0000 + mask, 32'h3333_0003};
      d3 = mask[3] ? {8'(mask), 8'h13, 16'hBEEF, FC_LR}   : {32'hA000_0000 + mask, 32'h4444_0004};
      x = fc_xcode_enc(s0, d0, s1, d1, s2, d2, s3, d3);
      blk = fc_xcode_dec(x);
      if (blk !== {s3, d3, s2, d2, s1, d1, s0, d0}) begin
        $display("FAIL mask %0h %h", mask, blk);
        errors = errors + 1;
      end
      xpack = fc_xcode_pack(x);
      y = fc_xcode_unpack(xpack[65:64], xpack[63:0], xpack[129:66],
                          xpack[195:132], xpack[261:198]);
      if (y !== x || !fc_xcode_frame(xpack[65:64], xpack[131:130],
                                     xpack[197:196], xpack[263:262])) begin
        $display("FAIL pack %0h", mask);
        errors = errors + 1;
      end
    end

    x = {1'b1, 256'h0};
    xpack = fc_xcode_pack(x);
    if (xpack[65:64] !== 2'b01 || fc_xcode_unpack(xpack[65:64], xpack[63:0],
        xpack[129:66], xpack[195:132], xpack[261:198]) !== x) begin
      $display("FAIL pack msb");
      errors = errors + 1;
    end

    for (i = 0; i < 64; i = i + 1) begin
      if ((i % 5) == 0)
        sent[i] = {FC_SYNC_CTRL, 32'h0100_0000 + i, FC_IDLE};
      else if ((i % 5) == 1)
        sent[i] = {FC_SYNC_CTRL, 32'h0, FC_RRDY};
      else
        sent[i] = {FC_SYNC_DATA, 64'h1000_0000_0000_0000 + i};
    end
    sent[12] = {FC_SYNC_CTRL, 64'hAABB_CCDD_1122_331E};
    sent[20] = {FC_SYNC_CTRL, 16'h0, 8'h00, 8'd8, FC_SOFI3};
    sent[21] = {FC_SYNC_CTRL, 32'hA5A55A5A, FC_EOFT};

    en = 0;
    rst_n = 0;
    stream_run = 0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
    #1;
    if (in_ready !== out_ready) begin
      $display("FAIL bypass ready");
      errors = errors + 1;
    end
    stream_run = 1;
    for (t = 0; t < 4000 && nseen < 64; t = t + 1)
      @(negedge clk);
    if (nseen != 64) begin
      $display("FAIL bypass count %0d", nseen);
      errors = errors + 1;
    end
    errors = errors + stream_errors;

    stream_errors = 0;
    stream_run = 0;
    en = 1;
    rst_n = 0;
    repeat (2) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
    stream_run = 1;
    for (t = 0; t < 4000 && nseen < 64; t = t + 1)
      @(negedge clk);
    if (nseen != 64) begin
      $display("FAIL stream count %0d", nseen);
      errors = errors + 1;
    end
    errors = errors + stream_errors;

    if (errors == 0)
      $display("PASS tb_fc_xcode");
    else
      $display("FAIL tb_fc_xcode errors=%0d", errors);
    $finish;
  end
endmodule
