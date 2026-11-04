`timescale 1ns/1ps
// Self-checking bring-up of the 8-port FC128 bridge:
// 256b/257b system-lane transcode, scramble, block lock, link init, CRC
// frames, system loopback, credit stall, RS-FEC correction, the second
// client port, NOS drop, and the protect-lane copy.
module tb_fc128_bridge;
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

  logic [11:0] csr_addr = 0;
  logic        csr_write = 0;
  logic        csr_read = 0;
  logic [31:0] csr_wdata = 0;
  logic [31:0] csr_rdata;
  logic [7:0]  client_rx_valid, client_rx_ready, client_tx_valid, client_tx_ready;
  logic [7:0][1:0]  client_rx_sync, client_tx_sync;
  logic [7:0][63:0] client_rx_data, client_tx_data;
  logic [15:0] sys_tx_valid, sys_tx_ready, sys_rx_valid, sys_rx_ready;
  logic [15:0][1:0]  sys_tx_sync, sys_rx_sync;
  logic [15:0][63:0] sys_tx_data, sys_rx_data;
  logic [7:0] sec_tx_valid;
  logic [7:0][1:0]  sec_tx_sync;
  logic [7:0][63:0] sec_tx_data;

  fc128_bridge_top dut (
    .clk_client(clk_client), .clk_system(clk_system),
    .rst_client_n(rst_client_n), .rst_system_n(rst_system_n),
    .csr_addr(csr_addr), .csr_write(csr_write), .csr_read(csr_read),
    .csr_wdata(csr_wdata), .csr_rdata(csr_rdata),
    .client_rx_valid(client_rx_valid), .client_rx_ready(client_rx_ready),
    .client_rx_sync(client_rx_sync), .client_rx_data(client_rx_data),
    .client_tx_valid(client_tx_valid), .client_tx_ready(client_tx_ready),
    .client_tx_sync(client_tx_sync), .client_tx_data(client_tx_data),
    .sys_tx_valid(sys_tx_valid), .sys_tx_ready(sys_tx_ready),
    .sys_tx_sync(sys_tx_sync), .sys_tx_data(sys_tx_data),
    .sys_rx_valid(sys_rx_valid), .sys_rx_ready(sys_rx_ready),
    .sys_rx_sync(sys_rx_sync), .sys_rx_data(sys_rx_data),
    .sec_tx_valid(sec_tx_valid), .sec_tx_sync(sec_tx_sync), .sec_tx_data(sec_tx_data)
  );

  logic        drive_en = 0;
  logic        mon_fec = 0;
  logic        check_sec = 0;
  integer      sec_mismatch = 0;
  logic [7:0]       plain_valid;
  logic [7:0][1:0]  plain_sync;
  logic [7:0][63:0] plain_data;
  logic [7:0][63:0] scr_dout;
  logic [7:0][63:0] mon_dout;

  assign client_tx_ready = 8'hFF;
  assign sys_tx_ready    = 16'hFFFF;
  assign sys_rx_valid    = '0;
  assign sys_rx_sync     = '0;
  assign sys_rx_data     = '0;

  genvar gp;
  generate
    for (gp = 0; gp < 8; gp = gp + 1) begin : g_tb_scr
      fc_scrambler u_drv (
        .clk(clk_client), .rst_n(rst_client_n), .en(1'b1), .descramble(1'b0),
        .step(plain_valid[gp] && client_rx_ready[gp]),
        .din(plain_data[gp]), .dout(scr_dout[gp])
      );
      fc_scrambler u_mon (
        .clk(clk_client), .rst_n(rst_client_n), .en(1'b1), .descramble(1'b1),
        .step(client_tx_valid[gp] && client_tx_ready[gp]),
        .din(client_tx_data[gp]), .dout(mon_dout[gp])
      );
      assign client_rx_data[gp] = scr_dout[gp];
      assign client_rx_sync[gp] = plain_sync[gp];
      assign client_rx_valid[gp] = plain_valid[gp];
    end
  endgenerate

  reg [65:0] q [0:63];
  integer q_wr = 0;
  integer q_rd = 0;
  integer active_port = 0;
  integer pi;

  always @(posedge clk_client or negedge rst_client_n) begin
    if (!rst_client_n || !drive_en) begin
      plain_valid <= '0;
      plain_sync  <= '0;
      plain_data  <= '0;
      q_rd        <= q_wr;
    end else begin
      for (pi = 0; pi < 8; pi = pi + 1) begin
        if (!plain_valid[pi] || client_rx_ready[pi]) begin
          plain_valid[pi] <= 1'b1;
          if (pi == active_port && q_rd != q_wr) begin
            plain_sync[pi] <= q[q_rd][65:64];
            plain_data[pi] <= q[q_rd][63:0];
            q_rd <= (q_rd + 1) % 64;
          end else begin
            plain_sync[pi] <= FC_SYNC_CTRL;
            plain_data[pi] <= {32'h0, FC_IDLE};
          end
        end
      end
    end
  end

  integer      cap_count = 0;
  integer      x_beats0 = 0;
  integer      x_start0 = 0;
  integer      x_start1 = 0;
  logic        watch_x = 0;
  integer      cap_port = 0;
  integer      cap_k = 0;
  integer      cap_n = 0;
  reg [7:0]    cap [0:255];
  integer      pst [0:7];
  integer      pidx [0:7];
  integer      pk [0:7];
  integer      pneed [0:7];
  reg [7:0]    pbuf [0:7][0:255];
  integer      rrdy_count = 0;

  always @(posedge clk_client or negedge rst_client_n) begin
    integer p, b, n;
    reg [63:0] d;
    if (!rst_client_n) begin
      cap_count <= 0;
      for (p = 0; p < 8; p = p + 1) pst[p] <= 0;
    end else begin
      for (p = 0; p < 8; p = p + 1) begin
        if (client_tx_valid[p] && client_tx_ready[p]) begin
          d = mon_dout[p];
          if (client_tx_sync[p] == FC_SYNC_CTRL && fc_is_sof(d[31:0]) && pst[p] == 0) begin
            pk[p]    <= d[39:32];
            pneed[p] <= mon_fec ? (d[39:32] + 16) : d[39:32];
            pidx[p]  <= 0;
            pst[p]   <= 1;
          end else if (pst[p] == 1 && client_tx_sync[p] == FC_SYNC_DATA) begin
            for (b = 0; b < 8; b = b + 1) begin
              if (pidx[p] + b < pneed[p])
                pbuf[p][pidx[p] + b] <= d[b*8 +: 8];
            end
            n = pidx[p] + 8;
            if (n > pneed[p]) n = pneed[p];
            pidx[p] <= n;
          end else if (pst[p] == 1 && client_tx_sync[p] == FC_SYNC_CTRL &&
                       fc_is_eof_good(d[31:0])) begin
            if (pidx[p] == pneed[p]) begin
              cap_k <= pk[p];
              cap_n <= pneed[p];
              cap_port <= p;
              for (b = 0; b < pneed[p]; b = b + 1)
                cap[b] <= pbuf[p][b];
              cap_count <= cap_count + 1;
            end
            pst[p] <= 0;
          end else if (client_tx_sync[p] == FC_SYNC_CTRL && d[31:0] == FC_RRDY) begin
            rrdy_count <= rrdy_count + 1;
          end
        end
      end
    end
  end

  always @(posedge clk_system) begin
    if (check_sec && sec_tx_valid[0] &&
        (sec_tx_data[0] !== sys_tx_data[0] || sec_tx_sync[0] !== sys_tx_sync[0]))
      sec_mismatch <= sec_mismatch + 1;
  end

  always @(posedge clk_system or negedge rst_system_n) begin
    if (!rst_system_n || !watch_x) begin
      x_beats0 <= 0;
      x_start0 <= 0;
      x_start1 <= 0;
    end else begin
      if (sys_tx_valid[0] && sys_tx_ready[0]) begin
        x_beats0 <= x_beats0 + 1;
        if (sys_tx_sync[0][1] == 1'b0)
          x_start0 <= x_start0 + 1;
      end
      if (sys_tx_valid[1] && sys_tx_ready[1] && sys_tx_sync[1][1] == 1'b0)
        x_start1 <= x_start1 + 1;
    end
  end

  integer errors = 0;
  integer fec_corrupt = 0;
  reg [7:0] pay [0:255];

  task automatic csr_write_t(input [11:0] a, input [31:0] d);
    begin
      @(posedge clk_client);
      csr_addr  <= a;
      csr_wdata <= d;
      csr_write <= 1'b1;
      @(posedge clk_client);
      csr_write <= 1'b0;
    end
  endtask

  task automatic csr_read_t(input [11:0] a, output [31:0] d);
    begin
      @(posedge clk_client);
      csr_addr <= a;
      csr_read <= 1'b1;
      @(posedge clk_client);
      d = csr_rdata;
      csr_read <= 1'b0;
    end
  endtask

  task automatic push_blk(input [1:0] sync, input [63:0] data);
    integer spins;
    begin
      spins = 0;
      while (((q_wr + 1) % 64) == q_rd) begin
        @(posedge clk_client);
        spins = spins + 1;
        if (spins > 20000) begin
          $display("FAIL queue stalled");
          $finish;
        end
      end
      @(posedge clk_client);
      #1;
      q[q_wr] = {sync, data};
      q_wr = (q_wr + 1) % 64;
    end
  endtask

  task automatic send_pay(
    input integer port,
    input integer k,
    input integer bad,
    input [31:0] sof,
    input [31:0] eof
  );
    integer nwire, n, b;
    reg [63:0] blk;
    reg [31:0] c;
    begin
      active_port = port;
      nwire = mon_fec ? (k + 16) : k;
      c = 32'hFFFF_FFFF;
      for (n = 0; n < k; n = n + 1)
        c = crc32_update(c, pay[n]);
      c = ~c;
      if (bad) c = c ^ 32'h00FF_00FF;
      push_blk(FC_SYNC_CTRL, {16'h0, 8'h00, k[7:0], sof});
      n = 0;
      while (n < nwire) begin
        blk = 64'h0;
        for (b = 0; b < 8; b = b + 1)
          if (n + b < nwire) begin
            blk[b*8 +: 8] = pay[n + b];
            if (fec_corrupt && (n + b) == 2)
              blk[b*8 +: 8] = pay[n + b] ^ 8'h0F;
            if (fec_corrupt && (n + b) == 10)
              blk[b*8 +: 8] = pay[n + b] ^ 8'hA5;
          end
        push_blk(FC_SYNC_DATA, blk);
        n = n + 8;
      end
      push_blk(FC_SYNC_CTRL, {c, eof});
    end
  endtask

  task automatic wait_links(input [7:0] want, input integer limit);
    integer t;
    reg [31:0] cli_l, sys_l, exp_ls;
    begin
      t = 0;
      cli_l = 32'h0;
      sys_l = 32'h0;
      while (t < limit && (cli_l[7:0] != want || sys_l[7:0] != want)) begin
        csr_read_t(12'h01C, cli_l);
        csr_read_t(12'h020, sys_l);
        t = t + 1;
      end
      if (cli_l[7:0] != want || sys_l[7:0] != want) begin
        $display("FAIL link up client %h system %h", cli_l, sys_l);
        csr_read_t(12'h118, rdw);
        $display("FAIL port0 link word %h", rdw);
        errors = errors + 1;
      end else if (want == 8'hFF) begin
        csr_read_t(12'h028, rdw);
        if (rdw[7:0] != 8'hFF) begin
          $display("FAIL system block lock %h", rdw);
          errors = errors + 1;
        end
        exp_ls = {16'h0, 2'b00, FC_LS_ACT, FC_LS_ACT, 6'h0, 1'b1, 1'b1};
        csr_read_t(12'h118, rdw);
        if (rdw !== exp_ls) begin
          $display("FAIL port0 link state %h exp %h", rdw, exp_ls);
          errors = errors + 1;
        end
      end
    end
  endtask

  task automatic wait_cap(input integer port, input integer prev, input integer limit);
    integer t;
    begin
      t = 0;
      while (cap_count == prev && t < limit) begin
        @(posedge clk_client);
        t = t + 1;
      end
      if (cap_count == prev || cap_port != port) begin
        $display("FAIL timeout waiting for port %0d frame (count %0d port %0d)",
                 port, cap_count, cap_port);
        errors = errors + 1;
      end
    end
  endtask

  task automatic expect_bytes(input integer n);
    integer i;
    begin
      if (cap_n < n) begin
        $display("FAIL short capture %0d < %0d", cap_n, n);
        errors = errors + 1;
      end else begin
        for (i = 0; i < n; i = i + 1) begin
          if (cap[i] !== pay[i]) begin
            $display("FAIL payload[%0d]=%h exp %h", i, cap[i], pay[i]);
            errors = errors + 1;
          end
        end
      end
    end
  endtask

  reg [31:0] rdw;
  reg [31:0] crc_snap;
  integer prev;
  integer bi;
  integer b0, s0c, s1c;
  reg [7:0] CW [0:23];

  initial begin
    CW[0]=8'h11; CW[1]=8'h22; CW[2]=8'h33; CW[3]=8'h44;
    CW[4]=8'h55; CW[5]=8'h66; CW[6]=8'h77; CW[7]=8'h88;
    CW[8]=8'h41; CW[9]=8'h32; CW[10]=8'h18; CW[11]=8'h79;
    CW[12]=8'hD8; CW[13]=8'hEE; CW[14]=8'hDD; CW[15]=8'h91;
    CW[16]=8'h4E; CW[17]=8'h3A; CW[18]=8'hAA; CW[19]=8'h7F;
    CW[20]=8'hA1; CW[21]=8'hC6; CW[22]=8'hC7; CW[23]=8'h79;

    repeat (8) @(posedge clk_client);
    rst_client_n = 1;
    rst_system_n = 1;
    repeat (8) @(posedge clk_client);

    csr_read_t(12'h000, rdw);
    if (rdw !== 32'hFC12_8039) begin
      $display("FAIL id %h", rdw);
      errors = errors + 1;
    end
    csr_write_t(12'h014, 32'hA5A5_1234);
    csr_read_t(12'h014, rdw);
    if (rdw !== 32'hA5A5_1234) begin
      $display("FAIL scratch %h", rdw);
      errors = errors + 1;
    end

    // System lanes carry 256b/257b. The client port stays a 66-bit block.
    csr_write_t(12'h008, 32'h0000_002A);
    csr_read_t(12'h008, rdw);
    if (rdw !== 32'h0000_002A) begin
      $display("FAIL xcode csr %h", rdw);
      errors = errors + 1;
    end
    csr_write_t(12'h008, 32'h0000_006A);
    csr_read_t(12'h008, rdw);
    if (rdw !== 32'h0000_006A) begin
      $display("FAIL rs544 csr %h", rdw);
      errors = errors + 1;
    end
    csr_read_t(12'h11C, rdw);
    if (rdw !== 32'h0) begin
      $display("FAIL rs544 count %h", rdw);
      errors = errors + 1;
    end
    csr_write_t(12'h008, 32'h0000_002A);
    csr_write_t(12'h010, 32'h0000_00FF);
    mon_fec = 0;
    drive_en = 1;
    watch_x = 1;
    wait_links(8'hFF, 8000);
    @(negedge clk_system);
    b0 = x_beats0;
    s0c = x_start0;
    s1c = x_start1;
    prev = cap_count;
    for (bi = 0; bi < 8; bi = bi + 1) pay[bi] = 8'h30 + bi[7:0];
    send_pay(0, 8, 0, FC_SOF, FC_EOF);
    wait_cap(0, prev, 8000);
    expect_bytes(8);
    @(negedge clk_system);
    if (x_start1 != s1c) begin
      $display("FAIL lane1 transcode marker %0d", x_start1 - s1c);
      errors = errors + 1;
    end
    if ((x_beats0 - b0) < 8) begin
      $display("FAIL lane0 transcode beats %0d", x_beats0 - b0);
      errors = errors + 1;
    end else if (((x_start0 - s0c) * 2) + 2 < (x_beats0 - b0) ||
                 ((x_start0 - s0c) * 2) > (x_beats0 - b0) + 2) begin
      $display("FAIL lane0 markers %0d of %0d", x_start0 - s0c, x_beats0 - b0);
      errors = errors + 1;
    end
    drive_en = 0;
    watch_x = 0;
    rst_client_n = 0;
    rst_system_n = 0;
    repeat (8) @(posedge clk_client);
    rst_client_n = 1;
    rst_system_n = 1;
    repeat (8) @(posedge clk_client);

    // loopback, scrambler, protect. FEC off.
    csr_write_t(12'h008, 32'h0000_001A);
    repeat (20) @(posedge clk_client);
    csr_write_t(12'h010, 32'h0000_00FF);
    mon_fec = 0;
    drive_en = 1;
    check_sec = 1;
    repeat (80) @(posedge clk_client);
    csr_read_t(12'h00C, rdw);
    if (rdw[7:0] != 8'hFF) begin
      $display("FAIL block lock %h", rdw);
      errors = errors + 1;
    end
    wait_links(8'hFF, 4000);

    prev = cap_count;
    for (bi = 0; bi < 16; bi = bi + 1) pay[bi] = bi[7:0];
    send_pay(0, 16, 0, FC_SOF, FC_EOF);
    wait_cap(0, prev, 4000);
    expect_bytes(16);

    // SOFn3 with the positive-disparity EOFn is a legal Class 3 continuation.
    prev = cap_count;
    for (bi = 0; bi < 8; bi = bi + 1) pay[bi] = 8'h20 + bi[7:0];
    send_pay(0, 8, 0, FC_SOFN3, FC_EOFN_P);
    wait_cap(0, prev, 4000);
    expect_bytes(8);

    // EOFa aborts the frame. Credit is still returned, and the payload is not.
    csr_read_t(12'h108, rdw);
    crc_snap = rdw;
    prev = cap_count;
    for (bi = 0; bi < 4; bi = bi + 1) pay[bi] = 8'hEE;
    send_pay(0, 4, 0, FC_SOF, FC_EOFA);
    repeat (1500) @(posedge clk_client);
    if (cap_count != prev) begin
      $display("FAIL EOFa frame was forwarded");
      errors = errors + 1;
    end
    csr_read_t(12'h108, rdw);
    if (rdw <= crc_snap) begin
      $display("FAIL EOFa did not count as a drop (%h)", rdw);
      errors = errors + 1;
    end

    // Bad CRC is dropped. The following good frame is the one that returns.
    prev = cap_count;
    for (bi = 0; bi < 8; bi = bi + 1) pay[bi] = 8'hC0 + bi[7:0];
    send_pay(0, 8, 1, FC_SOF, FC_EOF);
    for (bi = 0; bi < 8; bi = bi + 1) pay[bi] = 8'h40 + bi[7:0];
    send_pay(0, 8, 0, FC_SOF, FC_EOF);
    wait_cap(0, prev, 4000);
    expect_bytes(8);
    csr_read_t(12'h108, rdw);
    if (rdw < 32'd1) begin
      $display("FAIL crc_err %h", rdw);
      errors = errors + 1;
    end

    // System credit held at 0 keeps the frame on the client side of the gearbox.
    // Reload after the looped R_RDYs from earlier frames have been absorbed.
    repeat (200) @(posedge clk_client);
    csr_write_t(12'h018, 32'h0000_0800);
    repeat (100) @(posedge clk_client);
    csr_write_t(12'h018, 32'h0000_0800);
    repeat (6) @(posedge clk_client);
    csr_read_t(12'h018, rdw);
    if (rdw[7:0] != 8'h00) begin
      $display("FAIL system credit not held (%h)", rdw);
      errors = errors + 1;
    end
    prev = cap_count;
    for (bi = 0; bi < 4; bi = bi + 1) pay[bi] = 8'h90 + bi[7:0];
    send_pay(0, 4, 0, FC_SOF, FC_EOF);
    repeat (1500) @(posedge clk_client);
    if (cap_count != prev) begin
      $display("FAIL frame crossed with system credit 0");
      errors = errors + 1;
    end
    csr_write_t(12'h018, 32'h0000_0808);
    repeat (4) @(posedge clk_client);
    wait_cap(0, prev, 4000);
    expect_bytes(4);

    // Two-symbol correction, then a clean re-encode on the way back.
    csr_write_t(12'h008, 32'h0000_001E);
    mon_fec = 1;
    repeat (30) @(posedge clk_client);
    prev = cap_count;
    for (bi = 0; bi < 24; bi = bi + 1) pay[bi] = CW[bi];
    fec_corrupt = 1;
    send_pay(0, 8, 0, FC_SOF, FC_EOF);
    fec_corrupt = 0;
    wait_cap(0, prev, 8000);
    for (bi = 0; bi < 8; bi = bi + 1) pay[bi] = CW[bi];
    expect_bytes(8);
    csr_read_t(12'h10C, rdw);
    if (rdw < 32'd2) begin
      $display("FAIL fec corrections %h", rdw);
      errors = errors + 1;
    end

    // Port 7, partial last block, FEC back off.
    csr_write_t(12'h008, 32'h0000_001A);
    mon_fec = 0;
    repeat (20) @(posedge clk_client);
    prev = cap_count;
    pay[0] = 8'hAB; pay[1] = 8'hCD; pay[2] = 8'hEF;
    send_pay(7, 3, 0, FC_SOF, FC_EOF);
    wait_cap(7, prev, 4000);
    expect_bytes(3);

    // NOS drops the client link. The frame that follows is discarded, and a
    // later frame is delivered once Idle has brought the link back.
    prev = cap_count;
    push_blk(FC_SYNC_CTRL, {32'h0, FC_NOS});
    push_blk(FC_SYNC_CTRL, {32'h0, FC_NOS});
    for (bi = 0; bi < 4; bi = bi + 1) pay[bi] = 8'hD0 + bi[7:0];
    send_pay(0, 4, 0, FC_SOF, FC_EOF);
    repeat (1500) @(posedge clk_client);
    if (cap_count != prev) begin
      $display("FAIL frame accepted while client link down");
      errors = errors + 1;
    end
    wait_links(8'hFF, 4000);
    prev = cap_count;
    for (bi = 0; bi < 4; bi = bi + 1) pay[bi] = 8'hD0 + bi[7:0];
    send_pay(0, 4, 0, FC_SOF, FC_EOF);
    wait_cap(0, prev, 4000);
    expect_bytes(4);

    if (sec_mismatch != 0) begin
      $display("FAIL secondary protect mismatches %0d", sec_mismatch);
      errors = errors + 1;
    end
    csr_write_t(12'h008, 32'h0000_000A);
    repeat (40) @(posedge clk_system);
    if (sec_tx_valid != 8'h00) begin
      $display("FAIL secondary squelch %h", sec_tx_valid);
      errors = errors + 1;
    end

    if (errors == 0)
      $display("PASS tb_fc128_bridge");
    else
      $display("FAIL tb_fc128_bridge errors=%0d", errors);
    $finish;
  end
endmodule
