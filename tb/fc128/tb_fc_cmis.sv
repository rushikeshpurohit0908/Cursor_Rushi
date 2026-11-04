`timescale 1ns/1ps
// CMIS 5.0 host against a behavioral SFP112: power-up, low power, software
// reset, lane-1 OutputDisableTx, the data-path state machine, module fault,
// and an absent module.
module tb_fc_cmis;
  `include "fc_cmis.vh"

  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;

  logic poll_en = 0;
  logic low_pwr_sw = 0;
  logic sw_pulse = 0;
  logic tx_disable = 0;
  logic dp_deinit = 0;
  logic apply_pulse = 0;
  logic mod_prs_n = 0;
  logic lpmode = 0;
  logic reset_n = 1;
  logic force_fault = 0;
  logic [15:0] temp_s16 = 16'h2880;
  logic [15:0] vcc_u16 = 16'h80E8;

  logic busy, present, nack, armed, low_pwr_rb, tx_disable_rb, dp_deinit_rb;
  logic [7:0] ident, rev, flag0, flag1, flag2, flag3, txdis_byte, dpde_byte;
  logic [2:0] mod_state, slave_state;
  logic int_deasserted, flag_state;
  logic [15:0] temp_rb, vcc_rb;
  logic [3:0] dp_rb, dp_mod;
  logic rx_rb, tx_rb, dp_changed, dp_pending, lane_valid;
  logic rx_mod, tx_mod;
  logic scl_oe, sda_oe, sda_slave;
  wire scl_i = ~scl_oe;
  wire sda_i = ~(sda_oe | sda_slave);

  fc_cmis_host #(.DIV(4), .GAP(8)) host (
    .clk(clk), .rst_n(rst_n),
    .poll_en(poll_en), .low_pwr_sw(low_pwr_sw),
    .sw_reset_pulse(sw_pulse), .tx_disable(tx_disable),
    .dp_deinit(dp_deinit), .apply_pulse(apply_pulse),
    .mod_prs_n(mod_prs_n),
    .busy(busy), .present(present), .nack(nack), .armed(armed),
    .low_pwr_rb(low_pwr_rb), .tx_disable_rb(tx_disable_rb),
    .dp_deinit_rb(dp_deinit_rb),
    .ident(ident), .rev(rev), .mod_state(mod_state),
    .int_deasserted(int_deasserted),
    .flag0(flag0), .flag1(flag1), .flag2(flag2), .flag3(flag3),
    .temp_s16(temp_rb), .vcc_u16(vcc_rb),
    .dp_state(dp_rb), .rx_status(rx_rb), .tx_status(tx_rb),
    .dp_changed(dp_changed), .dp_pending(dp_pending),
    .lane_valid(lane_valid),
    .scl_oe(scl_oe), .sda_oe(sda_oe), .scl_i(scl_i), .sda_i(sda_i)
  );

  cmis_sfp_slave #(
    .PWR_DLY(20), .DP_DLY(8), .TXDIS_INIT(8'hA0), .DPDE_INIT(8'hC0)
  ) mod (
    .clk(clk), .rst_n(rst_n),
    .scl_i(scl_i), .sda_i(sda_i), .sda_oe(sda_slave),
    .lpmode(lpmode), .reset_n(reset_n), .force_fault(force_fault),
    .temp_s16(temp_s16), .vcc_u16(vcc_u16),
    .mod_state(slave_state), .txdis_byte(txdis_byte), .dpde_byte(dpde_byte),
    .dp_state(dp_mod), .rx_status(rx_mod), .tx_status(tx_mod),
    .flag_state(flag_state)
  );

  integer hn;
  reg [3:0] hist [0:63];
  reg [3:0] hist_last;
  initial begin
    hn = 0;
    hist_last = 4'hx;
  end
  always @(posedge clk) begin
    if (rst_n && dp_mod !== hist_last) begin
      if (hn < 64)
        hist[hn] = dp_mod;
      hn = hn + 1;
      hist_last = dp_mod;
    end
  end

  integer errors = 0;
  integer guard;
  integer mark;

  task automatic wait_state;
    input [2:0] want;
    input integer limit;
    input [255:0] tag;
    integer k;
    begin
      for (k = 0; k < limit; k = k + 1) begin
        @(posedge clk);
        if (present && mod_state == want && !busy)
          disable wait_state;
      end
      $display("FAIL %0s state %0d present %b busy %b nack %b ident %h",
               tag, mod_state, present, busy, nack, ident);
      errors = errors + 1;
    end
  endtask

  task automatic wait_tx;
    input want;
    input integer limit;
    input [255:0] tag;
    integer k;
    begin
      for (k = 0; k < limit; k = k + 1) begin
        @(posedge clk);
        if (armed && tx_disable_rb == want && txdis_byte[0] == want && !busy)
          disable wait_tx;
      end
      $display("FAIL %0s tx_rb %b byte %h busy %b", tag, tx_disable_rb, txdis_byte, busy);
      errors = errors + 1;
    end
  endtask

  task automatic wait_dp;
    input [3:0] want;
    input want_rx;
    input want_tx;
    input integer limit;
    input [255:0] tag;
    integer k;
    begin
      for (k = 0; k < limit; k = k + 1) begin
        @(posedge clk);
        if (lane_valid && dp_rb == want && rx_rb == want_rx && tx_rb == want_tx && !busy)
          disable wait_dp;
      end
      $display("FAIL %0s dp %h rx %b tx %b valid %b busy %b",
               tag, dp_rb, rx_rb, tx_rb, lane_valid, busy);
      errors = errors + 1;
    end
  endtask

  task automatic expect_from;
    input integer from;
    input integer n;
    input [3:0] s0, s1, s2, s3, s4, s5, s6, s7, s8;
    integer i, j;
    reg [3:0] s;
    reg ok;
    begin
      ok = 0;
      for (i = from; (i + n <= hn) && (i + n <= 64); i = i + 1) begin
        ok = 1;
        for (j = 0; j < n; j = j + 1) begin
          case (j)
            0: s = s0;
            1: s = s1;
            2: s = s2;
            3: s = s3;
            4: s = s4;
            5: s = s5;
            6: s = s6;
            7: s = s7;
            default: s = s8;
          endcase
          if (hist[i + j] !== s)
            ok = 0;
        end
        if (ok)
          disable expect_from;
      end
      $display("FAIL dp sequence from %0d length %0d count %0d", from, n, hn);
      for (i = 0; i < hn && i < 64; i = i + 1)
        $display("  dp[%0d]=%h", i, hist[i]);
      errors = errors + 1;
    end
  endtask

  initial begin
    guard = 0;
    repeat (4) @(posedge clk);
    rst_n = 1;
    repeat (4) @(posedge clk);

    poll_en = 1;
    wait_state(CMIS_ST_RDY, 200000, "ready");
    if (ident !== CMIS_ID_SFP || rev !== CMIS_REV50) begin
      $display("FAIL id/rev %h %h", ident, rev);
      errors = errors + 1;
    end
    if (temp_rb !== 16'h2880 || vcc_rb !== 16'h80E8) begin
      $display("FAIL monitors temp %h vcc %h", temp_rb, vcc_rb);
      errors = errors + 1;
    end
    if (txdis_byte !== 8'hA0 || flag0[0] !== 1'b1) begin
      $display("FAIL preserve %h flag %h", txdis_byte, flag0);
      errors = errors + 1;
    end
    if (int_deasserted !== 1'b1) begin
      $display("FAIL interrupt deasserted %b", int_deasserted);
      errors = errors + 1;
    end
    // DPDeinit defaults clear, so ModuleReady commissions the lane.
    if (dp_rb !== CMIS_DP_ACT || !rx_rb || !tx_rb || !lane_valid || !dp_changed) begin
      $display("FAIL dp bring-up %h rx %b tx %b valid %b flag %b",
               dp_rb, rx_rb, tx_rb, lane_valid, dp_changed);
      errors = errors + 1;
    end
    if (dpde_byte !== 8'hC0) begin
      $display("FAIL dpdeinit preserve %h", dpde_byte);
      errors = errors + 1;
    end
    expect_from(0, 5, CMIS_DP_DEACT, CMIS_DP_INIT, CMIS_DP_INITED,
                CMIS_DP_TXON, CMIS_DP_ACT, 4'h0, 4'h0, 4'h0, 4'h0);
    begin : flag_clr_watch
      integer k;
      for (k = 0; k < 200000; k = k + 1) begin
        @(posedge clk);
        if (lane_valid && dp_rb == CMIS_DP_ACT && !dp_changed && !busy)
          disable flag_clr_watch;
      end
      $display("FAIL dp flag stuck %b state %h", dp_changed, dp_rb);
      errors = errors + 1;
    end

    tx_disable = 1;
    mark = hn;
    wait_tx(1'b1, 200000, "tx disable");
    if (txdis_byte !== 8'hA1) begin
      $display("FAIL tx byte %h", txdis_byte);
      errors = errors + 1;
    end
    wait_dp(CMIS_DP_INITED, 1'b1, 1'b0, 200000, "tx off");
    expect_from(mark - 1, 3, CMIS_DP_ACT, CMIS_DP_TXOFF, CMIS_DP_INITED,
                4'h0, 4'h0, 4'h0, 4'h0, 4'h0, 4'h0);

    dp_deinit = 1;
    mark = hn;
    wait_dp(CMIS_DP_DEACT, 1'b0, 1'b0, 200000, "deinit");
    if (dpde_byte !== 8'hC1 || dp_deinit_rb !== 1'b1) begin
      $display("FAIL dpdeinit byte %h rb %b", dpde_byte, dp_deinit_rb);
      errors = errors + 1;
    end
    expect_from(mark - 1, 3, CMIS_DP_INITED, CMIS_DP_DEINIT, CMIS_DP_DEACT,
                4'h0, 4'h0, 4'h0, 4'h0, 4'h0, 4'h0);

    dp_deinit = 0;
    mark = hn;
    wait_dp(CMIS_DP_INITED, 1'b1, 1'b0, 200000, "init parked");
    if (dpde_byte !== 8'hC0) begin
      $display("FAIL dpdeinit restored %h", dpde_byte);
      errors = errors + 1;
    end
    expect_from(mark - 1, 3, CMIS_DP_DEACT, CMIS_DP_INIT, CMIS_DP_INITED,
                4'h0, 4'h0, 4'h0, 4'h0, 4'h0, 4'h0);

    tx_disable = 0;
    mark = hn;
    wait_tx(1'b0, 200000, "tx enable");
    if (txdis_byte !== 8'hA0) begin
      $display("FAIL tx restored %h", txdis_byte);
      errors = errors + 1;
    end
    wait_dp(CMIS_DP_ACT, 1'b1, 1'b1, 200000, "tx on");
    expect_from(mark - 1, 3, CMIS_DP_INITED, CMIS_DP_TXON, CMIS_DP_ACT,
                4'h0, 4'h0, 4'h0, 4'h0, 4'h0, 4'h0);

    mark = hn;
    @(negedge clk);
    apply_pulse = 1;
    @(negedge clk);
    apply_pulse = 0;
    begin : apply_watch
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (hn >= mark + 8)
          disable apply_watch;
      end
      $display("FAIL apply did not cycle the data path (count %0d)", hn);
      errors = errors + 1;
    end
    expect_from(mark - 1, 9, CMIS_DP_ACT, CMIS_DP_TXOFF, CMIS_DP_INITED,
                CMIS_DP_DEINIT, CMIS_DP_DEACT, CMIS_DP_INIT, CMIS_DP_INITED,
                CMIS_DP_TXON, CMIS_DP_ACT);
    wait_dp(CMIS_DP_ACT, 1'b1, 1'b1, 400000, "reinit");

    low_pwr_sw = 1;
    wait_state(CMIS_ST_LOW, 200000, "low power");
    low_pwr_sw = 0;
    wait_state(CMIS_ST_RDY, 200000, "high power");

    @(negedge clk);
    sw_pulse = 1;
    @(negedge clk);
    sw_pulse = 0;
    begin : sw_watch
      integer k;
      reg saw;
      saw = 0;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (flag0[0])
          saw = 1;
        if (saw && present && mod_state == CMIS_ST_RDY && !busy && !sw_pulse)
          disable sw_watch;
      end
      $display("FAIL software reset saw %b state %0d present %b", saw, mod_state, present);
      errors = errors + 1;
    end

    force_fault = 1;
    wait_state(CMIS_ST_FLT, 200000, "fault");
    force_fault = 0;
    wait_state(CMIS_ST_RDY, 200000, "fault cleared");

    mod_prs_n = 1;
    begin : abs_watch
      integer k;
      for (k = 0; k < 200000; k = k + 1) begin
        @(posedge clk);
        if (!present && !scl_oe && !sda_oe)
          disable abs_watch;
      end
      $display("FAIL absent present %b oe %b%b", present, scl_oe, sda_oe);
      errors = errors + 1;
    end
    mod_prs_n = 0;
    wait_state(CMIS_ST_RDY, 200000, "inserted");

    reset_n = 0;
    repeat (30) @(posedge clk);
    if (slave_state !== CMIS_ST_LOW) begin
      $display("FAIL hard reset state %0d", slave_state);
      errors = errors + 1;
    end
    reset_n = 1;
    wait_state(CMIS_ST_RDY, 200000, "reset released");

    if (errors == 0)
      $display("PASS tb_fc_cmis");
    else
      $display("FAIL tb_fc_cmis errors=%0d", errors);
    $finish;
  end

  initial begin
    for (guard = 0; guard < 8000000; guard = guard + 1)
      @(posedge clk);
    $display("FAIL tb_fc_cmis timeout");
    $finish;
  end
endmodule
