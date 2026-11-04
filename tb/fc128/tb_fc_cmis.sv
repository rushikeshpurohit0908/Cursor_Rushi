`timescale 1ns/1ps
// CMIS 5.0 host against a behavioral SFP112: power-up, low power, software
// reset, lane-1 OutputDisableTx, the data path, forced squelch, staged
// AppSel, lane flags and IntL, module fault, and an absent module.
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
  logic dp_deinit = 0;
  logic [7:0] staged = 8'h10;
  logic apply_p = 0;
  logic mask_fail = 1;
  logic mask_los_tx = 1;
  logic mask_lol_tx = 1;
  logic mask_los_rx = 1;
  logic mask_lol_rx = 1;
  logic [11:0] mask_alm = 12'hFFF;
  logic [7:0] mask_mon = 8'hFF;
  logic tx_fail = 0;
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
  logic [15:0] opt_tx_u16 = 16'h2710;
  logic [15:0] bias_tx_u16 = 16'h4E20;
  logic [15:0] opt_rx_u16 = 16'h1388;

  logic busy, present, nack, armed, low_pwr_rb, tx_disable_rb, tx_squelch_rb;
  logic dp_deinit_rb, dp_act, dp_pend, out_rx, out_tx, dp_flag_h, dp_valid;
  logic [7:0] ident, rev, flag0, flag1, flag2, flag3, txdis_byte, dpdeinit_byte;
  logic [7:0] active_h, active_s, squelch_byte;
  logic [3:0] dp_rb, slave_dp, cfg_h, cfg_s;
  logic [2:0] mod_state, slave_state;
  logic int_deasserted, flag_state, int_n;
  logic flag_fail, flag_los_tx, flag_lol_tx, flag_los_rx, flag_lol_rx;
  logic [11:0] flag_alm;
  logic [15:0] temp_rb, vcc_rb, opt_tx_rb, bias_rb, opt_rx_rb;
  logic scl_oe, sda_oe, sda_slave;
  wire scl_i = ~scl_oe;
  wire sda_i = ~(sda_oe | sda_slave);

  fc_cmis_host #(.DIV(4), .GAP(8)) host (
    .clk(clk), .rst_n(rst_n),
    .poll_en(poll_en), .low_pwr_sw(low_pwr_sw),
    .sw_reset_pulse(sw_pulse), .tx_disable(tx_disable),
    .tx_squelch(tx_squelch), .dp_deinit(dp_deinit),
    .staged_appsel(staged), .apply_pulse(apply_p),
    .mask_fail(mask_fail), .mask_los_tx(mask_los_tx),
    .mask_lol_tx(mask_lol_tx), .mask_los_rx(mask_los_rx),
    .mask_lol_rx(mask_lol_rx),
    .mask_alm(mask_alm),
    .mask_mon(mask_mon),
    .mod_prs_n(mod_prs_n),
    .busy(busy), .present(present), .nack(nack), .armed(armed),
    .low_pwr_rb(low_pwr_rb), .tx_disable_rb(tx_disable_rb),
    .tx_squelch_rb(tx_squelch_rb),
    .dp_state(dp_rb), .dp_deinit_rb(dp_deinit_rb), .dp_activated(dp_act),
    .config_status(cfg_h), .active_appsel(active_h),
    .dp_init_pend(dp_pend), .out_status_rx(out_rx), .out_status_tx(out_tx),
    .dp_flag(dp_flag_h), .dp_valid(dp_valid),
    .flag_fail(flag_fail), .flag_los_tx(flag_los_tx),
    .flag_lol_tx(flag_lol_tx), .flag_los_rx(flag_los_rx),
    .flag_lol_rx(flag_lol_rx),
    .flag_alm(flag_alm),
    .ident(ident), .rev(rev), .mod_state(mod_state),
    .int_deasserted(int_deasserted),
    .flag0(flag0), .flag1(flag1), .flag2(flag2), .flag3(flag3),
    .temp_s16(temp_rb), .vcc_u16(vcc_rb),
    .opt_tx_u16(opt_tx_rb), .bias_tx_u16(bias_rb), .opt_rx_u16(opt_rx_rb),
    .scl_oe(scl_oe), .sda_oe(sda_oe), .scl_i(scl_i), .sda_i(sda_i)
  );

  cmis_sfp_slave #(.PWR_DLY(20), .TXDIS_INIT(8'hA0)) mod (
    .clk(clk), .rst_n(rst_n),
    .scl_i(scl_i), .sda_i(sda_i), .sda_oe(sda_slave),
    .lpmode(lpmode), .reset_n(reset_n), .force_fault(force_fault),
    .temp_s16(temp_s16), .vcc_u16(vcc_u16),
    .opt_tx_u16(opt_tx_u16), .bias_tx_u16(bias_tx_u16), .opt_rx_u16(opt_rx_u16),
    .tx_fail(tx_fail), .los_tx(los_tx), .lol_tx(lol_tx),
    .los_rx(los_rx), .lol_rx(lol_rx), .int_n(int_n),
    .mod_state(slave_state), .txdis_byte(txdis_byte), .flag_state(flag_state),
    .dp_state(slave_dp), .dpdeinit_byte(dpdeinit_byte),
    .config_status(cfg_s), .active_appsel(active_s),
    .dp_init_pend(), .out_status_rx(), .out_status_tx(),
    .dp_flag(), .squelch_byte(squelch_byte)
  );

  integer errors = 0;
  integer guard;

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

    tx_disable = 1;
    wait_tx(1'b1, 200000, "tx disable");
    if (txdis_byte !== 8'hA1) begin
      $display("FAIL tx byte %h", txdis_byte);
      errors = errors + 1;
    end
    tx_disable = 0;
    wait_tx(1'b0, 200000, "tx enable");
    if (txdis_byte !== 8'hA0) begin
      $display("FAIL tx restored %h", txdis_byte);
      errors = errors + 1;
    end

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

    begin : dp_up
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (dp_act && dp_rb == CMIS_DP_ACT && slave_dp == CMIS_DP_ACT &&
            dpdeinit_byte == 8'hFE && !dp_deinit_rb && !busy)
          disable dp_up;
      end
      $display("FAIL dp activate host %h slave %h byte %h rb %b act %b",
               dp_rb, slave_dp, dpdeinit_byte, dp_deinit_rb, dp_act);
      errors = errors + 1;
    end

    dp_deinit = 1;
    begin : dp_hold
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (dp_rb == CMIS_DP_DEACT && slave_dp == CMIS_DP_DEACT &&
            dp_deinit_rb && dpdeinit_byte[0] && !dp_act && !busy)
          disable dp_hold;
      end
      $display("FAIL dp deinit host %h slave %h byte %h",
               dp_rb, slave_dp, dpdeinit_byte);
      errors = errors + 1;
    end

    dp_deinit = 0;
    begin : dp_back
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (dp_act && slave_dp == CMIS_DP_ACT && out_tx && out_rx &&
            active_h == CMIS_APP_128 && active_s == CMIS_APP_128 &&
            cfg_h == CMIS_CFG_NONE && squelch_byte == 8'hA0 && dp_valid && !busy)
          disable dp_back;
      end
      $display("FAIL dp default host %h slave %h act %h cfg %h sq %h tx %b rx %b",
               dp_rb, slave_dp, active_h, cfg_h, squelch_byte, out_tx, out_rx);
      errors = errors + 1;
    end
    if (mod.mem[86] !== CMIS_H_128 || mod.mem[87] !== CMIS_M_128 ||
        mod.mem[90] !== CMIS_H_64  || mod.mem[91] !== CMIS_M_64 ||
        mod.mem[94] !== CMIS_H_32  || mod.mem[95] !== CMIS_M_32 ||
        mod.mem[88] !== CMIS_LANES11 || mod.mem[89] !== CMIS_LANE1 ||
        mod.mem[2][6] !== 1'b0) begin
      $display("FAIL app ad %h %h %h %h step %b",
               mod.mem[86], mod.mem[87], mod.mem[90], mod.mem[94], mod.mem[2][6]);
      errors = errors + 1;
    end

    tx_squelch = 1;
    begin : sq_on
      integer k;
      reg saw_flag;
      saw_flag = 0;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (mod.dp_flag)
          saw_flag = 1;
        if (saw_flag && dp_rb == CMIS_DP_INITD && slave_dp == CMIS_DP_INITD &&
            tx_squelch_rb && !out_tx && out_rx && squelch_byte == 8'hA1 && !busy)
          disable sq_on;
      end
      $display("FAIL squelch on st %h byte %h tx %b rx %b flag %b",
               dp_rb, squelch_byte, out_tx, out_rx, saw_flag);
      errors = errors + 1;
    end
    tx_squelch = 0;
    begin : sq_off
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (dp_act && slave_dp == CMIS_DP_ACT && !tx_squelch_rb &&
            out_tx && squelch_byte == 8'hA0 && !busy)
          disable sq_off;
      end
      $display("FAIL squelch off st %h byte %h tx %b", dp_rb, squelch_byte, out_tx);
      errors = errors + 1;
    end

    staged = 8'h20;
    @(negedge clk);
    apply_p = 1;
    @(negedge clk);
    apply_p = 0;
    begin : app_ok
      integer k;
      reg saw_busy, saw_pend, saw_down;
      saw_busy = 0;
      saw_pend = 0;
      saw_down = 0;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (cfg_s == CMIS_CFG_BUSY)
          saw_busy = 1;
        if (mod.dp_init_pend)
          saw_pend = 1;
        if (saw_pend && slave_dp == CMIS_DP_DEACT)
          saw_down = 1;
        if (saw_busy && saw_pend && saw_down && cfg_h == CMIS_CFG_OK &&
            active_h == 8'h20 && active_s == 8'h20 && dp_act &&
            slave_dp == CMIS_DP_ACT && !busy)
          disable app_ok;
      end
      $display("FAIL appsel 64G cfg %h/%h act %h/%h busy %b pend %b down %b dp %h",
               cfg_h, cfg_s, active_h, active_s, saw_busy, saw_pend, saw_down, slave_dp);
      errors = errors + 1;
    end

    staged = 8'h12;
    @(negedge clk);
    apply_p = 1;
    @(negedge clk);
    apply_p = 0;
    begin : app_dp
      integer k;
      reg left;
      left = 0;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (slave_dp != CMIS_DP_ACT && slave_dp != CMIS_DP_TXON &&
            slave_dp != CMIS_DP_TXOFF && slave_dp != CMIS_DP_INITD)
          left = 1;
        if (cfg_h == CMIS_CFG_DP && active_h == 8'h20 && active_s == 8'h20 &&
            dp_act && !left && !busy)
          disable app_dp;
      end
      $display("FAIL bad dpid cfg %h act %h left %b dp %h",
               cfg_h, active_h, left, slave_dp);
      errors = errors + 1;
    end

    staged = 8'h70;
    @(negedge clk);
    apply_p = 1;
    @(negedge clk);
    apply_p = 0;
    begin : app_bad
      integer k;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (cfg_h == CMIS_CFG_APP && active_h == 8'h20 && active_s == 8'h20 &&
            dp_act && !busy)
          disable app_bad;
      end
      $display("FAIL bad appsel cfg %h act %h", cfg_h, active_h);
      errors = errors + 1;
    end

    staged = 8'h11;
    @(negedge clk);
    apply_p = 1;
    @(negedge clk);
    apply_p = 0;
    begin : app_ex
      integer k;
      reg saw_down;
      saw_down = 0;
      for (k = 0; k < 800000; k = k + 1) begin
        @(posedge clk);
        if (slave_dp == CMIS_DP_DEACT)
          saw_down = 1;
        if (saw_down && cfg_h == CMIS_CFG_OK && active_h == 8'h11 &&
            active_s == 8'h11 && dp_act && !busy)
          disable app_ex;
      end
      $display("FAIL explicit cfg %h act %h down %b dp %h",
               cfg_h, active_h, saw_down, slave_dp);
      errors = errors + 1;
    end

    tx_fail = 1;
    los_tx = 1;
    lol_tx = 1;
    los_rx = 1;
    lol_rx = 1;
    begin : fl_set
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (flag_fail && flag_los_tx && flag_lol_tx && flag_los_rx && flag_lol_rx &&
            int_deasserted && int_n && !busy)
          disable fl_set;
      end
      $display("FAIL flags set %b%b%b%b%b int %b pin %b",
               flag_fail, flag_los_tx, flag_lol_tx, flag_los_rx, flag_lol_rx,
               int_deasserted, int_n);
      errors = errors + 1;
    end
    tx_fail = 0;
    los_tx = 0;
    lol_tx = 0;
    los_rx = 0;
    lol_rx = 0;
    begin : fl_clr
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!flag_fail && !flag_los_tx && !flag_lol_tx && !flag_los_rx &&
            !flag_lol_rx && int_deasserted && int_n && !busy)
          disable fl_clr;
      end
      $display("FAIL flags clear %b%b%b%b%b",
               flag_fail, flag_los_tx, flag_lol_tx, flag_los_rx, flag_lol_rx);
      errors = errors + 1;
    end

    @(negedge clk);
    los_tx = 1;
    repeat (8) @(posedge clk);
    @(negedge clk);
    los_tx = 0;
    begin : fl_pulse
      integer k;
      reg saw;
      saw = 0;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (flag_los_tx)
          saw = 1;
        if (saw && !flag_los_tx && int_deasserted && !busy)
          disable fl_pulse;
      end
      $display("FAIL los pulse saw %b flag %b", saw, flag_los_tx);
      errors = errors + 1;
    end

    mask_los_rx = 0;
    begin : mk_rx
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (mod.p10[CMIS_MSK_LOSRX] == 8'hFE &&
            mod.p10[CMIS_MSK_FAIL] == 8'hFF &&
            mod.p10[CMIS_MSK_LOSTX] == 8'hFF &&
            mod.p10[CMIS_MSK_LOLTX] == 8'hFF &&
            mod.p10[CMIS_MSK_LOLRX] == 8'hFF && !busy)
          disable mk_rx;
      end
      $display("FAIL mask rx %h %h", mod.p10[CMIS_MSK_LOSRX], mod.p10[CMIS_MSK_FAIL]);
      errors = errors + 1;
    end
    los_rx = 1;
    begin : fl_int
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (flag_los_rx && !flag_los_tx && !int_deasserted && !int_n && !busy)
          disable fl_int;
      end
      $display("FAIL los int flag %b int %b pin %b", flag_los_rx, int_deasserted, int_n);
      errors = errors + 1;
    end
    los_rx = 0;
    begin : fl_int_clr
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!flag_los_rx && int_deasserted && int_n && !busy)
          disable fl_int_clr;
      end
      $display("FAIL los int clear flag %b int %b pin %b",
               flag_los_rx, int_deasserted, int_n);
      errors = errors + 1;
    end
    mask_los_rx = 1;
    begin : mk_back
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (mod.p10[CMIS_MSK_LOSRX] == 8'hFF && !busy)
          disable mk_back;
      end
      $display("FAIL mask restore %h", mod.p10[CMIS_MSK_LOSRX]);
      errors = errors + 1;
    end

    begin : mon_hold
      integer k;
      reg saw_busy;
      saw_busy = 0;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (busy)
          saw_busy = 1;
        if (saw_busy && !busy && opt_tx_rb == 16'h2710 &&
            bias_rb == 16'h4E20 && opt_rx_rb == 16'h1388)
          disable mon_hold;
      end
      $display("FAIL monitors %h %h %h", opt_tx_rb, bias_rb, opt_rx_rb);
      errors = errors + 1;
    end
    begin : mon_again
      integer k;
      reg saw_busy;
      saw_busy = 0;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (busy)
          saw_busy = 1;
        if (saw_busy && !busy && opt_tx_rb == 16'h2710 &&
            bias_rb == 16'h4E20 && opt_rx_rb == 16'h1388)
          disable mon_again;
      end
      $display("FAIL monitors cleared %h %h %h", opt_tx_rb, bias_rb, opt_rx_rb);
      errors = errors + 1;
    end
    opt_tx_u16 = 16'h00C8;
    bias_tx_u16 = 16'h2710;
    opt_rx_u16 = 16'h0000;
    begin : mon_new
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && opt_tx_rb == 16'h00C8 && bias_rb == 16'h2710 &&
            opt_rx_rb == 16'h0000)
          disable mon_new;
      end
      $display("FAIL monitors update %h %h %h", opt_tx_rb, bias_rb, opt_rx_rb);
      errors = errors + 1;
    end

    // Rx is 0, which is under both low thresholds. Tx and bias stay inside
    // their windows, and the alarm masks still hold IntL high.
    begin : alm_rx0
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag_alm == 12'hA00 && int_deasserted && int_n)
          disable alm_rx0;
      end
      $display("FAIL rx low alarm %h int %b pin %b", flag_alm, int_deasserted, int_n);
      errors = errors + 1;
    end
    opt_tx_u16 = 16'h5000;
    begin : alm_txhi
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag_alm == 12'hA05)
          disable alm_txhi;
      end
      $display("FAIL tx high alarm %h", flag_alm);
      errors = errors + 1;
    end
    opt_tx_u16 = 16'h00C8;
    bias_tx_u16 = 16'h0700;
    begin : alm_bilo
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag_alm == 12'hAA0)
          disable alm_bilo;
      end
      $display("FAIL bias low alarm %h", flag_alm);
      errors = errors + 1;
    end
    bias_tx_u16 = 16'h2710;
    begin : alm_biclr
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag_alm == 12'hA00)
          disable alm_biclr;
      end
      $display("FAIL bias alarm clear %h", flag_alm);
      errors = errors + 1;
    end
    mask_alm = 12'hDFF;
    begin : alm_int
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (mod.p10[CMIS_MSK_RX_LA] == 8'hFE &&
            mod.p10[CMIS_MSK_RX_HA] == 8'hFF &&
            mod.p10[CMIS_MSK_TX_HA] == 8'hFF &&
            mod.p10[CMIS_MSK_LOSRX] == 8'hFF &&
            flag_alm == 12'hA00 && !int_deasserted && !int_n && !busy)
          disable alm_int;
      end
      $display("FAIL alarm int %h mask %h int %b pin %b",
               flag_alm, mod.p10[CMIS_MSK_RX_LA], int_deasserted, int_n);
      errors = errors + 1;
    end
    mask_alm = 12'hFFF;
    begin : alm_mask
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (mod.p10[CMIS_MSK_RX_LA] == 8'hFF && int_deasserted && int_n && !busy)
          disable alm_mask;
      end
      $display("FAIL alarm mask restore %h int %b", mod.p10[CMIS_MSK_RX_LA], int_deasserted);
      errors = errors + 1;
    end

    // Nominal 40.5 C and 3.3 V sit inside the page 02h windows. Byte 9 stays
    // clear, and the mask byte stays FFh, so IntL stays high.
    begin : mon_quiet
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag1 == 8'h00 && mod.mem[CMIS_MSK_MON] == 8'hFF &&
            int_deasserted && int_n)
          disable mon_quiet;
      end
      $display("FAIL module monitors quiet %h mask %h", flag1, mod.mem[CMIS_MSK_MON]);
      errors = errors + 1;
    end
    temp_s16 = 16'h5000;
    begin : mon_thi
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag1 == 8'hA0)
          disable mon_thi;
      end
      $display("FAIL temp high %h", flag1);
      errors = errors + 1;
    end
    // Exactly 75 C is the high-alarm threshold, so only the high warning
    // remains. The high-alarm latch clears on the next read.
    temp_s16 = 16'h4B00;
    begin : mon_teq
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag1 == 8'h20)
          disable mon_teq;
      end
      $display("FAIL temp equal %h", flag1);
      errors = errors + 1;
    end
    temp_s16 = 16'hF000;
    begin : mon_tlo
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag1 == 8'h50)
          disable mon_tlo;
      end
      $display("FAIL temp low %h", flag1);
      errors = errors + 1;
    end
    temp_s16 = 16'hFF00;
    begin : mon_tlw
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag1 == 8'h10)
          disable mon_tlw;
      end
      $display("FAIL temp warning %h", flag1);
      errors = errors + 1;
    end
    temp_s16 = 16'h2880;
    begin : mon_tclr
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag1 == 8'h00)
          disable mon_tclr;
      end
      $display("FAIL temp clear %h", flag1);
      errors = errors + 1;
    end
    vcc_u16 = 16'h9000;
    begin : mon_vhi
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag1 == 8'h0A)
          disable mon_vhi;
      end
      $display("FAIL vcc high %h", flag1);
      errors = errors + 1;
    end
    vcc_u16 = 16'h8CA0;
    begin : mon_veq
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag1 == 8'h02)
          disable mon_veq;
      end
      $display("FAIL vcc equal %h", flag1);
      errors = errors + 1;
    end
    vcc_u16 = 16'h7000;
    begin : mon_vlo
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag1 == 8'h05)
          disable mon_vlo;
      end
      $display("FAIL vcc low %h", flag1);
      errors = errors + 1;
    end
    mask_mon = 8'hFE;
    begin : mon_int
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag1 == 8'h05 && mod.mem[CMIS_MSK_MON] == 8'hFE &&
            !int_deasserted && !int_n)
          disable mon_int;
      end
      $display("FAIL vcc int %h mask %h int %b pin %b",
               flag1, mod.mem[CMIS_MSK_MON], int_deasserted, int_n);
      errors = errors + 1;
    end
    mask_mon = 8'hFF;
    vcc_u16 = 16'h80E8;
    begin : mon_done
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag1 == 8'h00 && mod.mem[CMIS_MSK_MON] == 8'hFF &&
            int_deasserted && int_n)
          disable mon_done;
      end
      $display("FAIL module monitor restore %h mask %h int %b",
               flag1, mod.mem[CMIS_MSK_MON], int_deasserted);
      errors = errors + 1;
    end

    if (errors == 0)
      $display("PASS tb_fc_cmis");
    else
      $display("FAIL tb_fc_cmis errors=%0d", errors);
    $finish;
  end

  initial begin
    for (guard = 0; guard < 12000000; guard = guard + 1)
      @(posedge clk);
    $display("FAIL tb_fc_cmis timeout");
    $finish;
  end
endmodule
