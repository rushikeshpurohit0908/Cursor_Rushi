// Behavioral SFP112 module on the CMIS two-wire interface.
//
// Lower memory follows CMIS 5.0. Byte 0 is SFF-8024 identifier 20h
// (SFP/SFP+ with CMIS). Byte 26 bit 4 is LowPwrRequestSW, bit 6 is
// LowPwrAllowRequestHW, and bit 3 is the self-clearing SoftwareReset.
// Page 10h byte 130 bit 0 is OutputDisableTx for lane 1, byte 132 bit 0 is
// OutputSquelchForceTx, byte 128 bit 0 is DPDeinit, byte 145 is the staged
// AppSel for lane 1, and byte 143 bit 0 is the write-only ApplyDPInit
// trigger. Page 11h is lane status: ConfigStatus is byte 202 and the active
// AppSel is byte 206. Bytes 135, 136, 137, 147, and 148 are lane-1
// FailureFlagTx, LOSFlagTx, CDRLOLFlagTx, LOSFlagRx, and CDRLOLFlagRx.
// A flag stays set while its input is set and holds a pulse until that
// byte is read. Page 10h bytes 214, 215, 216, 226, and 227 bit 0 mask
// those flags. int_n is low while any unmasked flag is set. One data
// path, lane 1, follows Figure 6-5 with
// SteppedConfigOnly = 0. ModuleReady and DPDeinit clear run the path up.
// A successful ApplyDPInit copies the staged byte, sets DPInitPending, and
// cycles a live lane through DPDeactivated. ConfigInProgress holds for one
// PWR_DLY. A second trigger during that dwell is ignored.
// Temperature is signed 1/256 C at bytes 14-15. Supply is unsigned 100 uV
// at bytes 16-17. The slave does not stretch SCL. sda_oe drives a zero.
module cmis_sfp_slave #(
  parameter int PWR_DLY = 40,
  parameter int DP_DLY = 16,
  parameter [7:0] TXDIS_INIT = 8'hA0,
  parameter [7:0] DPDE_INIT = 8'h00
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        scl_i,
  input  logic        sda_i,
  output logic        sda_oe,
  output logic        int_n,
  input  logic        lpmode,
  input  logic        reset_n,
  input  logic        force_fault,
  input  logic        fail_tx,
  input  logic        los_tx,
  input  logic        lol_tx,
  input  logic        los_rx,
  input  logic        lol_rx,
  input  logic [15:0] temp_s16,
  input  logic [15:0] vcc_u16,
  output logic [2:0]  mod_state,
  output logic [7:0]  txdis_byte,
  output logic [7:0]  dpde_byte,
  output logic [3:0]  dp_state,
  output logic        rx_status,
  output logic        tx_status,
  output logic        flag_state,
  output logic [7:0]  squelch_byte,
  output logic [3:0]  config_status,
  output logic [7:0]  active_appsel,
  output logic        dp_init_pend,
  output logic [7:0]  apply_ignored
);
  `include "fc_cmis.vh"

  localparam [2:0] S_IDLE = 3'd0;
  localparam [2:0] S_ADDR = 3'd1;
  localparam [2:0] S_ACK  = 3'd2;
  localparam [2:0] S_RX   = 3'd3;
  localparam [2:0] S_TX   = 3'd4;
  localparam [2:0] S_MACK = 3'd5;

  logic [7:0] mem [0:255];
  logic [7:0] p10 [0:255];
  logic [2:0] st;
  logic [7:0] sh;
  logic [3:0] bits;
  logic [7:0] ptr;
  logic       scl_q, sda_q;
  logic       reading;
  logic       expect_ptr;
  logic       mack;
  logic       flag_sc;
  logic       flag_clr;
  logic       sw_hit;
  logic       apply_hit;
  logic       dp_flag_clr;
  logic [4:0] lane_clr;
  logic       f_fail_tx, f_los_tx, f_lol_tx, f_los_rx, f_lol_rx;
  logic       sw_resetting;
  logic       held;
  logic       raise_flag;
  logic [2:0] mod_state_q;
  logic [15:0] pwr_cnt;
  logic [3:0] dp_q;
  logic [15:0] dp_cnt;
  logic       dp_flag;
  logic       dp_pending;
  logic [3:0] dp_nxt;
  logic [15:0] cnt_nxt;
  logic       pend_nxt;
  logic       flag_set;
  logic       cfg_take;
  logic [3:0] cfg_q;
  logic [15:0] cfg_cnt;
  logic [7:0] cfg_snap;
  logic [7:0] active_sel;
  integer ii;

  localparam int DLY = (DP_DLY < 1) ? 1 : DP_DLY;

  wire start = scl_q && scl_i && sda_q && !sda_i;
  wire stop  = scl_q && scl_i && !sda_q && sda_i;
  wire rise  = !scl_q && scl_i;
  wire fall  = scl_q && !scl_i;
  wire lowpwr_s = mem[CMIS_CTL][4] | (mem[CMIS_CTL][6] & lpmode);
  wire lane_int = (f_fail_tx && !p10[CMIS_MFAILTX][0]) ||
                  (f_los_tx  && !p10[CMIS_MLOSTX][0])  ||
                  (f_lol_tx  && !p10[CMIS_MLOLTX][0])  ||
                  (f_los_rx  && !p10[CMIS_MLOSRX][0])  ||
                  (f_lol_rx  && !p10[CMIS_MLOLRX][0]);
  wire int_deassert = !((flag_sc && !mem[31][0]) || lane_int);
  assign int_n = int_deassert;

  function automatic [4:0] lane_clr_of(input [7:0] a, input [7:0] page);
    begin
      lane_clr_of = 5'h00;
      if (page == CMIS_STAT_PAGE) begin
        if (a == CMIS_FFAILTX)
          lane_clr_of[0] = 1'b1;
        else if (a == CMIS_FLOSTX)
          lane_clr_of[1] = 1'b1;
        else if (a == CMIS_FLOLTX)
          lane_clr_of[2] = 1'b1;
        else if (a == CMIS_FLOSRX)
          lane_clr_of[3] = 1'b1;
        else if (a == CMIS_FLOLRX)
          lane_clr_of[4] = 1'b1;
      end
    end
  endfunction
  wire module_ready = reset_n && !sw_resetting && !force_fault &&
                      (mod_state_q == CMIS_ST_RDY);
  // Eq. 6-6 and 6-12. OutputDisableTx and OutputSquelchForceTx both hold
  // the lane in DPInitialized. DPInitPending reinitializes a live lane.
  wire dp_deinit_s = !module_ready || lowpwr_s || p10[CMIS_DPDEINIT][0];
  wire dp_redeinit_s = dp_deinit_s || dp_pending;
  wire dp_deactivate_s = dp_redeinit_s || p10[CMIS_TXDIS][0] || p10[CMIS_SQFORCE][0];

  assign txdis_byte = p10[CMIS_TXDIS];
  assign dpde_byte = p10[CMIS_DPDEINIT];
  assign squelch_byte = p10[CMIS_SQFORCE];
  assign config_status = cfg_q;
  assign active_appsel = active_sel;
  assign dp_init_pend = dp_pending;
  assign dp_state = dp_q;
  assign rx_status = (dp_q == CMIS_DP_INITED) || (dp_q == CMIS_DP_TXON) ||
                     (dp_q == CMIS_DP_TXOFF) || (dp_q == CMIS_DP_ACT);
  assign tx_status = (dp_q == CMIS_DP_ACT);
  assign flag_state = flag_sc;
  assign mod_state = force_fault ? CMIS_ST_FLT :
                     sw_resetting ? CMIS_ST_LOW : mod_state_q;

  task automatic load_tx;
    input [7:0] a;
    reg [7:0] b;
    begin
      b = peek(a);
      sh <= b;
      sda_oe <= ~b[7];
    end
  endtask

  function automatic [7:0] peek(input [7:0] a);
    begin
      if (a == 8'd3)
        peek = {4'b0, (force_fault ? CMIS_ST_FLT : (sw_resetting ? CMIS_ST_LOW : mod_state_q)), int_deassert};
      else if (a == 8'd8)
        peek = {7'b0, flag_sc};
      else if (a == 8'd14)
        peek = temp_s16[15:8];
      else if (a == 8'd15)
        peek = temp_s16[7:0];
      else if (a == 8'd16)
        peek = vcc_u16[15:8];
      else if (a == 8'd17)
        peek = vcc_u16[7:0];
      else if (a < 8'd128)
        peek = mem[a];
      else if (mem[CMIS_PAGE] == CMIS_LANE_PAGE)
        peek = p10[a];
      else if (mem[CMIS_PAGE] == CMIS_STAT_PAGE) begin
        if (a == CMIS_DPDEINIT)
          peek = {4'h0, dp_q};
        else if (a == CMIS_OUTRX)
          peek = {7'h0, rx_status};
        else if (a == CMIS_OUTTX)
          peek = {7'h0, tx_status};
        else if (a == CMIS_DPFLAG)
          peek = {7'h0, dp_flag};
        else if (a == CMIS_FFAILTX)
          peek = {7'h0, f_fail_tx};
        else if (a == CMIS_FLOSTX)
          peek = {7'h0, f_los_tx};
        else if (a == CMIS_FLOLTX)
          peek = {7'h0, f_lol_tx};
        else if (a == CMIS_FLOSRX)
          peek = {7'h0, f_los_rx};
        else if (a == CMIS_FLOLRX)
          peek = {7'h0, f_lol_rx};
        else if (a == CMIS_DPPEND)
          peek = {7'h0, dp_pending};
        else if (a == CMIS_CFGSTAT)
          peek = {4'h0, cfg_q};
        else if (a == CMIS_ACS0)
          peek = active_sel;
        else
          peek = 8'h00;
      end else
        peek = 8'h00;
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (ii = 0; ii < 256; ii = ii + 1) begin
        mem[ii] <= 8'h00;
        p10[ii] <= 8'h00;
      end
      mem[0] <= CMIS_ID_SFP;
      mem[1] <= CMIS_REV50;
      mem[2] <= 8'h00;
      mem[CMIS_CTL] <= 8'h40;
      mem[31] <= 8'hFF;
      mem[CMIS_PAGE] <= 8'h00;
      mem[CMIS_APP_BASE + 0] <= CMIS_H_128;
      mem[CMIS_APP_BASE + 1] <= CMIS_M_128;
      mem[CMIS_APP_BASE + 2] <= CMIS_LANES11;
      mem[CMIS_APP_BASE + 3] <= CMIS_LANE1;
      mem[CMIS_APP_BASE + 4] <= CMIS_H_64;
      mem[CMIS_APP_BASE + 5] <= CMIS_M_64;
      mem[CMIS_APP_BASE + 6] <= CMIS_LANES11;
      mem[CMIS_APP_BASE + 7] <= CMIS_LANE1;
      mem[CMIS_APP_BASE + 8] <= CMIS_H_32;
      mem[CMIS_APP_BASE + 9] <= CMIS_M_32;
      mem[CMIS_APP_BASE + 10] <= CMIS_LANES11;
      mem[CMIS_APP_BASE + 11] <= CMIS_LANE1;
      p10[CMIS_TXDIS] <= TXDIS_INIT;
      p10[CMIS_SQFORCE] <= TXDIS_INIT;
      p10[CMIS_DPDEINIT] <= DPDE_INIT;
      p10[CMIS_SCS0] <= CMIS_APP_128;
      p10[CMIS_MFAILTX] <= 8'hFF;
      p10[CMIS_MLOSTX] <= 8'hFF;
      p10[CMIS_MLOLTX] <= 8'hFF;
      p10[CMIS_MLOSRX] <= 8'hFF;
      p10[CMIS_MLOLRX] <= 8'hFF;
      st <= S_IDLE;
      sh <= 8'h00;
      bits <= 4'd0;
      ptr <= 8'h00;
      scl_q <= 1'b1;
      sda_q <= 1'b1;
      reading <= 1'b0;
      expect_ptr <= 1'b0;
      mack <= 1'b1;
      sda_oe <= 1'b0;
      flag_clr <= 1'b0;
      sw_hit <= 1'b0;
      apply_hit <= 1'b0;
      dp_flag_clr <= 1'b0;
      lane_clr <= 5'h00;
    end else begin
      scl_q <= scl_i;
      sda_q <= sda_i;
      flag_clr <= 1'b0;
      sw_hit <= 1'b0;
      apply_hit <= 1'b0;
      dp_flag_clr <= 1'b0;
      lane_clr <= 5'h00;
      if (!reset_n) begin
        st <= S_IDLE;
        sda_oe <= 1'b0;
        bits <= 4'd0;
      end else if (start && !sw_resetting) begin
        st <= S_ADDR;
        bits <= 4'd0;
        sh <= 8'h00;
        sda_oe <= 1'b0;
      end else if (start || stop) begin
        st <= S_IDLE;
        sda_oe <= 1'b0;
      end else begin
        case (st)
          S_ADDR, S_RX: begin
            if (rise) begin
              sh <= {sh[6:0], sda_i};
              bits <= bits + 4'd1;
            end else if (fall && bits == 4'd8) begin
              bits <= 4'd0;
              if (st == S_ADDR) begin
                if (sh[7:1] == CMIS_DEV) begin
                  reading <= sh[0];
                  if (!sh[0])
                    expect_ptr <= 1'b1;
                  st <= S_ACK;
                  sda_oe <= 1'b1;
                end else begin
                  st <= S_IDLE;
                  sda_oe <= 1'b0;
                end
              end else begin
                st <= S_ACK;
                sda_oe <= 1'b1;
                if (expect_ptr) begin
                  ptr <= sh;
                  expect_ptr <= 1'b0;
                end else if (ptr == CMIS_CTL) begin
                  mem[ptr] <= sh & 8'hF7;
                  if (sh[3])
                    sw_hit <= 1'b1;
                  ptr <= ptr + 8'd1;
                end else if (ptr < 8'd128) begin
                  mem[ptr] <= sh;
                  ptr <= ptr + 8'd1;
                end else if (mem[CMIS_PAGE] == CMIS_LANE_PAGE && ptr == CMIS_APPLY) begin
                  // Write-only trigger. A 1 in bit 0 requests provision.
                  if (sh[0])
                    apply_hit <= 1'b1;
                  ptr <= ptr + 8'd1;
                end else if (mem[CMIS_PAGE] == CMIS_LANE_PAGE) begin
                  p10[ptr] <= sh;
                  ptr <= ptr + 8'd1;
                end else begin
                  ptr <= ptr + 8'd1;
                end
              end
            end
          end
          S_ACK: begin
            sda_oe <= 1'b1;
            if (fall) begin
              if (reading && (bits == 4'd0)) begin
                load_tx(ptr);
                if (ptr == 8'd8)
                  flag_clr <= 1'b1;
                if (ptr == CMIS_DPFLAG && mem[CMIS_PAGE] == CMIS_STAT_PAGE)
                  dp_flag_clr <= 1'b1;
                lane_clr <= lane_clr_of(ptr, mem[CMIS_PAGE]);
                ptr <= ptr + 8'd1;
                bits <= 4'd0;
                st <= S_TX;
                reading <= 1'b0;
              end else begin
                sda_oe <= 1'b0;
                bits <= 4'd0;
                st <= S_RX;
              end
            end
          end
          S_TX: begin
            sda_oe <= ~sh[7];
            if (rise) begin
              bits <= bits + 4'd1;
            end else if (fall && bits == 4'd8) begin
              sda_oe <= 1'b0;
              bits <= 4'd0;
              st <= S_MACK;
            end else if (fall) begin
              sh <= {sh[6:0], 1'b0};
              bits <= bits;
            end
          end
          S_MACK: begin
            sda_oe <= 1'b0;
            if (rise)
              mack <= sda_i;
            else if (fall) begin
              if (!mack) begin
                load_tx(ptr);
                if (ptr == 8'd8)
                  flag_clr <= 1'b1;
                if (ptr == CMIS_DPFLAG && mem[CMIS_PAGE] == CMIS_STAT_PAGE)
                  dp_flag_clr <= 1'b1;
                lane_clr <= lane_clr_of(ptr, mem[CMIS_PAGE]);
                ptr <= ptr + 8'd1;
                bits <= 4'd0;
                st <= S_TX;
              end else begin
                st <= S_IDLE;
              end
            end
          end
          default: begin
            st <= S_IDLE;
            sda_oe <= 1'b0;
          end
        endcase
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mod_state_q <= CMIS_ST_LOW;
      flag_sc <= 1'b0;
      sw_resetting <= 1'b0;
      held <= 1'b0;
      pwr_cnt <= 16'd0;
    end else if (!reset_n) begin
      mod_state_q <= CMIS_ST_LOW;
      sw_resetting <= 1'b0;
      pwr_cnt <= 16'd0;
      held <= 1'b1;
    end else begin
      raise_flag = 1'b0;
      if (sw_hit) begin
        sw_resetting <= 1'b1;
        pwr_cnt <= PWR_DLY[15:0];
      end else if (sw_resetting) begin
        if (pwr_cnt == 16'd0) begin
          sw_resetting <= 1'b0;
          mod_state_q <= CMIS_ST_LOW;
          raise_flag = 1'b1;
        end else begin
          pwr_cnt <= pwr_cnt - 16'd1;
        end
      end else if (force_fault) begin
        mod_state_q <= CMIS_ST_FLT;
      end else if (held) begin
        held <= 1'b0;
        raise_flag = 1'b1;
        mod_state_q <= CMIS_ST_LOW;
      end else if (mod_state_q == CMIS_ST_FLT) begin
        mod_state_q <= CMIS_ST_LOW;
      end else begin
        case (mod_state_q)
          CMIS_ST_LOW: begin
            if (!lowpwr_s) begin
              mod_state_q <= CMIS_ST_UP;
              pwr_cnt <= PWR_DLY[15:0];
            end
          end
          CMIS_ST_UP: begin
            if (pwr_cnt == 16'd0) begin
              mod_state_q <= CMIS_ST_RDY;
              raise_flag = 1'b1;
            end else begin
              pwr_cnt <= pwr_cnt - 16'd1;
            end
          end
          CMIS_ST_RDY: begin
            if (lowpwr_s) begin
              mod_state_q <= CMIS_ST_DN;
              pwr_cnt <= PWR_DLY[15:0];
            end
          end
          CMIS_ST_DN: begin
            if (pwr_cnt == 16'd0) begin
              mod_state_q <= CMIS_ST_LOW;
              raise_flag = 1'b1;
            end else begin
              pwr_cnt <= pwr_cnt - 16'd1;
            end
          end
          default: mod_state_q <= CMIS_ST_LOW;
        endcase
      end
      if (raise_flag)
        flag_sc <= 1'b1;
      else if (flag_clr)
        flag_sc <= 1'b0;
    end
  end

  // Figure 6-5. Steady states are DPDeactivated, DPInitialized, and
  // DPActivated. The other four are timed transients. DPStateChangedFlag is
  // set only on entry to a steady state that is not already exiting.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      dp_q <= CMIS_DP_DEACT;
      dp_cnt <= 16'd0;
      dp_flag <= 1'b1;
      dp_pending <= 1'b0;
      cfg_q <= CMIS_CFG_NONE;
      cfg_cnt <= 16'd0;
      cfg_snap <= 8'h00;
      active_sel <= CMIS_APP_128;
      apply_ignored <= 8'h00;
    end else begin
      dp_nxt = dp_q;
      cnt_nxt = dp_cnt;
      pend_nxt = dp_pending;
      flag_set = 1'b0;
      cfg_take = 1'b0;
      // ApplyDPInit. ConfigInProgress lasts one power dwell so the host can
      // observe it, then the staged byte captured at the trigger is checked.
      // AppSel 1..3 with DataPathID 0 is lane 1. Anything else is rejected
      // and the active set is left alone. A second trigger while the dwell
      // is running is ignored. Success copies the byte and sets
      // DPInitPending; the state machine below clears that on the step
      // into DPInit and, if the lane was up, walks it back through
      // DPDeactivated first.
      if (!reset_n || sw_resetting) begin
        cfg_q <= CMIS_CFG_NONE;
        cfg_cnt <= 16'd0;
        active_sel <= CMIS_APP_128;
      end else if (apply_hit && cfg_q == CMIS_CFG_BUSY) begin
        apply_ignored <= apply_ignored + 8'd1;
      end else if (apply_hit) begin
        cfg_q <= CMIS_CFG_BUSY;
        cfg_cnt <= PWR_DLY[15:0];
        cfg_snap <= p10[CMIS_SCS0];
      end else if (cfg_q == CMIS_CFG_BUSY) begin
        if (cfg_cnt != 16'd0)
          cfg_cnt <= cfg_cnt - 16'd1;
        else if (!module_ready)
          cfg_q <= CMIS_CFG_REJ;
        else if ((cfg_snap[7:4] == 4'h0) || (cfg_snap[7:4] > 4'h3))
          cfg_q <= CMIS_CFG_APP;
        else if (cfg_snap[3:1] != 3'd0)
          cfg_q <= CMIS_CFG_DP;
        else begin
          active_sel <= cfg_snap;
          cfg_q <= CMIS_CFG_OK;
          cfg_take = 1'b1;
        end
      end
      if (cfg_take)
        pend_nxt = 1'b1;
      if (!reset_n || sw_resetting || force_fault) begin
        dp_nxt = CMIS_DP_DEACT;
        cnt_nxt = 16'd0;
        pend_nxt = 1'b0;
        if (dp_q != CMIS_DP_DEACT)
          flag_set = 1'b1;
      end else begin
        case (dp_q)
          CMIS_DP_DEACT: begin
            if (!dp_deinit_s) begin
              dp_nxt = CMIS_DP_INIT;
              cnt_nxt = DLY[15:0];
            end
          end
          CMIS_DP_INIT: begin
            if (dp_deinit_s) begin
              dp_nxt = CMIS_DP_DEINIT;
              cnt_nxt = DLY[15:0];
            end else if (dp_cnt == 16'd0) begin
              dp_nxt = CMIS_DP_INITED;
            end else begin
              cnt_nxt = dp_cnt - 16'd1;
            end
          end
          CMIS_DP_INITED: begin
            if (dp_redeinit_s) begin
              dp_nxt = CMIS_DP_DEINIT;
              cnt_nxt = DLY[15:0];
            end else if (!dp_deactivate_s) begin
              dp_nxt = CMIS_DP_TXON;
              cnt_nxt = DLY[15:0];
            end
          end
          CMIS_DP_DEINIT: begin
            if (dp_cnt == 16'd0)
              dp_nxt = CMIS_DP_DEACT;
            else
              cnt_nxt = dp_cnt - 16'd1;
          end
          CMIS_DP_TXON: begin
            if (dp_deactivate_s) begin
              dp_nxt = CMIS_DP_TXOFF;
              cnt_nxt = DLY[15:0];
            end else if (dp_cnt == 16'd0) begin
              dp_nxt = CMIS_DP_ACT;
            end else begin
              cnt_nxt = dp_cnt - 16'd1;
            end
          end
          CMIS_DP_ACT: begin
            if (dp_deactivate_s) begin
              dp_nxt = CMIS_DP_TXOFF;
              cnt_nxt = DLY[15:0];
            end
          end
          CMIS_DP_TXOFF: begin
            if (dp_cnt == 16'd0)
              dp_nxt = CMIS_DP_INITED;
            else
              cnt_nxt = dp_cnt - 16'd1;
          end
          default: begin
            dp_nxt = CMIS_DP_DEACT;
            cnt_nxt = 16'd0;
          end
        endcase
        if (dp_nxt == CMIS_DP_INIT && dp_q != CMIS_DP_INIT)
          pend_nxt = 1'b0;
        if (dp_nxt != dp_q) begin
          if (dp_nxt == CMIS_DP_DEACT && dp_deinit_s)
            flag_set = 1'b1;
          if (dp_nxt == CMIS_DP_INITED && !dp_redeinit_s && dp_deactivate_s)
            flag_set = 1'b1;
          if (dp_nxt == CMIS_DP_ACT && !dp_deactivate_s)
            flag_set = 1'b1;
        end
      end
      dp_q <= dp_nxt;
      dp_cnt <= cnt_nxt;
      dp_pending <= pend_nxt;
      if (flag_set)
        dp_flag <= 1'b1;
      else if (dp_flag_clr)
        dp_flag <= 1'b0;
    end
  end

  // Level inputs hold the flag. A pulse stays latched until the host reads
  // that page 11h byte. The clear and a still-active input overlap, so the
  // flag does not drop for one poll.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      f_fail_tx <= 1'b0;
      f_los_tx  <= 1'b0;
      f_lol_tx  <= 1'b0;
      f_los_rx  <= 1'b0;
      f_lol_rx  <= 1'b0;
    end else begin
      f_fail_tx <= fail_tx || (f_fail_tx && !lane_clr[0]);
      f_los_tx  <= los_tx  || (f_los_tx  && !lane_clr[1]);
      f_lol_tx  <= lol_tx  || (f_lol_tx  && !lane_clr[2]);
      f_los_rx  <= los_rx  || (f_los_rx  && !lane_clr[3]);
      f_lol_rx  <= lol_rx  || (f_lol_rx  && !lane_clr[4]);
    end
  end
endmodule
