`timescale 1ns/1ps
// One port, system loopback, scrambler, 256b/257b transcode, and RS(544,514).
// Link init has to cross the codeword delay. A single flipped system bit is
// multiplied by the self-synchronizing scrambler and must still be corrected
// before a short frame returns.
module tb_fc_rs544_port;
  `include "fc128_defs.vh"
  `include "fc_crc.vh"

  logic clk_client = 0;
  logic clk_system = 0;
  logic rst_client_n = 0;
  logic rst_system_n = 0;
  always #4 clk_client = ~clk_client;
  initial begin
    #1;
    forever #7 clk_system = ~clk_system;
  end

  logic        client_rx_valid, client_rx_ready, client_tx_valid, client_tx_ready;
  logic [1:0]  client_rx_sync, client_tx_sync;
  logic [63:0] client_rx_data, client_tx_data;
  logic [1:0]  sys_tx_valid, sys_tx_ready, sys_rx_valid, sys_rx_ready;
  logic [1:0][1:0]  sys_tx_sync, sys_rx_sync;
  logic [1:0][63:0] sys_tx_data, sys_rx_data;
  logic        client_lock, client_link_up, system_link_up, sys_locked;
  logic [2:0]  client_ls, system_ls;
  logic [15:0] stat_rs544_corr, stat_rs544_fail;
  logic [7:0]  credit_cli, credit_sys;
  logic [31:0] stat_rx_frames, stat_tx_frames, stat_crc_err, stat_fec_corr, stat_fec_fail;

  fc_port dut (
    .clk_client(clk_client), .rst_client_n(rst_client_n),
    .clk_system(clk_system), .rst_system_n(rst_system_n),
    .port_en(1'b1), .fec_en(1'b0),
    .scrambler_en(1'b0), .scrambler_en_s(1'b1),
    .xcode_en(1'b1), .rs544_en(1'b1), .rate(FC_RATE_128),
    .credit_load(1'b0), .credit_cli_i(8'd8), .credit_sys_i(8'd8),
    .client_rx_valid(client_rx_valid), .client_rx_ready(client_rx_ready),
    .client_rx_sync(client_rx_sync), .client_rx_data(client_rx_data),
    .client_tx_valid(client_tx_valid), .client_tx_ready(client_tx_ready),
    .client_tx_sync(client_tx_sync), .client_tx_data(client_tx_data),
    .sys_tx_valid(sys_tx_valid), .sys_tx_ready(sys_tx_ready),
    .sys_tx_sync(sys_tx_sync), .sys_tx_data(sys_tx_data),
    .sys_rx_valid(sys_rx_valid), .sys_rx_ready(sys_rx_ready),
    .sys_rx_sync(sys_rx_sync), .sys_rx_data(sys_rx_data),
    .client_lock(client_lock),
    .credit_cli(credit_cli), .credit_sys(credit_sys),
    .stat_rx_frames(stat_rx_frames), .stat_tx_frames(stat_tx_frames),
    .stat_crc_err(stat_crc_err), .stat_fec_corr(stat_fec_corr),
    .stat_fec_fail(stat_fec_fail),
    .stat_rs544_corr(stat_rs544_corr), .stat_rs544_fail(stat_rs544_fail),
    .client_link_up(client_link_up), .system_link_up(system_link_up),
    .client_ls(client_ls), .system_ls(system_ls), .sys_locked(sys_locked),
    .rate_busy()
  );

  assign client_tx_ready = 1'b1;
  assign sys_rx_valid = sys_tx_valid;
  assign sys_rx_sync  = sys_tx_sync;
  assign sys_tx_ready = sys_rx_ready;

  logic flip = 0;
  logic flipped = 0;
  assign sys_rx_data[0] = sys_tx_data[0] ^ {63'h0, flip & ~flipped};
  assign sys_rx_data[1] = sys_tx_data[1];

  always @(posedge clk_system or negedge rst_system_n) begin
    if (!rst_system_n)
      flipped <= 1'b0;
    else if (flip && !flipped && sys_tx_valid[0] && sys_tx_ready[0])
      flipped <= 1'b1;
  end

  logic        drive_en = 0;
  logic        plain_valid;
  logic [1:0]  plain_sync;
  logic [63:0] plain_data;
  reg [65:0]   q [0:31];
  integer      q_wr = 0;
  integer      q_rd = 0;

  assign client_rx_valid = plain_valid;
  assign client_rx_sync  = plain_sync;
  assign client_rx_data  = plain_data;

  always @(posedge clk_client or negedge rst_client_n) begin
    if (!rst_client_n || !drive_en) begin
      plain_valid <= 1'b0;
      plain_sync  <= '0;
      plain_data  <= '0;
      q_rd        <= q_wr;
    end else if (!plain_valid || client_rx_ready) begin
      plain_valid <= 1'b1;
      if (q_rd != q_wr) begin
        plain_sync <= q[q_rd][65:64];
        plain_data <= q[q_rd][63:0];
        q_rd <= (q_rd + 1) % 32;
      end else begin
        plain_sync <= FC_SYNC_CTRL;
        plain_data <= {32'h0, FC_IDLE};
      end
    end
  end

  integer errors = 0;
  integer cap_count = 0;
  integer pst = 0;
  integer pidx = 0;
  integer pneed = 0;
  reg [7:0] cap [0:15];
  reg [7:0] pay [0:7];

  always @(posedge clk_client or negedge rst_client_n) begin
    integer b, n;
    if (!rst_client_n) begin
      cap_count <= 0;
      pst <= 0;
    end else if (client_tx_valid && client_tx_ready) begin
      if (client_tx_sync == FC_SYNC_CTRL && fc_is_sof(client_tx_data[31:0]) && pst == 0) begin
        pneed <= client_tx_data[39:32];
        pidx  <= 0;
        pst   <= 1;
      end else if (pst == 1 && client_tx_sync == FC_SYNC_DATA) begin
        for (b = 0; b < 8; b = b + 1)
          if (pidx + b < pneed)
            cap[pidx + b] <= client_tx_data[b*8 +: 8];
        n = pidx + 8;
        if (n > pneed)
          n = pneed;
        pidx <= n;
      end else if (pst == 1 && client_tx_sync == FC_SYNC_CTRL &&
                   fc_is_eof_good(client_tx_data[31:0])) begin
        if (pidx == pneed)
          cap_count <= cap_count + 1;
        pst <= 0;
      end
    end
  end

  task automatic push_blk(input [1:0] sync, input [63:0] data);
    integer spins;
    begin
      spins = 0;
      while (((q_wr + 1) % 32) == q_rd) begin
        @(posedge clk_client);
        spins = spins + 1;
        if (spins > 200000) begin
          $display("FAIL queue stalled");
          $finish;
        end
      end
      @(posedge clk_client);
      #1;
      q[q_wr] = {sync, data};
      q_wr = (q_wr + 1) % 32;
    end
  endtask

  integer t;
  integer i;
  reg [31:0] c;
  reg [63:0] blk;

  initial begin
    errors = 0;
    pay[0] = 8'h11;
    pay[1] = 8'h22;
    pay[2] = 8'h33;
    pay[3] = 8'h44;
    repeat (8) @(posedge clk_client);
    rst_client_n = 1;
    rst_system_n = 1;
    repeat (8) @(posedge clk_client);
    drive_en = 1;

    t = 0;
    while (t < 150000 && !(client_link_up && system_link_up)) begin
      @(posedge clk_client);
      t = t + 1;
    end
    if (!client_link_up || !system_link_up) begin
      $display("FAIL link cli %0d sys %0d lock %0b ls %0d/%0d t=%0d",
               client_link_up, system_link_up, sys_locked, client_ls, system_ls, t);
      errors = errors + 1;
    end else begin
      flip = 1;
      t = 0;
      while (t < 80000 && stat_rs544_corr == 16'h0) begin
        @(posedge clk_client);
        t = t + 1;
      end
      if (stat_rs544_corr == 16'h0 || stat_rs544_fail != 16'h0) begin
        $display("FAIL rs544 status corr %0d fail %0d", stat_rs544_corr, stat_rs544_fail);
        errors = errors + 1;
      end

      c = 32'hFFFF_FFFF;
      for (i = 0; i < 4; i = i + 1)
        c = crc32_update(c, pay[i]);
      c = ~c;
      push_blk(FC_SYNC_CTRL, {16'h0, 8'h00, 8'd4, FC_SOF});
      blk = 64'h0;
      for (i = 0; i < 4; i = i + 1)
        blk[i*8 +: 8] = pay[i];
      push_blk(FC_SYNC_DATA, blk);
      push_blk(FC_SYNC_CTRL, {c, FC_EOF});

      t = 0;
      while (cap_count == 0 && t < 150000) begin
        @(posedge clk_client);
        t = t + 1;
      end
      if (cap_count != 1) begin
        $display("FAIL frame did not return (%0d)", cap_count);
        errors = errors + 1;
      end else begin
        for (i = 0; i < 4; i = i + 1)
          if (cap[i] !== pay[i]) begin
            $display("FAIL payload[%0d]=%h", i, cap[i]);
            errors = errors + 1;
          end
      end
    end

    if (errors == 0)
      $display("PASS tb_fc_rs544_port");
    else
      $display("FAIL tb_fc_rs544_port errors=%0d", errors);
    $finish;
  end
endmodule
