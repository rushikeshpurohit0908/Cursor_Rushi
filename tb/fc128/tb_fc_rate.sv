`timescale 1ns/1ps
// Tri-rate gearbox. The shaper inserts and deletes the 32GFC IDLE by
// position. The port loops the system lanes back: 64GFC and 32GFC stay on
// lane 0, a short frame returns, and 32GFC puts an IDLE between SOF and the
// payload on that lane. 128GFC still stripes both lanes. A 32GFC frame also
// returns with the 256b/257b transcode enabled. Changing the rate while the
// link is Active drops both links, reports rate_busy, then a frame returns
// at the new lane map.
module tb_fc_rate;
  `include "fc128_defs.vh"
  `include "fc_crc.vh"

  logic clk = 0;
  logic rst_n = 0;
  always #4 clk = ~clk;

  logic        half = 0;
  logic        tv, tr, txv;
  wire         txr;
  logic [1:0]  ts, txs;
  logic [63:0] td, txd;
  logic        rv, rr, rxv;
  logic        rxr = 1;
  logic [1:0]  rs, rxs;
  logic [63:0] rd, rxd;

  fc_rate_tx u_tx (
    .clk(clk), .rst_n(rst_n), .half(half),
    .in_valid(tv), .in_ready(tr), .in_sync(ts), .in_data(td),
    .out_valid(txv), .out_ready(txr), .out_sync(txs), .out_data(txd)
  );
  fc_rate_rx u_rx (
    .clk(clk), .rst_n(rst_n), .half(half),
    .in_valid(rv), .in_ready(rr), .in_sync(rs), .in_data(rd),
    .out_valid(rxv), .out_ready(rxr), .out_sync(rxs), .out_data(rxd)
  );

  assign rv = txv;
  assign rs = txs;
  assign rd = txd;
  assign txr = rr;

  logic clk_client = 0;
  logic clk_system = 0;
  logic rst_client_n = 0;
  logic rst_system_n = 0;
  always #4 clk_client = ~clk_client;
  initial begin
    #1;
    forever #7 clk_system = ~clk_system;
  end

  logic [1:0]  rate = FC_RATE_128;
  logic        xcode_en = 0;
  logic        client_rx_valid, client_rx_ready, client_tx_valid, client_tx_ready;
  logic [1:0]  client_rx_sync, client_tx_sync;
  logic [63:0] client_rx_data, client_tx_data;
  logic [1:0]  sys_tx_valid, sys_tx_ready, sys_rx_valid, sys_rx_ready;
  logic [1:0][1:0]  sys_tx_sync, sys_rx_sync;
  logic [1:0][63:0] sys_tx_data, sys_rx_data;
  logic        client_lock, client_link_up, system_link_up, sys_locked, rate_busy;
  logic [2:0]  client_ls, system_ls;
  logic [15:0] stat_rs544_corr, stat_rs544_fail;
  logic [7:0]  credit_cli, credit_sys;
  logic [31:0] stat_rx_frames, stat_tx_frames, stat_crc_err, stat_fec_corr, stat_fec_fail;

  fc_port dut (
    .clk_client(clk_client), .rst_client_n(rst_client_n),
    .clk_system(clk_system), .rst_system_n(rst_system_n),
    .port_en(1'b1), .fec_en(1'b0),
    .scrambler_en(1'b0), .scrambler_en_s(1'b0),
    .xcode_en(xcode_en), .rs544_en(1'b0), .rate(rate),
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
    .rate_busy(rate_busy)
  );

  assign client_tx_ready = 1'b1;
  assign sys_rx_valid = sys_tx_valid;
  assign sys_rx_sync  = sys_tx_sync;
  assign sys_rx_data  = sys_tx_data;
  assign sys_tx_ready = sys_rx_ready;

  logic        drive_en = 0;
  logic        plain_valid;
  logic [1:0]  plain_sync;
  logic [63:0] plain_data;
  reg [65:0]   q [0:31];
  integer      q_wr = 0;
  integer      q_rd = 0;
  integer      lane0_n = 0;
  integer      lane1_n = 0;
  integer      saw = 0;
  reg [65:0]   seen [0:7];
  logic        arm = 0;
  logic        cap_clr = 0;

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

  integer cap_count = 0;
  integer pst = 0;
  integer pidx = 0;
  integer pneed = 0;
  reg [7:0] cap [0:15];

  always @(posedge clk_client or negedge rst_client_n) begin
    integer b, n;
    if (!rst_client_n || cap_clr) begin
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

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_n  <= 0;
      got_n <= 0;
    end else begin
      if (txv && txr && tx_n < 16) begin
        txcap[tx_n] <= {txs, txd};
        tx_n <= tx_n + 1;
      end
      if (rxv && rxr && got_n < 8) begin
        got[got_n] <= {rxs, rxd};
        got_n <= got_n + 1;
      end
    end
  end

  always @(posedge clk_system or negedge rst_system_n) begin
    if (!rst_system_n) begin
      lane0_n <= 0;
      lane1_n <= 0;
      saw <= 0;
    end else begin
      if (!arm)
        saw <= 0;
      if (sys_tx_valid[1] && sys_tx_ready[1])
        lane1_n <= lane1_n + 1;
      if (sys_tx_valid[0] && sys_tx_ready[0]) begin
        lane0_n <= lane0_n + 1;
        if (arm && saw < 8) begin
          if (saw != 0 || (sys_tx_sync[0] == FC_SYNC_CTRL &&
                           fc_is_sof(sys_tx_data[0][31:0]))) begin
            seen[saw] <= {sys_tx_sync[0], sys_tx_data[0]};
            saw <= saw + 1;
          end
        end
      end
    end
  end

  integer errors = 0;
  integer t;
  integer i;
  integer l0s;
  integer l1s;
  integer crc_s;
  integer tx_n = 0;
  integer got_n = 0;
  reg [65:0] txcap [0:15];
  reg [65:0] got [0:7];
  reg [31:0] c;
  reg [63:0] blk;
  reg [7:0] pay [0:3];

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

  task automatic send_frame;
    begin
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
    end
  endtask

  task automatic wait_link;
    begin
      t = 0;
      while (t < 150000 && !(client_link_up && system_link_up && sys_locked)) begin
        @(posedge clk_client);
        t = t + 1;
      end
      if (!client_link_up || !system_link_up || !sys_locked || rate_busy) begin
        $display("FAIL link rate %0d cli %0d sys %0d lock %0b busy %0d t=%0d",
                 rate, client_link_up, system_link_up, sys_locked, rate_busy, t);
        errors = errors + 1;
      end
    end
  endtask

  task automatic wait_frame;
    begin
      t = 0;
      while (cap_count == 0 && t < 150000) begin
        @(posedge clk_client);
        t = t + 1;
      end
      if (cap_count != 1) begin
        $display("FAIL frame did not return rate %0d xcode %0d (%0d)",
                 rate, xcode_en, cap_count);
        errors = errors + 1;
      end else begin
        for (i = 0; i < 4; i = i + 1)
          if (cap[i] !== pay[i]) begin
            $display("FAIL payload[%0d]=%h rate %0d", i, cap[i], rate);
            errors = errors + 1;
          end
      end
    end
  endtask

  task automatic clear_cap;
    begin
      cap_clr = 1;
      @(posedge clk_client);
      cap_clr = 0;
    end
  endtask

  task automatic expect_links_down;
    integer k;
    begin
      k = 0;
      while ((client_link_up || system_link_up) && k < 200) begin
        @(posedge clk_client);
        k = k + 1;
      end
      if (client_link_up || system_link_up || !rate_busy) begin
        $display("FAIL live rate %0d cli %0d sys %0d busy %0d",
                 rate, client_link_up, system_link_up, rate_busy);
        errors = errors + 1;
      end
    end
  endtask

  task automatic boot(input [1:0] next_rate, input x_on);
    begin
      drive_en = 0;
      arm = 0;
      rate = next_rate;
      xcode_en = x_on;
      rst_client_n = 0;
      rst_system_n = 0;
      repeat (8) @(posedge clk_client);
      rst_client_n = 1;
      rst_system_n = 1;
      repeat (8) @(posedge clk_client);
      drive_en = 1;
    end
  endtask

  initial begin
    errors = 0;
    pay[0] = 8'h11;
    pay[1] = 8'h22;
    pay[2] = 8'h33;
    pay[3] = 8'h44;
    half = 1;
    tv = 0;
    ts = FC_SYNC_DATA;
    td = 64'h0;
    repeat (4) @(posedge clk);
    rst_n = 1;
    @(posedge clk);
    for (i = 0; i < 3; i = i + 1) begin
      td = 64'hA0 + i;
      tv = 1;
      @(posedge clk);
      while (!tr) @(posedge clk);
    end
    tv = 0;
    t = 0;
    while ((tx_n < 6 || got_n < 3) && t < 40) begin
      @(posedge clk);
      t = t + 1;
    end
    if (tx_n != 6 || got_n != 3) begin
      $display("FAIL shaper tx %0d rx %0d", tx_n, got_n);
      errors = errors + 1;
    end else begin
      for (i = 0; i < 3; i = i + 1) begin
        if (txcap[2*i][63:0] !== (64'hA0 + i) || txcap[2*i][65:64] !== FC_SYNC_DATA ||
            txcap[2*i+1][31:0] !== FC_IDLE || txcap[2*i+1][65:64] !== FC_SYNC_CTRL) begin
          $display("FAIL shaper wire %0d %h %h", i, txcap[2*i], txcap[2*i+1]);
          errors = errors + 1;
        end
        if (got[i][63:0] !== (64'hA0 + i) || got[i][65:64] !== FC_SYNC_DATA) begin
          $display("FAIL shaper out %0d %h", i, got[i]);
          errors = errors + 1;
        end
      end
    end

    // 128GFC uses both system lanes before the link is up.
    boot(FC_RATE_128, 1'b0);
    repeat (40) @(posedge clk_system);
    if (lane0_n == 0 || lane1_n == 0) begin
      $display("FAIL 128 stripe lane0 %0d lane1 %0d", lane0_n, lane1_n);
      errors = errors + 1;
    end

    boot(FC_RATE_64, 1'b0);
    repeat (80) @(posedge clk_system);
    if (lane0_n == 0 || lane1_n != 0) begin
      $display("FAIL 64 lane0 %0d lane1 %0d", lane0_n, lane1_n);
      errors = errors + 1;
    end
    wait_link;
    if (system_link_up) begin
      arm = 1;
      send_frame;
      wait_frame;
      t = 0;
      while (saw < 3 && t < 4000) begin
        @(posedge clk_system);
        t = t + 1;
      end
      if (saw < 3 || seen[0][65:64] != FC_SYNC_CTRL || !fc_is_sof(seen[0][31:0]) ||
          seen[1][65:64] != FC_SYNC_DATA || seen[1][7:0] != pay[0] ||
          seen[2][65:64] != FC_SYNC_CTRL || !fc_is_eof_good(seen[2][31:0])) begin
        $display("FAIL 64 wire sof %h %h %h saw %0d", seen[0], seen[1], seen[2], saw);
        errors = errors + 1;
      end
      if (lane1_n != 0) begin
        $display("FAIL 64 lane1 became active %0d", lane1_n);
        errors = errors + 1;
      end
    end

    boot(FC_RATE_32, 1'b0);
    repeat (80) @(posedge clk_system);
    if (lane0_n == 0 || lane1_n != 0) begin
      $display("FAIL 32 lane0 %0d lane1 %0d", lane0_n, lane1_n);
      errors = errors + 1;
    end
    wait_link;
    if (system_link_up) begin
      arm = 1;
      send_frame;
      wait_frame;
      t = 0;
      while (saw < 5 && t < 8000) begin
        @(posedge clk_system);
        t = t + 1;
      end
      if (saw < 5 || seen[0][65:64] != FC_SYNC_CTRL || !fc_is_sof(seen[0][31:0]) ||
          seen[1][65:64] != FC_SYNC_CTRL || seen[1][31:0] != FC_IDLE ||
          seen[2][65:64] != FC_SYNC_DATA || seen[2][7:0] != pay[0] ||
          seen[3][65:64] != FC_SYNC_CTRL || seen[3][31:0] != FC_IDLE ||
          seen[4][65:64] != FC_SYNC_CTRL || !fc_is_eof_good(seen[4][31:0])) begin
        $display("FAIL 32 wire %h %h %h %h %h saw %0d",
                 seen[0], seen[1], seen[2], seen[3], seen[4], saw);
        errors = errors + 1;
      end
    end

    boot(FC_RATE_32, 1'b1);
    wait_link;
    if (system_link_up) begin
      send_frame;
      wait_frame;
      if (lane1_n != 0) begin
        $display("FAIL 32 xcode lane1 %0d", lane1_n);
        errors = errors + 1;
      end
    end

    // Same code again does not drop a live link. A different code does,
    // and the next frame uses the new lane map without a port reset.
    boot(FC_RATE_64, 1'b0);
    wait_link;
    rate = FC_RATE_64;
    repeat (40) @(posedge clk_client);
    if (!client_link_up || !system_link_up || rate_busy) begin
      $display("FAIL same rate dropped the link cli %0d sys %0d busy %0d",
               client_link_up, system_link_up, rate_busy);
      errors = errors + 1;
    end

    rate = FC_RATE_32;
    expect_links_down;
    wait_link;
    if (system_link_up && lane1_n != 0) begin
      $display("FAIL live 32 lane1 %0d", lane1_n);
      errors = errors + 1;
    end
    if (system_link_up) begin
      clear_cap;
      arm = 0;
      @(posedge clk_system);
      arm = 1;
      crc_s = stat_crc_err;
      send_frame;
      wait_frame;
      if (stat_crc_err != crc_s) begin
        $display("FAIL live 32 crc %0d -> %0d", crc_s, stat_crc_err);
        errors = errors + 1;
      end
      t = 0;
      while (saw < 5 && t < 8000) begin
        @(posedge clk_system);
        t = t + 1;
      end
      if (saw < 5 || seen[0][65:64] != FC_SYNC_CTRL || !fc_is_sof(seen[0][31:0]) ||
          seen[1][65:64] != FC_SYNC_CTRL || seen[1][31:0] != FC_IDLE ||
          seen[2][65:64] != FC_SYNC_DATA || seen[2][7:0] != pay[0] ||
          seen[3][65:64] != FC_SYNC_CTRL || seen[3][31:0] != FC_IDLE ||
          seen[4][65:64] != FC_SYNC_CTRL || !fc_is_eof_good(seen[4][31:0])) begin
        $display("FAIL live 32 wire %h %h %h %h %h saw %0d",
                 seen[0], seen[1], seen[2], seen[3], seen[4], saw);
        errors = errors + 1;
      end
      if (lane1_n != 0) begin
        $display("FAIL live 32 lane1 after frame %0d", lane1_n);
        errors = errors + 1;
      end
    end

    arm = 0;
    rate = FC_RATE_128;
    expect_links_down;
    wait_link;
    if (system_link_up && lane1_n == 0) begin
      $display("FAIL live 128 lane1 still idle");
      errors = errors + 1;
    end
    if (system_link_up) begin
      l0s = lane0_n;
      l1s = lane1_n;
      clear_cap;
      crc_s = stat_crc_err;
      send_frame;
      wait_frame;
      if (stat_crc_err != crc_s) begin
        $display("FAIL live 128 crc %0d -> %0d", crc_s, stat_crc_err);
        errors = errors + 1;
      end
      if (lane0_n <= l0s || lane1_n <= l1s) begin
        $display("FAIL live 128 lanes %0d %0d -> %0d %0d", l0s, l1s, lane0_n, lane1_n);
        errors = errors + 1;
      end
    end

    rate = 2'b11;
    repeat (40) @(posedge clk_client);
    if (!client_link_up || !system_link_up || rate_busy) begin
      $display("FAIL reserved rate dropped the link cli %0d sys %0d busy %0d",
               client_link_up, system_link_up, rate_busy);
      errors = errors + 1;
    end

    rate = FC_RATE_64;
    expect_links_down;
    wait_link;
    if (system_link_up) begin
      l1s = lane1_n;
      clear_cap;
      crc_s = stat_crc_err;
      send_frame;
      wait_frame;
      if (stat_crc_err != crc_s) begin
        $display("FAIL live 64 crc %0d -> %0d", crc_s, stat_crc_err);
        errors = errors + 1;
      end
      if (lane1_n != l1s) begin
        $display("FAIL live 64 lane1 %0d -> %0d", l1s, lane1_n);
        errors = errors + 1;
      end
    end

    boot(FC_RATE_64, 1'b1);
    wait_link;
    rate = FC_RATE_32;
    expect_links_down;
    wait_link;
    if (system_link_up) begin
      l1s = lane1_n;
      clear_cap;
      crc_s = stat_crc_err;
      send_frame;
      wait_frame;
      if (stat_crc_err != crc_s) begin
        $display("FAIL live 32 xcode crc %0d -> %0d", crc_s, stat_crc_err);
        errors = errors + 1;
      end
      if (lane1_n != l1s) begin
        $display("FAIL live 32 xcode lane1 %0d -> %0d", l1s, lane1_n);
        errors = errors + 1;
      end
    end

    if (errors == 0)
      $display("PASS tb_fc_rate");
    else
      $display("FAIL tb_fc_rate errors=%0d", errors);
    $finish;
  end
endmodule
