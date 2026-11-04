`timescale 1ns/1ps
// CMIS 5.0 host against a behavioral SFP112: power-up, low power, software
// reset, lane-1 OutputDisableTx, OutputSquelchForceTx, staged AppSel,
// the data-path state machine, lane flags and IntL, module fault, and an
// absent module.
module tb_fc_cmis;
  `include "fc_cmis.vh"

  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;

  logic poll_en = 0;
  logic low_pwr_sw = 0;
  logic sw_pulse = 0;
  logic tx_disable = 0;
  logic tx_squelch = 0;
  logic [7:0] staged = 8'h10;
  logic dp_deinit = 0;
  logic apply_pulse = 0;
  logic [4:0] lane_mask = 5'h1F;
  logic [11:0] opt_mask = 12'hFFF;
  logic [7:0] mod_mask = 8'hFF;
  logic [7:0] aux_mask = 8'hFF;
  logic [7:0] cst_mask = 8'hFF;
  logic fail_tx = 0;
  logic los_tx = 0;
  logic lol_tx = 0;
  logic los_rx = 0;
  logic lol_rx = 0;
  logic mod_prs_n = 0;
  logic lpmode = 0;
  logic reset_n = 1;
  logic force_fault = 0;
  logic [15:0] temp_s16 = 16'h2880;
  logic [15:0] vcc_u16 = 16'h80E8;
  logic [15:0] opt_tx = 16'd8000;
  logic [15:0] bias_tx = 16'd20000;
  logic [15:0] opt_rx = 16'd1000;
  logic [15:0] aux1_s16 = 16'd12800;
  logic [15:0] aux2_s16 = 16'd3277;
  logic [15:0] aux3_s16 = 16'd18000;
  logic [15:0] cust_s16 = 16'd250;

  logic busy, present, nack, armed, low_pwr_rb, tx_disable_rb, tx_squelch_rb, dp_deinit_rb;
  logic [7:0] ident, rev, flag0, flag1, flag2, flag3, txdis_byte, dpde_byte;
  logic [2:0] mod_state, slave_state;
  logic int_deasserted, flag_state;
  logic [15:0] temp_rb, vcc_rb, aux1_rb, aux2_rb, aux3_rb, cust_rb;
  logic [3:0][31:0] vname, vpn;
  logic [3:0] dp_rb, dp_mod;
  logic rx_rb, tx_rb, dp_changed, dp_pending, lane_valid;
  logic [3:0] cfg_h, cfg_s;
  logic [7:0] active_h, active_s, squelch_byte, ignored;
  logic flag_fail, flag_los_tx, flag_lol_tx, flag_los_rx, flag_lol_rx;
  logic [15:0] opt_tx_rb, bias_rb, opt_rx_rb;
  logic [11:0] opt_flags;
  logic int_n;
  logic rx_mod, tx_mod, pend_s;
  logic scl_oe, sda_oe, sda_slave;
  wire scl_i = ~scl_oe;
  wire sda_i = ~(sda_oe | sda_slave);

  fc_cmis_host #(.DIV(4), .GAP(8)) host (
    .clk(clk), .rst_n(rst_n),
    .poll_en(poll_en), .low_pwr_sw(low_pwr_sw),
    .sw_reset_pulse(sw_pulse), .tx_disable(tx_disable),
    .tx_squelch(tx_squelch), .dp_deinit(dp_deinit),
    .staged_appsel(staged), .apply_pulse(apply_pulse),
    .flag_mask(lane_mask),
    .opt_mask(opt_mask),
    .mod_mask(mod_mask),
    .aux_mask(aux_mask),
    .cst_mask(cst_mask),
    .mod_prs_n(mod_prs_n),
    .busy(busy), .present(present), .nack(nack), .armed(armed),
    .low_pwr_rb(low_pwr_rb), .tx_disable_rb(tx_disable_rb),
    .tx_squelch_rb(tx_squelch_rb),
    .dp_deinit_rb(dp_deinit_rb),
    .ident(ident), .rev(rev), .mod_state(mod_state),
    .int_deasserted(int_deasserted),
    .flag0(flag0), .flag1(flag1), .flag2(flag2), .flag3(flag3),
    .temp_s16(temp_rb), .vcc_u16(vcc_rb),
    .aux1_s16(aux1_rb), .aux2_s16(aux2_rb),
    .aux3_s16(aux3_rb), .cust_s16(cust_rb),
    .vendor_name(vname), .vendor_pn(vpn),
    .dp_state(dp_rb), .rx_status(rx_rb), .tx_status(tx_rb),
    .dp_changed(dp_changed), .dp_pending(dp_pending),
    .lane_valid(lane_valid),
    .config_status(cfg_h), .active_appsel(active_h),
    .flag_fail_tx(flag_fail), .flag_los_tx(flag_los_tx),
    .flag_lol_tx(flag_lol_tx), .flag_los_rx(flag_los_rx),
    .flag_lol_rx(flag_lol_rx),
    .opt_tx_u16(opt_tx_rb), .bias_tx_u16(bias_rb), .opt_rx_u16(opt_rx_rb),
    .opt_flags(opt_flags),
    .scl_oe(scl_oe), .sda_oe(sda_oe), .scl_i(scl_i), .sda_i(sda_i)
  );

  cmis_sfp_slave #(
    .PWR_DLY(20000), .DP_DLY(8), .TXDIS_INIT(8'hA0), .DPDE_INIT(8'hC0)
  ) mod (
    .clk(clk), .rst_n(rst_n),
    .scl_i(scl_i), .sda_i(sda_i), .sda_oe(sda_slave), .int_n(int_n),
    .lpmode(lpmode), .reset_n(reset_n), .force_fault(force_fault),
    .fail_tx(fail_tx), .los_tx(los_tx), .lol_tx(lol_tx),
    .los_rx(los_rx), .lol_rx(lol_rx),
    .temp_s16(temp_s16), .vcc_u16(vcc_u16),
    .opt_tx_u16(opt_tx), .bias_tx_u16(bias_tx), .opt_rx_u16(opt_rx),
    .aux1_s16(aux1_s16), .aux2_s16(aux2_s16),
    .aux3_s16(aux3_s16), .cust_s16(cust_s16),
    .mod_state(slave_state), .txdis_byte(txdis_byte), .dpde_byte(dpde_byte),
    .dp_state(dp_mod), .rx_status(rx_mod), .tx_status(tx_mod),
    .flag_state(flag_state),
    .squelch_byte(squelch_byte), .config_status(cfg_s),
    .active_appsel(active_s), .dp_init_pend(pend_s),
    .apply_ignored(ignored)
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

  task automatic wait_vendor;
    input integer limit;
    input [255:0] tag;
    integer k;
    begin
      for (k = 0; k < limit; k = k + 1) begin
        @(posedge clk);
        if (vname[0] == CMIS_VENDOR_NAME[127:96] &&
            vname[1] == CMIS_VENDOR_NAME[95:64] &&
            vname[2] == CMIS_VENDOR_NAME[63:32] &&
            vname[3] == CMIS_VENDOR_NAME[31:0] &&
            vpn[0] == CMIS_VENDOR_PN[127:96] &&
            vpn[1] == CMIS_VENDOR_PN[95:64] &&
            vpn[2] == CMIS_VENDOR_PN[63:32] &&
            vpn[3] == CMIS_VENDOR_PN[31:0] && !busy)
          disable wait_vendor;
      end
      $display("FAIL %0s name %h %h %h %h pn %h %h %h %h",
               tag, vname[0], vname[1], vname[2], vname[3],
               vpn[0], vpn[1], vpn[2], vpn[3]);
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
    if (vname !== '0 || vpn !== '0) begin
      $display("FAIL vendor reset name %h pn %h", vname[0], vpn[0]);
      errors = errors + 1;
    end

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
    // The lane image is the previous status pass, so wait until that pass
    // shows DPActivated rather than the sample taken while the module was
    // still powering up.
    begin : dp_bring
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (dp_rb == CMIS_DP_ACT && rx_rb && tx_rb && lane_valid && dp_changed && !busy)
          disable dp_bring;
      end
      $display("FAIL dp bring-up %h rx %b tx %b valid %b flag %b",
               dp_rb, rx_rb, tx_rb, lane_valid, dp_changed);
      errors = errors + 1;
    end
    if (dpde_byte !== 8'hC0) begin
      $display("FAIL dpdeinit preserve %h", dpde_byte);
      errors = errors + 1;
    end
    if (mod.mem[86] !== CMIS_H_128 || mod.mem[87] !== CMIS_M_128 ||
        mod.mem[90] !== CMIS_H_64  || mod.mem[91] !== CMIS_M_64 ||
        mod.mem[94] !== CMIS_H_32  || mod.mem[95] !== CMIS_M_32 ||
        mod.mem[88] !== CMIS_LANES11 || mod.mem[89] !== CMIS_LANE1 ||
        mod.mem[2][6] !== 1'b0 || active_s !== CMIS_APP_128 ||
        cfg_s !== CMIS_CFG_NONE || squelch_byte !== 8'hA0) begin
      $display("FAIL app ad %h %h %h %h step %b act %h cfg %h sq %h",
               mod.mem[86], mod.mem[87], mod.mem[90], mod.mem[94], mod.mem[2][6],
               active_s, cfg_s, squelch_byte);
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

    tx_squelch = 1;
    begin : sq_on
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (lane_valid && dp_rb == CMIS_DP_INITED && dp_mod == CMIS_DP_INITED &&
            tx_squelch_rb && !tx_rb && rx_rb && squelch_byte == 8'hA1 && !busy)
          disable sq_on;
      end
      $display("FAIL squelch on st %h byte %h tx %b rx %b",
               dp_rb, squelch_byte, tx_rb, rx_rb);
      errors = errors + 1;
    end
    tx_squelch = 0;
    begin : sq_off
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (lane_valid && dp_rb == CMIS_DP_ACT && dp_mod == CMIS_DP_ACT &&
            !tx_squelch_rb && tx_rb && squelch_byte == 8'hA0 && !busy)
          disable sq_off;
      end
      $display("FAIL squelch off st %h byte %h tx %b", dp_rb, squelch_byte, tx_rb);
      errors = errors + 1;
    end

    // Masks power up set, so a held LOS is visible and IntL stays high.
    // Dropping the input leaves the flag until the next status read.
    los_rx = 1;
    begin : los_masked
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (flag_los_rx && int_n && int_deasserted &&
            mod.p10[CMIS_MLOSRX] == 8'hFF && !flag_fail && !busy)
          disable los_masked;
      end
      $display("FAIL masked LOS flag %b int %b deassert %b mask %h",
               flag_los_rx, int_n, int_deasserted, mod.p10[CMIS_MLOSRX]);
      errors = errors + 1;
    end
    los_rx = 0;
    begin : los_clr
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (!flag_los_rx && int_n && !busy)
          disable los_clr;
      end
      $display("FAIL LOS flag did not clear %b", flag_los_rx);
      errors = errors + 1;
    end
    // A one-shot pulse is held until that same read.
    los_rx = 1;
    repeat (30) @(posedge clk);
    los_rx = 0;
    begin : los_pulse
      integer k;
      reg saw;
      saw = 0;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (flag_los_rx)
          saw = 1;
        if (saw && !flag_los_rx && !los_rx && !busy)
          disable los_pulse;
      end
      $display("FAIL LOS pulse saw %b flag %b", saw, flag_los_rx);
      errors = errors + 1;
    end
    // Unmask LOSFlagRx only. Bit 0 follows the CSR; bits [7:1] stay 1.
    lane_mask[3] = 0;
    los_rx = 1;
    begin : los_open
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (flag_los_rx && !int_n && !int_deasserted &&
            mod.p10[CMIS_MLOSRX] == 8'hFE &&
            mod.p10[CMIS_MFAILTX] == 8'hFF && mod.p10[CMIS_MLOLRX] == 8'hFF &&
            !busy)
          disable los_open;
      end
      $display("FAIL unmasked LOS flag %b int %b byte3 %b mask %h %h",
               flag_los_rx, int_n, int_deasserted,
               mod.p10[CMIS_MLOSRX], mod.p10[CMIS_MFAILTX]);
      errors = errors + 1;
    end
    los_rx = 0;
    lane_mask = 5'h1F;
    begin : los_done
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (!flag_los_rx && int_n && int_deasserted &&
            mod.p10[CMIS_MLOSRX] == 8'hFF && !busy)
          disable los_done;
      end
      $display("FAIL LOS restore flag %b int %b mask %h",
               flag_los_rx, int_n, mod.p10[CMIS_MLOSRX]);
      errors = errors + 1;
    end

    // 8000 / 20000 / 1000 sit inside every threshold, so no optical flag
    // is set and the masks, which power up at 1, keep IntL high.
    begin : mon_quiet
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (opt_tx_rb == 16'd8000 && bias_rb == 16'd20000 && opt_rx_rb == 16'd1000 &&
            opt_flags == 12'h000 && int_n && !busy)
          disable mon_quiet;
      end
      $display("FAIL monitors %h %h %h flags %h", opt_tx_rb, bias_rb, opt_rx_rb, opt_flags);
      errors = errors + 1;
    end
    // Equal to the high-alarm threshold is not a high alarm. It is still
    // above the high-warning threshold.
    opt_tx = CMIS_TX_HA;
    begin : mon_eq
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (opt_tx_rb == CMIS_TX_HA && opt_flags[3:0] == 4'b0100 && int_n && !busy)
          disable mon_eq;
      end
      $display("FAIL tx equal HA flags %h tx %h", opt_flags, opt_tx_rb);
      errors = errors + 1;
    end
    opt_tx = CMIS_TX_HA + 16'd1;
    begin : mon_ha
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (opt_tx_rb == CMIS_TX_HA + 16'd1 && opt_flags[3:0] == 4'b0101 &&
            int_n && mod.p10[CMIS_M_TXHA] == 8'hFF && !busy)
          disable mon_ha;
      end
      $display("FAIL tx high alarm flags %h mask %h", opt_flags, mod.p10[CMIS_M_TXHA]);
      errors = errors + 1;
    end
    // Unmask Tx high alarm only. Bit 0 follows the CSR; bits [7:1] stay 1.
    opt_mask[0] = 1'b0;
    begin : mon_int
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (opt_flags[0] && !opt_flags[1] && !int_n && !int_deasserted &&
            mod.p10[CMIS_M_TXHA] == 8'hFE && mod.p10[CMIS_M_TXHW] == 8'hFF &&
            mod.p10[CMIS_M_RXLW] == 8'hFF && !busy)
          disable mon_int;
      end
      $display("FAIL tx alarm IntL flags %h int %b mask %h %h",
               opt_flags, int_n, mod.p10[CMIS_M_TXHA], mod.p10[CMIS_M_TXHW]);
      errors = errors + 1;
    end
    opt_tx = 16'd8000;
    opt_mask = 12'hFFF;
    begin : mon_rest
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (opt_flags == 12'h000 && opt_tx_rb == 16'd8000 && int_n &&
            int_deasserted && mod.p10[CMIS_M_TXHA] == 8'hFF && !busy)
          disable mon_rest;
      end
      $display("FAIL tx alarm restore flags %h int %b mask %h",
               opt_flags, int_n, mod.p10[CMIS_M_TXHA]);
      errors = errors + 1;
    end
    // Equal to the low-alarm threshold is not a low alarm. It is still
    // below the low-warning threshold.
    bias_tx = CMIS_BI_LA;
    begin : mon_bias
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (bias_rb == CMIS_BI_LA && opt_flags[7:4] == 4'b1000 && int_n && !busy)
          disable mon_bias;
      end
      $display("FAIL bias equal LA flags %h bias %h", opt_flags, bias_rb);
      errors = errors + 1;
    end
    bias_tx = CMIS_BI_LA - 16'd1;
    begin : mon_bias_la
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (bias_rb == CMIS_BI_LA - 16'd1 && opt_flags[7:4] == 4'b1010 && !busy)
          disable mon_bias_la;
      end
      $display("FAIL bias low alarm flags %h bias %h", opt_flags, bias_rb);
      errors = errors + 1;
    end
    bias_tx = 16'd20000;
    begin : mon_bias_clr
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (opt_flags == 12'h000 && bias_rb == 16'd20000 && !busy)
          disable mon_bias_clr;
      end
      $display("FAIL bias restore flags %h", opt_flags);
      errors = errors + 1;
    end
    // A one-shot excursion below the Rx low alarm is held until that read.
    opt_rx = CMIS_RX_LA - 16'd1;
    repeat (30) @(posedge clk);
    opt_rx = 16'd1000;
    begin : mon_pulse
      integer k;
      reg saw;
      saw = 0;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (opt_flags[9])
          saw = 1;
        if (saw && opt_flags == 12'h000 && opt_rx_rb == 16'd1000 && !busy)
          disable mon_pulse;
      end
      $display("FAIL rx pulse saw %b flags %h rx %h", saw, opt_flags, opt_rx_rb);
      errors = errors + 1;
    end

    // 40.5 C and 3.300 V sit inside the module windows. Byte 32 powers up
    // at FF, so a later alarm stays off IntL until the mask opens.
    begin : mod_quiet
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (temp_rb == 16'h2880 && vcc_rb == 16'h80E8 && flag1 == 8'h00 &&
            int_n && mod.mem[CMIS_MONMSK] == 8'hFF && !busy)
          disable mod_quiet;
      end
      $display("FAIL module quiet flags %h mask %h temp %h vcc %h",
               flag1, mod.mem[CMIS_MONMSK], temp_rb, vcc_rb);
      errors = errors + 1;
    end
    // Equal to the high-alarm threshold is not a high alarm. It is still
    // above the high-warning threshold.
    temp_s16 = CMIS_TEMP_HA;
    begin : mod_eq
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (temp_rb == CMIS_TEMP_HA && flag1 == 8'h20 && int_n && !busy)
          disable mod_eq;
      end
      $display("FAIL temp equal HA flags %h temp %h", flag1, temp_rb);
      errors = errors + 1;
    end
    temp_s16 = CMIS_TEMP_HA + 16'd1;
    begin : mod_ha
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (temp_rb == CMIS_TEMP_HA + 16'd1 && flag1 == 8'hA0 && int_n &&
            mod.mem[CMIS_MONMSK] == 8'hFF && !busy)
          disable mod_ha;
      end
      $display("FAIL temp high alarm flags %h mask %h", flag1, mod.mem[CMIS_MONMSK]);
      errors = errors + 1;
    end
    // Unmask temperature high alarm only. The other seven mask bits stay 1.
    mod_mask = 8'h7F;
    begin : mod_int
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (flag1[7] && !flag1[6] && !int_n && !int_deasserted &&
            mod.mem[CMIS_MONMSK] == 8'h7F && !busy)
          disable mod_int;
      end
      $display("FAIL temp alarm IntL flags %h int %b mask %h",
               flag1, int_n, mod.mem[CMIS_MONMSK]);
      errors = errors + 1;
    end
    temp_s16 = 16'h2880;
    mod_mask = 8'hFF;
    begin : mod_rest
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (flag1 == 8'h00 && temp_rb == 16'h2880 && int_n && int_deasserted &&
            mod.mem[CMIS_MONMSK] == 8'hFF && !busy)
          disable mod_rest;
      end
      $display("FAIL temp restore flags %h int %b mask %h",
               flag1, int_n, mod.mem[CMIS_MONMSK]);
      errors = errors + 1;
    end
    // Equal to the low-alarm threshold is not a low alarm. It is still
    // below the low-warning threshold.
    vcc_u16 = CMIS_VCC_LA;
    begin : mod_vcc
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (vcc_rb == CMIS_VCC_LA && flag1 == 8'h01 && int_n && !busy)
          disable mod_vcc;
      end
      $display("FAIL vcc equal LA flags %h vcc %h", flag1, vcc_rb);
      errors = errors + 1;
    end
    vcc_u16 = CMIS_VCC_LA - 16'd1;
    begin : mod_vcc_la
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (vcc_rb == CMIS_VCC_LA - 16'd1 && flag1 == 8'h05 && !busy)
          disable mod_vcc_la;
      end
      $display("FAIL vcc low alarm flags %h vcc %h", flag1, vcc_rb);
      errors = errors + 1;
    end
    vcc_u16 = 16'h80E8;
    begin : mod_vcc_clr
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (flag1 == 8'h00 && vcc_rb == 16'h80E8 && !busy)
          disable mod_vcc_clr;
      end
      $display("FAIL vcc restore flags %h", flag1);
      errors = errors + 1;
    end
    // One step below -5 C sets both low flags. The same bits read as a
    // large unsigned value, so an unsigned compare would raise a high
    // alarm instead. The pulse is held until byte 9 is read.
    temp_s16 = CMIS_TEMP_LA - 16'd1;
    repeat (30) @(posedge clk);
    temp_s16 = 16'h2880;
    begin : mod_pulse
      integer k;
      reg saw;
      saw = 0;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (flag1[6] && flag1[4] && !flag1[7] && !flag1[5])
          saw = 1;
        if (saw && flag1 == 8'h00 && temp_rb == 16'h2880 && !busy)
          disable mod_pulse;
      end
      $display("FAIL temp pulse saw %b flags %h temp %h", saw, flag1, temp_rb);
      errors = errors + 1;
    end

    // 50 C and about +10% TEC current sit inside the Aux windows. Byte 33
    // powers up at FF, so a later alarm stays off IntL until the mask opens.
    // Flags are byte 10, already inside the bytes 0-17 poll.
    begin : aux_quiet
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (aux1_rb == 16'd12800 && aux2_rb == 16'd3277 && flag2 == 8'h00 &&
            flag1 == 8'h00 && int_n && mod.mem[CMIS_AUXMSK] == 8'hFF && !busy)
          disable aux_quiet;
      end
      $display("FAIL aux quiet flags %h mask %h aux1 %h aux2 %h",
               flag2, mod.mem[CMIS_AUXMSK], aux1_rb, aux2_rb);
      errors = errors + 1;
    end
    // Equal to the laser-temperature high alarm is not a high alarm. It is
    // still above the high-warning threshold.
    aux1_s16 = CMIS_AUX1_HA;
    begin : aux_eq
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (aux1_rb == CMIS_AUX1_HA && flag2 == 8'h20 && int_n && !busy)
          disable aux_eq;
      end
      $display("FAIL aux1 equal HA flags %h aux1 %h", flag2, aux1_rb);
      errors = errors + 1;
    end
    aux1_s16 = CMIS_AUX1_HA + 16'd1;
    begin : aux_ha
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (aux1_rb == CMIS_AUX1_HA + 16'd1 && flag2 == 8'hA0 && int_n &&
            mod.mem[CMIS_AUXMSK] == 8'hFF && !busy)
          disable aux_ha;
      end
      $display("FAIL aux1 high alarm flags %h mask %h", flag2, mod.mem[CMIS_AUXMSK]);
      errors = errors + 1;
    end
    // Unmask Aux1 high alarm only. The other seven mask bits stay 1.
    aux_mask = 8'h7F;
    begin : aux_int
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (flag2[7] && !flag2[6] && !int_n && !int_deasserted &&
            mod.mem[CMIS_AUXMSK] == 8'h7F && !busy)
          disable aux_int;
      end
      $display("FAIL aux1 alarm IntL flags %h int %b mask %h",
               flag2, int_n, mod.mem[CMIS_AUXMSK]);
      errors = errors + 1;
    end
    aux1_s16 = 16'd12800;
    aux_mask = 8'hFF;
    begin : aux_rest
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (flag2 == 8'h00 && aux1_rb == 16'd12800 && int_n && int_deasserted &&
            mod.mem[CMIS_AUXMSK] == 8'hFF && !busy)
          disable aux_rest;
      end
      $display("FAIL aux1 restore flags %h int %b mask %h",
               flag2, int_n, mod.mem[CMIS_AUXMSK]);
      errors = errors + 1;
    end
    // Equal to the TEC low-alarm threshold is not a low alarm. It is still
    // below the low-warning threshold. The value is negative.
    aux2_s16 = CMIS_AUX2_LA;
    begin : aux_tec
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (aux2_rb == CMIS_AUX2_LA && flag2 == 8'h01 && int_n && !busy)
          disable aux_tec;
      end
      $display("FAIL aux2 equal LA flags %h aux2 %h", flag2, aux2_rb);
      errors = errors + 1;
    end
    aux2_s16 = CMIS_AUX2_LA - 16'd1;
    begin : aux_tec_la
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (aux2_rb == CMIS_AUX2_LA - 16'd1 && flag2 == 8'h05 &&
            !flag2[7] && !flag2[5] && !busy)
          disable aux_tec_la;
      end
      $display("FAIL aux2 low alarm flags %h aux2 %h", flag2, aux2_rb);
      errors = errors + 1;
    end
    aux2_s16 = 16'd3277;
    begin : aux_tec_clr
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (flag2 == 8'h00 && aux2_rb == 16'd3277 && !busy)
          disable aux_tec_clr;
      end
      $display("FAIL aux2 restore flags %h", flag2);
      errors = errors + 1;
    end
    // One step below -80% sets both TEC low flags. The same bits read as a
    // large unsigned value, so an unsigned compare would raise a high
    // alarm instead. The pulse is held until byte 10 is read.
    aux2_s16 = CMIS_AUX2_LA - 16'd1;
    repeat (30) @(posedge clk);
    aux2_s16 = 16'd3277;
    begin : aux_pulse
      integer k;
      reg saw;
      saw = 0;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (flag2[2] && flag2[0] && !flag2[7] && !flag2[5])
          saw = 1;
        if (saw && flag2 == 8'h00 && aux2_rb == 16'd3277 && !busy)
          disable aux_pulse;
      end
      $display("FAIL aux pulse saw %b flags %h aux2 %h", saw, flag2, aux2_rb);
      errors = errors + 1;
    end

    // 1.800 V and +250 MHz sit inside the Aux3 and custom windows. Byte 34
    // powers up at FF. Flags are byte 11, already inside the bytes 0-17 poll.
    begin : cst_quiet
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (aux3_rb == 16'd18000 && cust_rb == 16'd250 && flag3 == 8'h00 &&
            flag2 == 8'h00 && int_n && mod.mem[CMIS_CSTMSK] == 8'hFF && !busy)
          disable cst_quiet;
      end
      $display("FAIL cst quiet flags %h mask %h aux3 %h cust %h",
               flag3, mod.mem[CMIS_CSTMSK], aux3_rb, cust_rb);
      errors = errors + 1;
    end
    // Equal to the Vcc2 high alarm is not a high alarm. It is still above
    // the high-warning threshold.
    aux3_s16 = CMIS_AUX3_HA;
    begin : cst_eq
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (aux3_rb == CMIS_AUX3_HA && flag3 == 8'h20 && int_n && !busy)
          disable cst_eq;
      end
      $display("FAIL aux3 equal HA flags %h aux3 %h", flag3, aux3_rb);
      errors = errors + 1;
    end
    aux3_s16 = CMIS_AUX3_HA + 16'd1;
    begin : cst_ha
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (aux3_rb == CMIS_AUX3_HA + 16'd1 && flag3 == 8'hA0 && int_n &&
            mod.mem[CMIS_CSTMSK] == 8'hFF && !busy)
          disable cst_ha;
      end
      $display("FAIL aux3 high alarm flags %h mask %h", flag3, mod.mem[CMIS_CSTMSK]);
      errors = errors + 1;
    end
    // Unmask Aux3 high alarm only. The other seven mask bits stay 1.
    cst_mask = 8'h7F;
    begin : cst_int
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (flag3[7] && !flag3[6] && !int_n && !int_deasserted &&
            mod.mem[CMIS_CSTMSK] == 8'h7F && !busy)
          disable cst_int;
      end
      $display("FAIL aux3 alarm IntL flags %h int %b mask %h",
               flag3, int_n, mod.mem[CMIS_CSTMSK]);
      errors = errors + 1;
    end
    aux3_s16 = 16'd18000;
    cst_mask = 8'hFF;
    begin : cst_rest
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (flag3 == 8'h00 && aux3_rb == 16'd18000 && int_n && int_deasserted &&
            mod.mem[CMIS_CSTMSK] == 8'hFF && !busy)
          disable cst_rest;
      end
      $display("FAIL aux3 restore flags %h int %b mask %h",
               flag3, int_n, mod.mem[CMIS_CSTMSK]);
      errors = errors + 1;
    end
    // Equal to the frequency-error low alarm is not a low alarm. It is
    // still below the low-warning threshold. The value is negative.
    cust_s16 = CMIS_CUST_LA;
    begin : cst_freq
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (cust_rb == CMIS_CUST_LA && flag3 == 8'h01 && int_n && !busy)
          disable cst_freq;
      end
      $display("FAIL custom equal LA flags %h cust %h", flag3, cust_rb);
      errors = errors + 1;
    end
    cust_s16 = CMIS_CUST_LA - 16'd1;
    begin : cst_freq_la
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (cust_rb == CMIS_CUST_LA - 16'd1 && flag3 == 8'h05 &&
            !flag3[7] && !flag3[5] && !busy)
          disable cst_freq_la;
      end
      $display("FAIL custom low alarm flags %h cust %h", flag3, cust_rb);
      errors = errors + 1;
    end
    cust_s16 = 16'd250;
    begin : cst_freq_clr
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (flag3 == 8'h00 && cust_rb == 16'd250 && !busy)
          disable cst_freq_clr;
      end
      $display("FAIL custom restore flags %h", flag3);
      errors = errors + 1;
    end
    // The most negative Vcc2 code sets both low flags. The same bits read
    // as a large unsigned value, so an unsigned compare would raise a high
    // alarm instead. The pulse is held until byte 11 is read.
    aux3_s16 = 16'h8000;
    repeat (30) @(posedge clk);
    aux3_s16 = 16'd18000;
    begin : cst_pulse
      integer k;
      reg saw;
      saw = 0;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (flag3[6] && flag3[4] && !flag3[7] && !flag3[5])
          saw = 1;
        if (saw && flag3 == 8'h00 && aux3_rb == 16'd18000 && !busy)
          disable cst_pulse;
      end
      $display("FAIL aux3 pulse saw %b flags %h aux3 %h", saw, flag3, aux3_rb);
      errors = errors + 1;
    end
    // Page 00h is read once after byte 34, before the armed status pass.
    // The bytes 0-17 poll does not carry the name.
    wait_vendor(800000, "vendor");

    staged = 8'h20;
    @(negedge clk);
    apply_pulse = 1;
    @(negedge clk);
    apply_pulse = 0;
    begin : app_ok
      integer k;
      reg saw_busy, saw_pend, saw_down, pulsed;
      saw_busy = 0;
      saw_pend = 0;
      saw_down = 0;
      pulsed = 0;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (cfg_s == CMIS_CFG_BUSY)
          saw_busy = 1;
        // A second Apply while ConfigInProgress is in force must be dropped.
        if (saw_busy && !pulsed && !busy && cfg_s == CMIS_CFG_BUSY) begin
          pulsed = 1;
          apply_pulse <= 1;
        end else if (pulsed && apply_pulse) begin
          apply_pulse <= 0;
        end
        if (pend_s)
          saw_pend = 1;
        if (saw_pend && dp_mod == CMIS_DP_DEACT)
          saw_down = 1;
        if (saw_busy && saw_pend && saw_down && ignored != 8'h00 &&
            cfg_h == CMIS_CFG_OK && active_h == 8'h20 && active_s == 8'h20 &&
            lane_valid && dp_rb == CMIS_DP_ACT && dp_mod == CMIS_DP_ACT && !busy)
          disable app_ok;
      end
      $display("FAIL appsel 64G cfg %h/%h act %h/%h busy %b pend %b down %b ign %h dp %h",
               cfg_h, cfg_s, active_h, active_s, saw_busy, saw_pend, saw_down,
               ignored, dp_mod);
      errors = errors + 1;
    end

    staged = 8'h12;
    @(negedge clk);
    apply_pulse = 1;
    @(negedge clk);
    apply_pulse = 0;
    begin : app_dp
      integer k;
      reg left;
      left = 0;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (dp_mod != CMIS_DP_ACT && dp_mod != CMIS_DP_TXON &&
            dp_mod != CMIS_DP_TXOFF && dp_mod != CMIS_DP_INITED)
          left = 1;
        if (cfg_h == CMIS_CFG_DP && active_h == 8'h20 && active_s == 8'h20 &&
            lane_valid && dp_rb == CMIS_DP_ACT && !left && !busy)
          disable app_dp;
      end
      $display("FAIL bad dpid cfg %h act %h left %b dp %h",
               cfg_h, active_h, left, dp_mod);
      errors = errors + 1;
    end

    staged = 8'h70;
    @(negedge clk);
    apply_pulse = 1;
    @(negedge clk);
    apply_pulse = 0;
    begin : app_bad
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (cfg_h == CMIS_CFG_APP && active_h == 8'h20 && active_s == 8'h20 &&
            lane_valid && dp_rb == CMIS_DP_ACT && dp_mod == CMIS_DP_ACT && !busy)
          disable app_bad;
      end
      $display("FAIL bad appsel cfg %h act %h dp %h", cfg_h, active_h, dp_mod);
      errors = errors + 1;
    end

    staged = 8'h11;
    @(negedge clk);
    apply_pulse = 1;
    @(negedge clk);
    apply_pulse = 0;
    begin : app_ex
      integer k;
      reg saw_down;
      saw_down = 0;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (dp_mod == CMIS_DP_DEACT)
          saw_down = 1;
        if (saw_down && cfg_h == CMIS_CFG_OK && active_h == 8'h11 &&
            active_s == 8'h11 && lane_valid && dp_rb == CMIS_DP_ACT && !busy)
          disable app_ex;
      end
      $display("FAIL explicit cfg %h act %h down %b dp %h",
               cfg_h, active_h, saw_down, dp_mod);
      errors = errors + 1;
    end

    low_pwr_sw = 1;
    wait_state(CMIS_ST_LOW, 400000, "low power");
    @(negedge clk);
    apply_pulse = 1;
    @(negedge clk);
    apply_pulse = 0;
    begin : app_rej
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (cfg_h == CMIS_CFG_REJ && active_h == 8'h11 && active_s == 8'h11 && !busy)
          disable app_rej;
      end
      $display("FAIL not ready cfg %h act %h/%h", cfg_h, active_h, active_s);
      errors = errors + 1;
    end
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
        if (!present && !scl_oe && !sda_oe && vname == '0 && vpn == '0)
          disable abs_watch;
      end
      $display("FAIL absent present %b oe %b%b", present, scl_oe, sda_oe);
      errors = errors + 1;
    end
    mod_prs_n = 0;
    wait_state(CMIS_ST_RDY, 200000, "inserted");
    wait_vendor(800000, "vendor reinserted");

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
    for (guard = 0; guard < 20000000; guard = guard + 1)
      @(posedge clk);
    $display("FAIL tb_fc_cmis timeout");
    $finish;
  end
endmodule
