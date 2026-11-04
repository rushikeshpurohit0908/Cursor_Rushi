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
  logic mask_sc = 1;
  logic [7:0] mask_aux = 8'hFF;
  logic [7:0] mask_a3 = 8'hFF;
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
  logic [15:0] aux1_s16 = 16'd12800;
  logic [15:0] aux2_s16 = 16'd3277;
  logic [15:0] aux3_s16 = 16'd18000;
  logic [15:0] cust_s16 = 16'd250;

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
  logic [15:0] aux1_rb, aux2_rb, aux3_rb, cust_rb;
  logic [127:0] vname, vpn;
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
    .mask_sc(mask_sc),
    .mask_aux(mask_aux),
    .mask_a3(mask_a3),
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
    .aux1_s16(aux1_rb), .aux2_s16(aux2_rb),
    .aux3_s16(aux3_rb), .cust_s16(cust_rb),
    .vendor_name(vname), .vendor_pn(vpn),
    .scl_oe(scl_oe), .sda_oe(sda_oe), .scl_i(scl_i), .sda_i(sda_i)
  );

  cmis_sfp_slave #(.PWR_DLY(20), .TXDIS_INIT(8'hA0)) mod (
    .clk(clk), .rst_n(rst_n),
    .scl_i(scl_i), .sda_i(sda_i), .sda_oe(sda_slave),
    .lpmode(lpmode), .reset_n(reset_n), .force_fault(force_fault),
    .temp_s16(temp_s16), .vcc_u16(vcc_u16),
    .opt_tx_u16(opt_tx_u16), .bias_tx_u16(bias_tx_u16), .opt_rx_u16(opt_rx_u16),
    .aux1_s16(aux1_s16), .aux2_s16(aux2_s16),
    .aux3_s16(aux3_s16), .cust_s16(cust_s16),
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
        if (!present && !scl_oe && !sda_oe && vname == 128'h0 && vpn == 128'h0)
          disable abs_watch;
      end
      $display("FAIL absent present %b oe %b%b name %h pn %h",
               present, scl_oe, sda_oe, vname, vpn);
      errors = errors + 1;
    end
    mod_prs_n = 0;
    wait_state(CMIS_ST_RDY, 200000, "inserted");
    if (vname !== CMIS_VENDOR_NAME || vpn !== CMIS_VENDOR_PN) begin
      $display("FAIL vendor reinsert name %h pn %h", vname, vpn);
      errors = errors + 1;
    end

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

    // ModuleStateChangedFlag is byte 8 bit 0. It latches the entry into
    // ModuleLowPwr, ModuleReady, or ModuleFault, then clears on read. Power-up
    // and power-down do not latch it. Byte 31 bit 0 is the mask.
    begin : sc_quiet
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && present && mod_state == CMIS_ST_RDY &&
            flag0 == 8'h00 && !flag_state && int_deasserted && int_n &&
            mod.mem[CMIS_MSK_SC] == 8'hFF)
          disable sc_quiet;
      end
      $display("FAIL state flag idle %h pin %b mask %h",
               flag0, int_n, mod.mem[CMIS_MSK_SC]);
      errors = errors + 1;
    end
    mask_sc = 0;
    begin : sc_unmask
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && mod.mem[CMIS_MSK_SC] == 8'hFE && int_deasserted && int_n)
          disable sc_unmask;
      end
      $display("FAIL state mask %h int %b", mod.mem[CMIS_MSK_SC], int_n);
      errors = errors + 1;
    end
    low_pwr_sw = 1;
    begin : sc_down
      integer k;
      reg saw_dn, bad_dn, saw_pin, saw_low;
      saw_dn = 0;
      bad_dn = 0;
      saw_pin = 0;
      saw_low = 0;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (mod.mod_state_q == CMIS_ST_DN) begin
          saw_dn = 1;
          if (flag_state)
            bad_dn = 1;
        end
        // The pin falls while the latch is set. The poll that reports it
        // also reads byte 8, so the pin is high again by the next idle.
        if (mod.mod_state_q == CMIS_ST_LOW && flag_state && !int_n)
          saw_pin = 1;
        if (saw_dn && !bad_dn && saw_pin && !busy && mod_state == CMIS_ST_LOW &&
            flag0[0] && !int_deasserted)
          saw_low = 1;
        if (saw_low)
          disable sc_down;
      end
      $display("FAIL state down dn %b bad %b low %b flag %h int %b",
               saw_dn, bad_dn, saw_low, flag0, int_n);
      errors = errors + 1;
    end
    begin : sc_low_clr
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && mod_state == CMIS_ST_LOW && flag0 == 8'h00 &&
            !flag_state && int_deasserted && int_n)
          disable sc_low_clr;
      end
      $display("FAIL state low clear %h pin %b", flag0, int_n);
      errors = errors + 1;
    end
    low_pwr_sw = 0;
    begin : sc_up
      integer k;
      reg saw_up, bad_up, saw_pin, saw_rdy;
      saw_up = 0;
      bad_up = 0;
      saw_pin = 0;
      saw_rdy = 0;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (mod.mod_state_q == CMIS_ST_UP && !flag_state)
          saw_up = 1;
        if (mod.mod_state_q == CMIS_ST_UP && flag_state)
          bad_up = 1;
        if (mod.mod_state_q == CMIS_ST_RDY && flag_state && !int_n)
          saw_pin = 1;
        if (saw_up && !bad_up && saw_pin && !busy && mod_state == CMIS_ST_RDY &&
            flag0[0] && !int_deasserted)
          saw_rdy = 1;
        if (saw_rdy)
          disable sc_up;
      end
      $display("FAIL state up up %b bad %b rdy %b flag %h int %b",
               saw_up, bad_up, saw_rdy, flag0, int_n);
      errors = errors + 1;
    end
    begin : sc_rdy_clr
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && mod_state == CMIS_ST_RDY && flag0 == 8'h00 &&
            !flag_state && int_deasserted && int_n)
          disable sc_rdy_clr;
      end
      $display("FAIL state ready clear %h", flag0);
      errors = errors + 1;
    end
    // A software reset with LowPwrS already false skips the LowPwr flag.
    begin : sc_sw
      integer k;
      reg bad_low, saw_pin, saw_rdy;
      bad_low = 0;
      saw_pin = 0;
      saw_rdy = 0;
      @(negedge clk);
      sw_pulse = 1;
      @(negedge clk);
      sw_pulse = 0;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (mod.mod_state_q == CMIS_ST_LOW && flag_state)
          bad_low = 1;
        if (mod.mod_state_q == CMIS_ST_UP && flag_state)
          bad_low = 1;
        if (mod.mod_state_q == CMIS_ST_RDY && flag_state && !int_n)
          saw_pin = 1;
        if (!bad_low && saw_pin && !busy && mod_state == CMIS_ST_RDY &&
            flag0[0] && !int_deasserted)
          saw_rdy = 1;
        if (saw_rdy)
          disable sc_sw;
      end
      $display("FAIL state sw bad %b rdy %b flag %h", bad_low, saw_rdy, flag0);
      errors = errors + 1;
    end
    begin : sc_sw_clr
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && mod_state == CMIS_ST_RDY && flag0 == 8'h00 && !flag_state)
          disable sc_sw_clr;
      end
      $display("FAIL state sw clear %h", flag0);
      errors = errors + 1;
    end
    mask_sc = 1;
    begin : sc_remask
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && mod_state == CMIS_ST_RDY && flag0 == 8'h00 &&
            mod.mem[CMIS_MSK_SC] == 8'hFF && int_deasserted && int_n)
          disable sc_remask;
      end
      $display("FAIL state remask %h", mod.mem[CMIS_MSK_SC]);
      errors = errors + 1;
    end
    force_fault = 1;
    begin : sc_fault
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && mod_state == CMIS_ST_FLT && flag0[0] &&
            int_deasserted && int_n && mod.mem[CMIS_MSK_SC][0])
          disable sc_fault;
      end
      $display("FAIL state fault flag %h mask %h int %b",
               flag0, mod.mem[CMIS_MSK_SC], int_n);
      errors = errors + 1;
    end
    begin : sc_fault_clr
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && mod_state == CMIS_ST_FLT && flag0 == 8'h00 &&
            !flag_state && int_deasserted && int_n)
          disable sc_fault_clr;
      end
      $display("FAIL state fault held %h", flag0);
      errors = errors + 1;
    end
    force_fault = 0;
    mask_sc = 1;
    begin : sc_done
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && mod_state == CMIS_ST_RDY && flag0 == 8'h00 &&
            mod.mem[CMIS_MSK_SC] == 8'hFF && int_deasserted && int_n)
          disable sc_done;
      end
      $display("FAIL state restore %h mask %h state %0d",
               flag0, mod.mem[CMIS_MSK_SC], mod_state);
      errors = errors + 1;
    end

    // Aux1 is laser temperature (signed 1/256 C) and Aux2 is TEC current
    // (signed 100/32767 percent). Byte 10 is clear-on-read. A negative TEC
    // reading must not set a high alarm. Byte 33 is the whole-byte mask.
    begin : aux_quiet
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag2 == 8'h00 && aux1_rb == 16'd12800 &&
            aux2_rb == 16'd3277 && int_deasserted && int_n &&
            mod.mem[CMIS_MSK_AUX] == 8'hFF)
          disable aux_quiet;
      end
      $display("FAIL aux quiet flags %h aux %h %h mask %h",
               flag2, aux1_rb, aux2_rb, mod.mem[CMIS_MSK_AUX]);
      errors = errors + 1;
    end
    aux1_s16 = CMIS_AUX1_HA + 16'sd1;
    begin : aux_thi
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag2 == 8'hA0 && aux1_rb == aux1_s16 &&
            int_deasserted && int_n)
          disable aux_thi;
      end
      $display("FAIL aux temp high %h aux %h", flag2, aux1_rb);
      errors = errors + 1;
    end
    aux1_s16 = CMIS_AUX1_HA;
    begin : aux_teq
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag2 == 8'h20 && aux1_rb == CMIS_AUX1_HA)
          disable aux_teq;
      end
      $display("FAIL aux temp equal %h aux %h", flag2, aux1_rb);
      errors = errors + 1;
    end
    aux1_s16 = CMIS_AUX1_LA - 16'sd1;
    begin : aux_tlo
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag2 == 8'h50 && aux1_rb == aux1_s16)
          disable aux_tlo;
      end
      $display("FAIL aux temp low %h aux %h", flag2, aux1_rb);
      errors = errors + 1;
    end
    aux1_s16 = CMIS_AUX1_LA;
    begin : aux_tlw
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag2 == 8'h10 && aux1_rb == CMIS_AUX1_LA)
          disable aux_tlw;
      end
      $display("FAIL aux temp warning %h aux %h", flag2, aux1_rb);
      errors = errors + 1;
    end
    aux1_s16 = 16'd12800;
    begin : aux_tclr
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag2 == 8'h00 && aux1_rb == 16'd12800)
          disable aux_tclr;
      end
      $display("FAIL aux temp clear %h aux %h", flag2, aux1_rb);
      errors = errors + 1;
    end
    aux2_s16 = CMIS_AUX2_HA + 16'sd1;
    begin : aux_chi
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag2 == 8'h0A && aux2_rb == aux2_s16)
          disable aux_chi;
      end
      $display("FAIL aux tec high %h aux %h", flag2, aux2_rb);
      errors = errors + 1;
    end
    aux2_s16 = CMIS_AUX2_HA;
    begin : aux_ceq
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag2 == 8'h02 && aux2_rb == CMIS_AUX2_HA)
          disable aux_ceq;
      end
      $display("FAIL aux tec equal %h aux %h", flag2, aux2_rb);
      errors = errors + 1;
    end
    aux2_s16 = -16'sd3277;
    begin : aux_cneg
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag2 == 8'h00 && aux2_rb == aux2_s16)
          disable aux_cneg;
      end
      $display("FAIL aux tec negative %h aux %h", flag2, aux2_rb);
      errors = errors + 1;
    end
    aux2_s16 = CMIS_AUX2_LA - 16'sd1;
    begin : aux_clo
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag2 == 8'h05 && aux2_rb == aux2_s16 &&
            int_deasserted && int_n)
          disable aux_clo;
      end
      $display("FAIL aux tec low %h aux %h int %b", flag2, aux2_rb, int_n);
      errors = errors + 1;
    end
    mask_aux = 8'hFE;
    begin : aux_int
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag2 == 8'h05 && mod.mem[CMIS_MSK_AUX] == 8'hFE &&
            !int_deasserted && !int_n)
          disable aux_int;
      end
      $display("FAIL aux int %h mask %h int %b pin %b",
               flag2, mod.mem[CMIS_MSK_AUX], int_deasserted, int_n);
      errors = errors + 1;
    end
    mask_aux = 8'hFF;
    aux2_s16 = 16'd3277;
    begin : aux_done
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag2 == 8'h00 && aux1_rb == 16'd12800 &&
            aux2_rb == 16'd3277 && mod.mem[CMIS_MSK_AUX] == 8'hFF &&
            mod.mem[CMIS_MSK_MON] == 8'hFF && mod.mem[CMIS_MSK_SC] == 8'hFF &&
            int_deasserted && int_n)
          disable aux_done;
      end
      $display("FAIL aux restore flags %h aux %h %h mask %h",
               flag2, aux1_rb, aux2_rb, mod.mem[CMIS_MSK_AUX]);
      errors = errors + 1;
    end

    // Aux3 is Vcc2 (signed 100 uV) and Custom is laser frequency error
    // (signed 1 MHz). Byte 11 is clear-on-read. A negative reading must
    // not set a high alarm. Byte 34 is the whole-byte mask.
    begin : a3_quiet
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag3 == 8'h00 && aux3_rb == 16'd18000 &&
            cust_rb == 16'd250 && int_deasserted && int_n &&
            mod.mem[CMIS_MSK_A3] == 8'hFF)
          disable a3_quiet;
      end
      $display("FAIL aux3 quiet flags %h aux %h %h mask %h",
               flag3, aux3_rb, cust_rb, mod.mem[CMIS_MSK_A3]);
      errors = errors + 1;
    end
    aux3_s16 = CMIS_AUX3_HA + 16'sd1;
    begin : a3_vhi
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag3 == 8'hA0 && aux3_rb == aux3_s16 &&
            int_deasserted && int_n)
          disable a3_vhi;
      end
      $display("FAIL aux3 vcc high %h aux %h", flag3, aux3_rb);
      errors = errors + 1;
    end
    aux3_s16 = CMIS_AUX3_HA;
    begin : a3_veq
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag3 == 8'h20 && aux3_rb == CMIS_AUX3_HA)
          disable a3_veq;
      end
      $display("FAIL aux3 vcc equal %h aux %h", flag3, aux3_rb);
      errors = errors + 1;
    end
    aux3_s16 = CMIS_AUX3_LA - 16'sd1;
    begin : a3_vlo
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag3 == 8'h50 && aux3_rb == aux3_s16)
          disable a3_vlo;
      end
      $display("FAIL aux3 vcc low %h aux %h", flag3, aux3_rb);
      errors = errors + 1;
    end
    aux3_s16 = CMIS_AUX3_LA;
    begin : a3_vlw
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag3 == 8'h10 && aux3_rb == CMIS_AUX3_LA)
          disable a3_vlw;
      end
      $display("FAIL aux3 vcc warning %h aux %h", flag3, aux3_rb);
      errors = errors + 1;
    end
    aux3_s16 = -16'sd100;
    begin : a3_vneg
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag3 == 8'h50 && aux3_rb == aux3_s16 && !flag3[7])
          disable a3_vneg;
      end
      $display("FAIL aux3 vcc negative %h aux %h", flag3, aux3_rb);
      errors = errors + 1;
    end
    aux3_s16 = 16'd18000;
    begin : a3_vclr
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag3 == 8'h00 && aux3_rb == 16'd18000)
          disable a3_vclr;
      end
      $display("FAIL aux3 vcc clear %h aux %h", flag3, aux3_rb);
      errors = errors + 1;
    end
    cust_s16 = CMIS_CUST_HA + 16'sd1;
    begin : a3_fhi
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag3 == 8'h0A && cust_rb == cust_s16)
          disable a3_fhi;
      end
      $display("FAIL aux3 freq high %h aux %h", flag3, cust_rb);
      errors = errors + 1;
    end
    cust_s16 = CMIS_CUST_HA;
    begin : a3_feq
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag3 == 8'h02 && cust_rb == CMIS_CUST_HA)
          disable a3_feq;
      end
      $display("FAIL aux3 freq equal %h aux %h", flag3, cust_rb);
      errors = errors + 1;
    end
    cust_s16 = -16'sd250;
    begin : a3_fneg
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag3 == 8'h00 && cust_rb == cust_s16)
          disable a3_fneg;
      end
      $display("FAIL aux3 freq negative %h aux %h", flag3, cust_rb);
      errors = errors + 1;
    end
    cust_s16 = CMIS_CUST_LA - 16'sd1;
    begin : a3_flo
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag3 == 8'h05 && cust_rb == cust_s16 &&
            int_deasserted && int_n)
          disable a3_flo;
      end
      $display("FAIL aux3 freq low %h aux %h int %b", flag3, cust_rb, int_n);
      errors = errors + 1;
    end
    mask_a3 = 8'hFE;
    begin : a3_int
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag3 == 8'h05 && mod.mem[CMIS_MSK_A3] == 8'hFE &&
            !int_deasserted && !int_n)
          disable a3_int;
      end
      $display("FAIL aux3 int %h mask %h int %b pin %b",
               flag3, mod.mem[CMIS_MSK_A3], int_deasserted, int_n);
      errors = errors + 1;
    end
    mask_a3 = 8'hFF;
    cust_s16 = 16'd250;
    begin : a3_done
      integer k;
      for (k = 0; k < 400000; k = k + 1) begin
        @(posedge clk);
        if (!busy && flag3 == 8'h00 && flag2 == 8'h00 &&
            aux3_rb == 16'd18000 && cust_rb == 16'd250 &&
            mod.mem[CMIS_MSK_A3] == 8'hFF && mod.mem[CMIS_MSK_AUX] == 8'hFF &&
            mod.mem[CMIS_MSK_MON] == 8'hFF && mod.mem[CMIS_MSK_SC] == 8'hFF &&
            int_deasserted && int_n)
          disable a3_done;
      end
      $display("FAIL aux3 restore flags %h aux %h %h mask %h",
               flag3, aux3_rb, cust_rb, mod.mem[CMIS_MSK_A3]);
      errors = errors + 1;
    end

    begin : vend_live
      integer k;
      for (k = 0; k < 200000; k = k + 1) begin
        @(posedge clk);
        if (!busy && present && vname == CMIS_VENDOR_NAME &&
            vpn == CMIS_VENDOR_PN && mod.mem[CMIS_PAGE] != CMIS_VEND_PAGE)
          disable vend_live;
      end
      $display("FAIL vendor live name %h pn %h page %h",
               vname, vpn, mod.mem[CMIS_PAGE]);
      errors = errors + 1;
    end
    // A write into the page 00h window must not replace the advertised string.
    begin
      reg [7:0] saved_page;
      reg [7:0] saved_mem;
      reg [7:0] saved_p10;
      saved_page = mod.mem[CMIS_PAGE];
      saved_mem = mod.mem[CMIS_VNAME];
      saved_p10 = mod.p10[CMIS_VNAME];
      mod.mem[CMIS_PAGE] = CMIS_VEND_PAGE;
      mod.mem[CMIS_VNAME] = 8'h58;
      mod.p10[CMIS_VNAME] = 8'h58;
      if (mod.peek(CMIS_VNAME) !== 8'h41 || mod.peek(CMIS_VPN) !== 8'h53) begin
        $display("FAIL vendor write stuck %h %h",
                 mod.peek(CMIS_VNAME), mod.peek(CMIS_VPN));
        errors = errors + 1;
      end
      mod.mem[CMIS_VNAME] = saved_mem;
      mod.p10[CMIS_VNAME] = saved_p10;
      mod.mem[CMIS_PAGE] = saved_page;
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
