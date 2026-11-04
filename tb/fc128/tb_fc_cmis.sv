`timescale 1ns/1ps
// CMIS 5.0 host against a behavioral SFP112: power-up, low power, software
// reset, lane-1 OutputDisableTx, the data path, forced squelch, staged
// AppSel, module fault, and an absent module.
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
  logic mod_prs_n = 0;
  logic lpmode = 0;
  logic reset_n = 1;
  logic force_fault = 0;
  logic [15:0] temp_s16 = 16'h2880;
  logic [15:0] vcc_u16 = 16'h80E8;

  logic busy, present, nack, armed, low_pwr_rb, tx_disable_rb, tx_squelch_rb;
  logic dp_deinit_rb, dp_act, dp_pend, out_rx, out_tx, dp_flag_h, dp_valid;
  logic [7:0] ident, rev, flag0, flag1, flag2, flag3, txdis_byte, dpdeinit_byte;
  logic [7:0] active_h, active_s, squelch_byte;
  logic [3:0] dp_rb, slave_dp, cfg_h, cfg_s;
  logic [2:0] mod_state, slave_state;
  logic int_deasserted, flag_state;
  logic [15:0] temp_rb, vcc_rb;
  logic scl_oe, sda_oe, sda_slave;
  wire scl_i = ~scl_oe;
  wire sda_i = ~(sda_oe | sda_slave);

  fc_cmis_host #(.DIV(4), .GAP(8)) host (
    .clk(clk), .rst_n(rst_n),
    .poll_en(poll_en), .low_pwr_sw(low_pwr_sw),
    .sw_reset_pulse(sw_pulse), .tx_disable(tx_disable),
    .tx_squelch(tx_squelch), .dp_deinit(dp_deinit),
    .staged_appsel(staged), .apply_pulse(apply_p),
    .mod_prs_n(mod_prs_n),
    .busy(busy), .present(present), .nack(nack), .armed(armed),
    .low_pwr_rb(low_pwr_rb), .tx_disable_rb(tx_disable_rb),
    .tx_squelch_rb(tx_squelch_rb),
    .dp_state(dp_rb), .dp_deinit_rb(dp_deinit_rb), .dp_activated(dp_act),
    .config_status(cfg_h), .active_appsel(active_h),
    .dp_init_pend(dp_pend), .out_status_rx(out_rx), .out_status_tx(out_tx),
    .dp_flag(dp_flag_h), .dp_valid(dp_valid),
    .ident(ident), .rev(rev), .mod_state(mod_state),
    .int_deasserted(int_deasserted),
    .flag0(flag0), .flag1(flag1), .flag2(flag2), .flag3(flag3),
    .temp_s16(temp_rb), .vcc_u16(vcc_rb),
    .scl_oe(scl_oe), .sda_oe(sda_oe), .scl_i(scl_i), .sda_i(sda_i)
  );

  cmis_sfp_slave #(.PWR_DLY(20), .TXDIS_INIT(8'hA0)) mod (
    .clk(clk), .rst_n(rst_n),
    .scl_i(scl_i), .sda_i(sda_i), .sda_oe(sda_slave),
    .lpmode(lpmode), .reset_n(reset_n), .force_fault(force_fault),
    .temp_s16(temp_s16), .vcc_u16(vcc_u16),
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
