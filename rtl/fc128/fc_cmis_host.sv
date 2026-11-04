// CMIS host for one SFP112 cage.
//
// The two-wire interface is the CMIS management interface (7-bit address
// 0x50). While poll_en is set and ModPrsL is low, the host does three things
// in order:
//   * read-modify-write lower byte 26 so LowPwrRequestSW follows low_pwr_sw
//     and a SoftwareReset pulse is a single write of bit 3. Bits 6 and 5
//     (LowPwrAllowRequestHW, SquelchMethodSelect) are left as the module
//     set them.
//   * select page 10h and read-modify-write byte 130 bit 0, OutputDisableTx
//     for lane 1, then byte 132 bit 0, OutputSquelchForceTx. Other bits in
//     those bytes are preserved.
//   * on that same page, read-modify-write byte 128 bit 0 (DPDeinit for
//     lane 1). Clearing it lets a ModuleReady module bring the data path up.
//   * write page 10h byte 145 when the staged AppSel byte changes, then a
//     one-byte write of bit 0 at byte 143 when apply_pulse is set. Byte 143
//     is write-only.
//   * select page 11h and read the lane 1 data path state, output status,
//     ConfigStatus, the active AppSel, and DPInitPending. The same pass
//     reads the clear-on-read lane flags: Tx failure, Tx LOS, Tx CDR LOL,
//     Rx LOS, and Rx CDR LOL. Bytes 139-146 and 149-152 are the lane-1
//     optical and laser alarm/warning flags, also clear-on-read. It also
//     reads the lane-1 monitors: OpticalPowerTx at bytes 154-155,
//     LaserBiasTx at bytes 170-171, and OpticalPowerRx at bytes 186-187.
//     Those three are live values, not clear-on-read latches.
//   * on page 10h, read-modify-write bit 0 of the lane-flag masks so an
//     unmasked flag can assert the module interrupt. Bits [7:1] of each
//     mask byte stay as the module set them. The five link flags use bytes
//     214, 215, 216, 226, and 227. The twelve alarm flags use bytes 218-225
//     and 228-231. Lower byte 32 is the module temperature and supply mask.
//     The host writes that whole byte from mask_mon. Byte 9, captured with
//     the lower-memory poll, is the eight clear-on-read flags. Lower byte 31
//     bit 0 is ModuleStateChangedMask. The host read-modify-writes that bit
//     from mask_sc and leaves bits [7:1] as the module set them. Byte 8 bit 0,
//     captured with the same lower-memory poll, is ModuleStateChangedFlag.
//     Lower byte 33 is the Aux1/Aux2 mask. The host writes that whole byte
//     from mask_aux after the byte 32 mask and before the status pass.
//     Byte 10, captured with the lower-memory poll, is the eight Aux flags.
//     Lower byte 34 is the Aux3/Custom mask. The host writes that whole byte
//     from mask_a3 after the byte 33 mask and before the status pass.
//     Byte 11, captured with the same lower-memory poll, is the eight
//     Aux3 and Custom flags.
//   * after the page 11h Rx-power flags, read lower bytes 18-21, then
//     bytes 22-25. Those are Aux1Mon, Aux2Mon, Aux3Mon, and CustomMon.
//     The bytes 128-134 read is left as it is, and the lower-memory poll
//     stays bytes 0-17.
//   * read lower bytes 0 through 17 and publish identifier, revision, module
//     state, flags, temperature, and supply.
//
// LPMode and ResetL are cage pins driven by the bridge CSR, not by this
// state machine. A NACK, or ModPrsL high, drops present and the next poll
// repeats the control writes.
module fc_cmis_host #(
  parameter int DIV = 4,
  parameter int GAP = 32
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        poll_en,
  input  logic        low_pwr_sw,
  input  logic        sw_reset_pulse,
  input  logic        tx_disable,
  input  logic        tx_squelch,
  input  logic        dp_deinit,
  input  logic [7:0]  staged_appsel,
  input  logic        apply_pulse,
  input  logic        mask_fail,
  input  logic        mask_los_tx,
  input  logic        mask_lol_tx,
  input  logic        mask_los_rx,
  input  logic        mask_lol_rx,
  input  logic [11:0] mask_alm,
  input  logic [7:0]  mask_mon,
  input  logic        mask_sc,
  input  logic [7:0]  mask_aux,
  input  logic [7:0]  mask_a3,
  input  logic        mod_prs_n,

  output logic        busy,
  output logic        present,
  output logic        nack,
  output logic        armed,
  output logic        low_pwr_rb,
  output logic        tx_disable_rb,
  output logic        tx_squelch_rb,
  output logic [3:0]  dp_state,
  output logic        dp_deinit_rb,
  output logic        dp_activated,
  output logic [3:0]  config_status,
  output logic [7:0]  active_appsel,
  output logic        dp_init_pend,
  output logic        out_status_rx,
  output logic        out_status_tx,
  output logic        dp_flag,
  output logic        dp_valid,
  output logic        flag_fail,
  output logic        flag_los_tx,
  output logic        flag_lol_tx,
  output logic        flag_los_rx,
  output logic        flag_lol_rx,
  output logic [11:0] flag_alm,
  output logic [7:0]  ident,
  output logic [7:0]  rev,
  output logic [2:0]  mod_state,
  output logic        int_deasserted,
  output logic [7:0]  flag0,
  output logic [7:0]  flag1,
  output logic [7:0]  flag2,
  output logic [7:0]  flag3,
  output logic [15:0] temp_s16,
  output logic [15:0] vcc_u16,
  output logic [15:0] opt_tx_u16,
  output logic [15:0] bias_tx_u16,
  output logic [15:0] opt_rx_u16,
  output logic [15:0] aux1_s16,
  output logic [15:0] aux2_s16,
  output logic [15:0] aux3_s16,
  output logic [15:0] cust_s16,

  output logic        scl_oe,
  output logic        sda_oe,
  input  logic        scl_i,
  input  logic        sda_i
);
  `include "fc_cmis.vh"

  localparam int GAPW = (GAP < 1) ? 1 : GAP;
  localparam [4:0] OP_RD26   = 5'd0;
  localparam [4:0] OP_WR26   = 5'd1;
  localparam [4:0] OP_PG     = 5'd2;
  localparam [4:0] OP_RD130  = 5'd3;
  localparam [4:0] OP_WR130  = 5'd4;
  localparam [4:0] OP_POLL   = 5'd5;
  localparam [4:0] OP_DP_PG  = 5'd6;
  localparam [4:0] OP_DP_RD  = 5'd7;
  localparam [4:0] OP_DP_WR  = 5'd8;
  localparam [4:0] OP_ST_PG  = 5'd9;
  localparam [4:0] OP_ST_RD  = 5'd10;
  localparam [4:0] OP_SQ_PG  = 5'd11;
  localparam [4:0] OP_SQ_RD  = 5'd12;
  localparam [4:0] OP_SQ_WR  = 5'd13;
  localparam [4:0] OP_AS_PG  = 5'd14;
  localparam [4:0] OP_AS_RD  = 5'd15;
  localparam [4:0] OP_AS_WR  = 5'd16;
  localparam [4:0] OP_AP_PG  = 5'd17;
  localparam [4:0] OP_AP_WR  = 5'd18;
  localparam [4:0] OP_ST_OUT = 5'd19;
  localparam [4:0] OP_ST_CFG = 5'd20;
  localparam [4:0] OP_ST_PND = 5'd21;
  localparam [4:0] OP_MK_PG  = 5'd22;
  localparam [4:0] OP_MK_RD  = 5'd23;
  localparam [4:0] OP_MK_WR  = 5'd24;
  localparam [4:0] OP_FL_TX  = 5'd25;
  localparam [4:0] OP_FL_RX  = 5'd26;
  localparam [4:0] OP_MON_TX = 5'd27;
  localparam [4:0] OP_MON_BI = 5'd28;
  localparam [4:0] OP_MON_RX = 5'd29;
  localparam [4:0] OP_AL_TX  = 5'd30;
  localparam [4:0] OP_AL_RX  = 5'd31;
  localparam [5:0] OP_MM_RD  = 6'd32;
  localparam [5:0] OP_MM_WR  = 6'd33;
  localparam [5:0] OP_SC_RD  = 6'd34;
  localparam [5:0] OP_SC_WR  = 6'd35;
  localparam [5:0] OP_AX_RD  = 6'd36;
  localparam [5:0] OP_AX_WR  = 6'd37;
  localparam [5:0] OP_AUX    = 6'd38;
  localparam [5:0] OP_A3_RD  = 6'd39;
  localparam [5:0] OP_A3_WR  = 6'd40;
  localparam [5:0] OP_A3     = 6'd41;
  localparam [4:0] MK_LAST   = 5'd16;

  logic        cmd_valid, cmd_ready, cmd_write, cmd_done, cmd_nack;
  logic [7:0]  cmd_addr, cmd_wdata, rx_data;
  logic [5:0]  cmd_rlen;
  logic        rx_valid;
  logic [4:0]  rx_index;
  logic [7:0]  cap [0:31];
  logic [5:0]  op;
  logic        launch, inflight, wait_gap;
  logic        ctrl_ok, tx_ok, sq_ok, dp_ok, as_ok, st_fresh, sw_pend, ap_pend;
  logic        mk_ok, mm_ok, sc_ok, ax_ok, a3_ok;
  logic [7:0]  mm_rb, mm_snap;
  logic        sc_rb, sc_snap;
  logic [7:0]  ax_rb, ax_snap;
  logic [7:0]  a3_rb, a3_snap;
  logic [7:0]  as_rb;
  logic [4:0]  mk_i;
  logic [16:0] mk_snap;
  logic        mk_fail_rb, mk_los_tx_rb, mk_lol_tx_rb, mk_los_rx_rb, mk_lol_rx_rb;
  logic [11:0] mk_alm_rb;
  logic [15:0] gapcnt;

  fc_i2c_master #(.DIV(DIV), .DEV(CMIS_DEV)) u_i2c (
    .clk(clk), .rst_n(rst_n),
    .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
    .cmd_write(cmd_write), .cmd_addr(cmd_addr),
    .cmd_wdata(cmd_wdata), .cmd_rlen(cmd_rlen),
    .cmd_done(cmd_done), .cmd_nack(cmd_nack),
    .rx_data(rx_data), .rx_valid(rx_valid), .rx_index(rx_index),
    .scl_oe(scl_oe), .sda_oe(sda_oe), .scl_i(scl_i), .sda_i(sda_i)
  );

  function automatic [7:0] merge_ctl(input [7:0] old, input logic lp, input logic rstb);
    begin
      // Keep bits [7:5] and [2:0]. Replace LowPwrRequestSW and SoftwareReset.
      merge_ctl = (old & 8'hE7) | (lp ? 8'h10 : 8'h00) | (rstb ? 8'h08 : 8'h00);
    end
  endfunction

  function automatic [7:0] merge_bit0(input [7:0] old, input logic bit0);
    begin
      merge_bit0 = (old & 8'hFE) | (bit0 ? 8'h01 : 8'h00);
    end
  endfunction

  function automatic [7:0] mask_addr(input [4:0] idx);
    begin
      case (idx)
        5'd0:  mask_addr = CMIS_MSK_FAIL;
        5'd1:  mask_addr = CMIS_MSK_LOSTX;
        5'd2:  mask_addr = CMIS_MSK_LOLTX;
        5'd3:  mask_addr = CMIS_MSK_LOSRX;
        5'd4:  mask_addr = CMIS_MSK_LOLRX;
        5'd5:  mask_addr = CMIS_MSK_TX_HA;
        5'd6:  mask_addr = CMIS_MSK_TX_LA;
        5'd7:  mask_addr = CMIS_MSK_TX_HW;
        5'd8:  mask_addr = CMIS_MSK_TX_LW;
        5'd9:  mask_addr = CMIS_MSK_BI_HA;
        5'd10: mask_addr = CMIS_MSK_BI_LA;
        5'd11: mask_addr = CMIS_MSK_BI_HW;
        5'd12: mask_addr = CMIS_MSK_BI_LW;
        5'd13: mask_addr = CMIS_MSK_RX_HA;
        5'd14: mask_addr = CMIS_MSK_RX_LA;
        5'd15: mask_addr = CMIS_MSK_RX_HW;
        default: mask_addr = CMIS_MSK_RX_LW;
      endcase
    end
  endfunction

  // Commit the mask readback only when the CSR request is still the snapshot
  // the walk programmed. Index 0 is FailureFlagTx. Indexes 5..16 follow
  // mask_alm[0] (Tx high alarm) through mask_alm[11] (Rx low warning).
  task automatic take_masks;
    begin
      if ({mask_alm, mask_lol_rx, mask_los_rx, mask_lol_tx, mask_los_tx, mask_fail} == mk_snap) begin
        mk_fail_rb   <= mk_snap[0];
        mk_los_tx_rb <= mk_snap[1];
        mk_lol_tx_rb <= mk_snap[2];
        mk_los_rx_rb <= mk_snap[3];
        mk_lol_rx_rb <= mk_snap[4];
        mk_alm_rb    <= mk_snap[16:5];
        mk_ok        <= 1'b1;
      end
    end
  endtask

  assign busy  = launch || inflight;
  assign armed = ctrl_ok && tx_ok;

  integer ci;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (ci = 0; ci < 32; ci = ci + 1)
        cap[ci] <= 8'h00;
      cmd_valid <= 1'b0;
      cmd_write <= 1'b0;
      cmd_addr  <= 8'h00;
      cmd_wdata <= 8'h00;
      cmd_rlen  <= 6'd1;
      op        <= OP_RD26;
      launch    <= 1'b0;
      inflight  <= 1'b0;
      wait_gap  <= 1'b0;
      ctrl_ok   <= 1'b0;
      tx_ok     <= 1'b0;
      sq_ok     <= 1'b0;
      dp_ok     <= 1'b0;
      as_ok     <= 1'b0;
      as_rb     <= 8'h00;
      mk_ok     <= 1'b0;
      mm_ok     <= 1'b0;
      mm_rb     <= 8'hFF;
      mm_snap   <= 8'hFF;
      sc_ok     <= 1'b0;
      sc_rb     <= 1'b1;
      sc_snap   <= 1'b1;
      ax_ok     <= 1'b0;
      ax_rb     <= 8'hFF;
      ax_snap   <= 8'hFF;
      a3_ok     <= 1'b0;
      a3_rb     <= 8'hFF;
      a3_snap   <= 8'hFF;
      mk_i      <= 5'd0;
      mk_snap   <= 17'h1FFFF;
      mk_fail_rb   <= 1'b1;
      mk_los_tx_rb <= 1'b1;
      mk_lol_tx_rb <= 1'b1;
      mk_los_rx_rb <= 1'b1;
      mk_lol_rx_rb <= 1'b1;
      mk_alm_rb    <= 12'hFFF;
      st_fresh  <= 1'b0;
      sw_pend   <= 1'b0;
      ap_pend   <= 1'b0;
      gapcnt    <= 16'd0;
      present   <= 1'b0;
      nack      <= 1'b0;
      low_pwr_rb <= 1'b0;
      tx_disable_rb <= 1'b0;
      tx_squelch_rb <= 1'b0;
      dp_state     <= CMIS_DP_DEACT;
      dp_deinit_rb <= 1'b1;
      dp_activated <= 1'b0;
      config_status <= CMIS_CFG_NONE;
      active_appsel <= 8'h00;
      dp_init_pend  <= 1'b0;
      out_status_rx <= 1'b0;
      out_status_tx <= 1'b0;
      dp_flag       <= 1'b0;
      dp_valid      <= 1'b0;
      flag_fail     <= 1'b0;
      flag_los_tx   <= 1'b0;
      flag_lol_tx   <= 1'b0;
      flag_los_rx   <= 1'b0;
      flag_lol_rx   <= 1'b0;
      flag_alm      <= 12'h000;
      ident     <= 8'h00;
      rev       <= 8'h00;
      mod_state <= 3'd0;
      int_deasserted <= 1'b1;
      flag0 <= 8'h00;
      flag1 <= 8'h00;
      flag2 <= 8'h00;
      flag3 <= 8'h00;
      temp_s16 <= 16'h0000;
      vcc_u16  <= 16'h0000;
      opt_tx_u16  <= 16'h0000;
      bias_tx_u16 <= 16'h0000;
      opt_rx_u16  <= 16'h0000;
      aux1_s16    <= 16'h0000;
      aux2_s16    <= 16'h0000;
      aux3_s16    <= 16'h0000;
      cust_s16    <= 16'h0000;
    end else begin
      if (rx_valid)
        cap[rx_index] <= rx_data;

      if (sw_reset_pulse)
        sw_pend <= 1'b1;
      if (apply_pulse)
        ap_pend <= 1'b1;

      cmd_valid <= 1'b0;
      if (launch && cmd_ready) begin
        cmd_valid <= 1'b1;
        launch    <= 1'b0;
        inflight  <= 1'b1;
      end else if (cmd_done) begin
        inflight <= 1'b0;
        if (cmd_nack || mod_prs_n) begin
          nack     <= 1'b1;
          present  <= 1'b0;
          ctrl_ok  <= 1'b0;
          tx_ok    <= 1'b0;
          sq_ok    <= 1'b0;
          dp_ok    <= 1'b0;
          as_ok    <= 1'b0;
          mk_ok    <= 1'b0;
          mm_ok    <= 1'b0;
          sc_ok    <= 1'b0;
          ax_ok    <= 1'b0;
          a3_ok    <= 1'b0;
          st_fresh <= 1'b0;
          dp_state <= CMIS_DP_DEACT;
          dp_activated <= 1'b0;
          config_status <= CMIS_CFG_NONE;
          active_appsel <= 8'h00;
          dp_init_pend  <= 1'b0;
          out_status_rx <= 1'b0;
          out_status_tx <= 1'b0;
          dp_flag       <= 1'b0;
          dp_valid      <= 1'b0;
          flag_fail     <= 1'b0;
          flag_los_tx   <= 1'b0;
          flag_lol_tx   <= 1'b0;
          flag_los_rx   <= 1'b0;
          flag_lol_rx   <= 1'b0;
          flag_alm      <= 12'h000;
          opt_tx_u16    <= 16'h0000;
          bias_tx_u16   <= 16'h0000;
          opt_rx_u16    <= 16'h0000;
          aux1_s16      <= 16'h0000;
          aux2_s16      <= 16'h0000;
          aux3_s16      <= 16'h0000;
          cust_s16      <= 16'h0000;
          wait_gap <= 1'b1;
          gapcnt   <= GAPW[15:0];
        end else begin
          nack <= 1'b0;
          case (op)
            OP_RD26: begin
              if ((cap[0][4] == low_pwr_sw) && !sw_pend) begin
                low_pwr_rb <= low_pwr_sw;
                ctrl_ok    <= 1'b1;
              end else begin
                op        <= OP_WR26;
                cmd_write <= 1'b1;
                cmd_addr  <= CMIS_CTL;
                cmd_wdata <= merge_ctl(cap[0], low_pwr_sw, sw_pend);
                cmd_rlen  <= 6'd1;
                launch    <= 1'b1;
              end
            end
            OP_WR26: begin
              low_pwr_rb <= low_pwr_sw;
              ctrl_ok    <= 1'b1;
              if (!sw_reset_pulse)
                sw_pend <= 1'b0;
            end
            OP_PG: begin
              op        <= OP_RD130;
              cmd_write <= 1'b0;
              cmd_addr  <= CMIS_TXDIS;
              cmd_rlen  <= 6'd1;
              launch    <= 1'b1;
            end
            OP_RD130: begin
              op        <= OP_WR130;
              cmd_write <= 1'b1;
              cmd_addr  <= CMIS_TXDIS;
              cmd_wdata <= merge_bit0(cap[0], tx_disable);
              cmd_rlen  <= 6'd1;
              launch    <= 1'b1;
            end
            OP_WR130: begin
              tx_disable_rb <= tx_disable;
              tx_ok         <= 1'b1;
            end
            OP_SQ_PG: begin
              op        <= OP_SQ_RD;
              cmd_write <= 1'b0;
              cmd_addr  <= CMIS_SQFORCE;
              cmd_rlen  <= 6'd1;
              launch    <= 1'b1;
            end
            OP_SQ_RD: begin
              if (cap[0][0] == tx_squelch) begin
                tx_squelch_rb <= tx_squelch;
                sq_ok         <= 1'b1;
              end else begin
                op        <= OP_SQ_WR;
                cmd_write <= 1'b1;
                cmd_addr  <= CMIS_SQFORCE;
                cmd_wdata <= merge_bit0(cap[0], tx_squelch);
                cmd_rlen  <= 6'd1;
                launch    <= 1'b1;
              end
            end
            OP_SQ_WR: begin
              tx_squelch_rb <= tx_squelch;
              sq_ok         <= 1'b1;
            end
            OP_DP_PG: begin
              op        <= OP_DP_RD;
              cmd_write <= 1'b0;
              cmd_addr  <= CMIS_DPDEINIT;
              cmd_rlen  <= 6'd1;
              launch    <= 1'b1;
            end
            OP_DP_RD: begin
              if (cap[0][0] == dp_deinit) begin
                dp_deinit_rb <= dp_deinit;
                dp_ok        <= 1'b1;
              end else begin
                op        <= OP_DP_WR;
                cmd_write <= 1'b1;
                cmd_addr  <= CMIS_DPDEINIT;
                cmd_wdata <= merge_bit0(cap[0], dp_deinit);
                cmd_rlen  <= 6'd1;
                launch    <= 1'b1;
              end
            end
            OP_DP_WR: begin
              dp_deinit_rb <= dp_deinit;
              dp_ok        <= 1'b1;
            end
            OP_AS_PG: begin
              op        <= OP_AS_RD;
              cmd_write <= 1'b0;
              cmd_addr  <= CMIS_SCS0;
              cmd_rlen  <= 6'd1;
              launch    <= 1'b1;
            end
            OP_AS_RD: begin
              if (cap[0] == staged_appsel) begin
                as_rb <= staged_appsel;
                as_ok <= 1'b1;
              end else begin
                op        <= OP_AS_WR;
                cmd_write <= 1'b1;
                cmd_addr  <= CMIS_SCS0;
                cmd_wdata <= staged_appsel;
                cmd_rlen  <= 6'd1;
                launch    <= 1'b1;
              end
            end
            OP_AS_WR: begin
              as_rb <= staged_appsel;
              as_ok <= 1'b1;
            end
            OP_AP_PG: begin
              op        <= OP_AP_WR;
              cmd_write <= 1'b1;
              cmd_addr  <= CMIS_APPLY;
              cmd_wdata <= 8'h01;
              cmd_rlen  <= 6'd1;
              launch    <= 1'b1;
            end
            OP_AP_WR: begin
              if (!apply_pulse)
                ap_pend <= 1'b0;
            end
            OP_ST_PG: begin
              op        <= OP_ST_RD;
              cmd_write <= 1'b0;
              cmd_addr  <= 8'd128;
              cmd_rlen  <= 6'd1;
              launch    <= 1'b1;
            end
            OP_ST_RD: begin
              dp_state     <= cap[0][3:0];
              dp_activated <= (cap[0][3:0] == CMIS_DP_ACT);
              op        <= OP_ST_OUT;
              cmd_write <= 1'b0;
              cmd_addr  <= CMIS_OUTRX;
              cmd_rlen  <= 6'd3;
              launch    <= 1'b1;
            end
            OP_ST_OUT: begin
              out_status_rx <= cap[0][0];
              out_status_tx <= cap[1][0];
              dp_flag       <= cap[2][0];
              op        <= OP_ST_CFG;
              cmd_write <= 1'b0;
              cmd_addr  <= CMIS_CFGSTAT;
              cmd_rlen  <= 6'd5;
              launch    <= 1'b1;
            end
            OP_ST_CFG: begin
              config_status <= cap[0][3:0];
              active_appsel <= cap[4];
              op        <= OP_ST_PND;
              cmd_write <= 1'b0;
              cmd_addr  <= CMIS_DPPEND;
              cmd_rlen  <= 6'd1;
              launch    <= 1'b1;
            end
            OP_ST_PND: begin
              dp_init_pend <= cap[0][0];
              op        <= OP_FL_TX;
              cmd_write <= 1'b0;
              cmd_addr  <= CMIS_FAILTX;
              cmd_rlen  <= 6'd3;
              launch    <= 1'b1;
            end
            OP_FL_TX: begin
              flag_fail   <= cap[0][0];
              flag_los_tx <= cap[1][0];
              flag_lol_tx <= cap[2][0];
              op        <= OP_FL_RX;
              cmd_write <= 1'b0;
              cmd_addr  <= CMIS_LOSRX;
              cmd_rlen  <= 6'd2;
              launch    <= 1'b1;
            end
            OP_FL_RX: begin
              flag_los_rx <= cap[0][0];
              flag_lol_rx <= cap[1][0];
              op        <= OP_MON_TX;
              cmd_write <= 1'b0;
              cmd_addr  <= CMIS_OPT_TX;
              cmd_rlen  <= 6'd2;
              launch    <= 1'b1;
            end
            OP_MON_TX: begin
              opt_tx_u16 <= {cap[0], cap[1]};
              op        <= OP_MON_BI;
              cmd_write <= 1'b0;
              cmd_addr  <= CMIS_BIAS_TX;
              cmd_rlen  <= 6'd2;
              launch    <= 1'b1;
            end
            OP_MON_BI: begin
              bias_tx_u16 <= {cap[0], cap[1]};
              op        <= OP_MON_RX;
              cmd_write <= 1'b0;
              cmd_addr  <= CMIS_OPT_RX;
              cmd_rlen  <= 6'd2;
              launch    <= 1'b1;
            end
            OP_MON_RX: begin
              opt_rx_u16 <= {cap[0], cap[1]};
              op        <= OP_AL_TX;
              cmd_write <= 1'b0;
              cmd_addr  <= CMIS_ALM_TX;
              cmd_rlen  <= 6'd8;
              launch    <= 1'b1;
            end
            OP_AL_TX: begin
              flag_alm[7:0] <= {cap[7][0], cap[6][0], cap[5][0], cap[4][0],
                                cap[3][0], cap[2][0], cap[1][0], cap[0][0]};
              op        <= OP_AL_RX;
              cmd_write <= 1'b0;
              cmd_addr  <= CMIS_ALM_RX;
              cmd_rlen  <= 6'd4;
              launch    <= 1'b1;
            end
            OP_AL_RX: begin
              flag_alm[11:8] <= {cap[3][0], cap[2][0], cap[1][0], cap[0][0]};
              op        <= OP_AUX;
              cmd_write <= 1'b0;
              cmd_addr  <= CMIS_AUX1_MON;
              cmd_rlen  <= 6'd4;
              launch    <= 1'b1;
            end
            OP_AUX: begin
              aux1_s16 <= {cap[0], cap[1]};
              aux2_s16 <= {cap[2], cap[3]};
              op        <= OP_A3;
              cmd_write <= 1'b0;
              cmd_addr  <= CMIS_AUX3_MON;
              cmd_rlen  <= 6'd4;
              launch    <= 1'b1;
            end
            OP_A3: begin
              aux3_s16 <= {cap[0], cap[1]};
              cust_s16 <= {cap[2], cap[3]};
              dp_valid <= 1'b1;
              st_fresh <= 1'b1;
            end
            OP_A3_RD: begin
              if (cap[0] == a3_snap) begin
                a3_rb <= a3_snap;
                a3_ok <= 1'b1;
              end else begin
                op        <= OP_A3_WR;
                cmd_write <= 1'b1;
                cmd_addr  <= CMIS_MSK_A3;
                cmd_wdata <= a3_snap;
                cmd_rlen  <= 6'd1;
                launch    <= 1'b1;
              end
            end
            OP_A3_WR: begin
              a3_rb <= a3_snap;
              a3_ok <= 1'b1;
            end
            OP_MM_RD: begin
              if (cap[0] == mm_snap) begin
                mm_rb <= mm_snap;
                mm_ok <= 1'b1;
              end else begin
                op        <= OP_MM_WR;
                cmd_write <= 1'b1;
                cmd_addr  <= CMIS_MSK_MON;
                cmd_wdata <= mm_snap;
                cmd_rlen  <= 6'd1;
                launch    <= 1'b1;
              end
            end
            OP_MM_WR: begin
              mm_rb <= mm_snap;
              mm_ok <= 1'b1;
            end
            OP_SC_RD: begin
              if (cap[0][0] == sc_snap) begin
                sc_rb <= sc_snap;
                sc_ok <= 1'b1;
              end else begin
                op        <= OP_SC_WR;
                cmd_write <= 1'b1;
                cmd_addr  <= CMIS_MSK_SC;
                cmd_wdata <= merge_bit0(cap[0], sc_snap);
                cmd_rlen  <= 6'd1;
                launch    <= 1'b1;
              end
            end
            OP_SC_WR: begin
              sc_rb <= sc_snap;
              sc_ok <= 1'b1;
            end
            OP_AX_RD: begin
              if (cap[0] == ax_snap) begin
                ax_rb <= ax_snap;
                ax_ok <= 1'b1;
              end else begin
                op        <= OP_AX_WR;
                cmd_write <= 1'b1;
                cmd_addr  <= CMIS_MSK_AUX;
                cmd_wdata <= ax_snap;
                cmd_rlen  <= 6'd1;
                launch    <= 1'b1;
              end
            end
            OP_AX_WR: begin
              ax_rb <= ax_snap;
              ax_ok <= 1'b1;
            end
            OP_MK_PG: begin
              mk_i      <= 5'd0;
              op        <= OP_MK_RD;
              cmd_write <= 1'b0;
              cmd_addr  <= mask_addr(5'd0);
              cmd_rlen  <= 6'd1;
              launch    <= 1'b1;
            end
            OP_MK_RD: begin
              if (cap[0][0] == mk_snap[mk_i]) begin
                if (mk_i == MK_LAST) begin
                  take_masks();
                end else begin
                  mk_i      <= mk_i + 5'd1;
                  op        <= OP_MK_RD;
                  cmd_write <= 1'b0;
                  cmd_addr  <= mask_addr(mk_i + 5'd1);
                  cmd_rlen  <= 6'd1;
                  launch    <= 1'b1;
                end
              end else begin
                op        <= OP_MK_WR;
                cmd_write <= 1'b1;
                cmd_addr  <= mask_addr(mk_i);
                cmd_wdata <= merge_bit0(cap[0], mk_snap[mk_i]);
                cmd_rlen  <= 6'd1;
                launch    <= 1'b1;
              end
            end
            OP_MK_WR: begin
              if (mk_i == MK_LAST) begin
                take_masks();
              end else begin
                mk_i      <= mk_i + 5'd1;
                op        <= OP_MK_RD;
                cmd_write <= 1'b0;
                cmd_addr  <= mask_addr(mk_i + 5'd1);
                cmd_rlen  <= 6'd1;
                launch    <= 1'b1;
              end
            end
            OP_POLL: begin
              ident          <= cap[0];
              rev            <= cap[1];
              mod_state      <= cap[3][3:1];
              int_deasserted <= cap[3][0];
              flag0          <= cap[8];
              flag1          <= cap[9];
              flag2          <= cap[10];
              flag3          <= cap[11];
              temp_s16       <= {cap[14], cap[15]};
              vcc_u16        <= {cap[16], cap[17]};
              present        <= (cap[0] != 8'h00) && (cap[0] != 8'hFF);
              st_fresh       <= 1'b0;
              wait_gap       <= 1'b1;
              gapcnt         <= GAPW[15:0];
            end
            default: ;
          endcase
        end
      end else if (!inflight && !launch) begin
        if (mod_prs_n || !poll_en) begin
          if (mod_prs_n) begin
            present <= 1'b0;
            ctrl_ok <= 1'b0;
            tx_ok   <= 1'b0;
            sq_ok   <= 1'b0;
            dp_ok   <= 1'b0;
            as_ok   <= 1'b0;
            mk_ok   <= 1'b0;
            mm_ok   <= 1'b0;
            sc_ok   <= 1'b0;
            ax_ok   <= 1'b0;
            a3_ok   <= 1'b0;
            st_fresh <= 1'b0;
            dp_state <= CMIS_DP_DEACT;
            dp_activated <= 1'b0;
            config_status <= CMIS_CFG_NONE;
            active_appsel <= 8'h00;
            dp_init_pend  <= 1'b0;
            out_status_rx <= 1'b0;
            out_status_tx <= 1'b0;
            dp_flag       <= 1'b0;
            dp_valid      <= 1'b0;
            flag_fail     <= 1'b0;
            flag_los_tx   <= 1'b0;
            flag_lol_tx   <= 1'b0;
            flag_los_rx   <= 1'b0;
            flag_lol_rx   <= 1'b0;
            flag_alm      <= 12'h000;
            opt_tx_u16    <= 16'h0000;
            bias_tx_u16   <= 16'h0000;
            opt_rx_u16    <= 16'h0000;
            aux1_s16      <= 16'h0000;
            aux2_s16      <= 16'h0000;
            aux3_s16      <= 16'h0000;
            cust_s16      <= 16'h0000;
          end
        end else if (wait_gap) begin
          if (gapcnt == 16'd0)
            wait_gap <= 1'b0;
          else
            gapcnt <= gapcnt - 16'd1;
        end else if (!ctrl_ok || sw_pend || (low_pwr_sw != low_pwr_rb)) begin
          op        <= OP_RD26;
          cmd_write <= 1'b0;
          cmd_addr  <= CMIS_CTL;
          cmd_rlen  <= 6'd1;
          launch    <= 1'b1;
        end else if (!tx_ok || (tx_disable != tx_disable_rb)) begin
          op        <= OP_PG;
          cmd_write <= 1'b1;
          cmd_addr  <= CMIS_PAGE;
          cmd_wdata <= CMIS_LANE_PAGE;
          cmd_rlen  <= 6'd1;
          launch    <= 1'b1;
        end else if (!sq_ok || (tx_squelch != tx_squelch_rb)) begin
          op        <= OP_SQ_PG;
          cmd_write <= 1'b1;
          cmd_addr  <= CMIS_PAGE;
          cmd_wdata <= CMIS_LANE_PAGE;
          cmd_rlen  <= 6'd1;
          launch    <= 1'b1;
        end else if (!dp_ok || (dp_deinit != dp_deinit_rb)) begin
          op        <= OP_DP_PG;
          cmd_write <= 1'b1;
          cmd_addr  <= CMIS_PAGE;
          cmd_wdata <= CMIS_LANE_PAGE;
          cmd_rlen  <= 6'd1;
          launch    <= 1'b1;
        end else if (!as_ok || (staged_appsel != as_rb)) begin
          op        <= OP_AS_PG;
          cmd_write <= 1'b1;
          cmd_addr  <= CMIS_PAGE;
          cmd_wdata <= CMIS_LANE_PAGE;
          cmd_rlen  <= 6'd1;
          launch    <= 1'b1;
        end else if (ap_pend) begin
          op        <= OP_AP_PG;
          cmd_write <= 1'b1;
          cmd_addr  <= CMIS_PAGE;
          cmd_wdata <= CMIS_LANE_PAGE;
          cmd_rlen  <= 6'd1;
          launch    <= 1'b1;
        end else if (!mk_ok || mask_fail != mk_fail_rb || mask_los_tx != mk_los_tx_rb ||
                     mask_lol_tx != mk_lol_tx_rb || mask_los_rx != mk_los_rx_rb ||
                     mask_lol_rx != mk_lol_rx_rb || mask_alm != mk_alm_rb) begin
          mk_snap   <= {mask_alm, mask_lol_rx, mask_los_rx, mask_lol_tx, mask_los_tx, mask_fail};
          op        <= OP_MK_PG;
          cmd_write <= 1'b1;
          cmd_addr  <= CMIS_PAGE;
          cmd_wdata <= CMIS_LANE_PAGE;
          cmd_rlen  <= 6'd1;
          launch    <= 1'b1;
        end else if (!mm_ok || mask_mon != mm_rb) begin
          mm_snap   <= mask_mon;
          op        <= OP_MM_RD;
          cmd_write <= 1'b0;
          cmd_addr  <= CMIS_MSK_MON;
          cmd_rlen  <= 6'd1;
          launch    <= 1'b1;
        end else if (!sc_ok || mask_sc != sc_rb) begin
          sc_snap   <= mask_sc;
          op        <= OP_SC_RD;
          cmd_write <= 1'b0;
          cmd_addr  <= CMIS_MSK_SC;
          cmd_rlen  <= 6'd1;
          launch    <= 1'b1;
        end else if (!ax_ok || mask_aux != ax_rb) begin
          ax_snap   <= mask_aux;
          op        <= OP_AX_RD;
          cmd_write <= 1'b0;
          cmd_addr  <= CMIS_MSK_AUX;
          cmd_rlen  <= 6'd1;
          launch    <= 1'b1;
        end else if (!a3_ok || mask_a3 != a3_rb) begin
          a3_snap   <= mask_a3;
          op        <= OP_A3_RD;
          cmd_write <= 1'b0;
          cmd_addr  <= CMIS_MSK_A3;
          cmd_rlen  <= 6'd1;
          launch    <= 1'b1;
        end else if (!st_fresh) begin
          op        <= OP_ST_PG;
          cmd_write <= 1'b1;
          cmd_addr  <= CMIS_PAGE;
          cmd_wdata <= CMIS_STAT_PAGE;
          cmd_rlen  <= 6'd1;
          launch    <= 1'b1;
        end else begin
          op        <= OP_POLL;
          cmd_write <= 1'b0;
          cmd_addr  <= 8'h00;
          cmd_rlen  <= CMIS_POLL_N;
          launch    <= 1'b1;
        end
      end
    end
  end
endmodule
