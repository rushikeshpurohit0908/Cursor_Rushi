// Behavioral SFP112 module on the CMIS two-wire interface.
//
// Lower memory follows CMIS 5.0. Byte 0 is SFF-8024 identifier 20h
// (SFP/SFP+ with CMIS). Byte 26 bit 4 is LowPwrRequestSW, bit 6 is
// LowPwrAllowRequestHW, and bit 3 is the self-clearing SoftwareReset.
// Page 10h byte 130 bit 0 is OutputDisableTx for lane 1. Byte 132 bit 0 is
// OutputSquelchForceTx. Byte 128 bit 0 is DPDeinit. Byte 145 is the staged
// AppSel for lane 1, and byte 143 bit 0 is the write-only ApplyDPInit
// trigger. Page 11h reports the data path state, output status, ConfigStatus,
// the active AppSel, and DPInitPending. The path steps forward only while
// the module is ModuleReady. OutputDisableTx or OutputSquelchForceTx holds
// the lane at DPInitialized. A valid ApplyDPInit copies the staged AppSel
// into the active set and, when the lane is already up, cycles it through
// DPDeactivated. Lane-1 FailureFlagTx, LOSFlagTx, CDRLOLFlagTx, LOSFlagRx,
// and CDRLOLFlagRx latch while the matching input is set and clear on read.
// Page 10h mask bit 0 gates each one out of the interrupt. IntL is active
// low. Page 11h bytes 154-155, 170-171, and 186-187 report lane-1
// OpticalPowerTx, LaserBiasTx, and OpticalPowerRx. Power counts 0.1 uW
// and bias counts 2 uA. The MSB is the lower address. A read leaves them
// unchanged. Bytes 139-146 and 149-152 latch when those monitors cross the
// page 02h thresholds: greater than a high threshold, or less than a low
// one. A read clears a latch whose comparison is no longer true. Page 10h
// bytes 218-225 and 228-231 mask those flags out of IntL. Temperature is
// signed 1/256 C at bytes 14-15. Supply is
// unsigned 100 uV at bytes 16-17. Byte 9 latches the module temperature
// and supply alarm/warning flags against the page 02h thresholds. A read
// clears a latch whose comparison is no longer true. Byte 32 masks those
// flags out of IntL and powers up at FFh. Byte 8 bit 0 is
// ModuleStateChangedFlag. It is set on entry to ModuleLowPwr, ModuleReady,
// or ModuleFault, unless that state is left immediately, and a read clears
// it. ModulePwrUp and ModulePwrDn do not set it. Byte 31 bit 0 masks it
// out of IntL and powers up at 1. Bytes 18-19 are Aux1 laser temperature,
// signed 1/256 C. Bytes 20-21 are Aux2 TEC current, signed 100/32767 percent.
// Byte 10 latches the eight high/low alarm and warning flags for those
// monitors. A read clears a latch whose comparison is no longer true. A
// negative TEC current does not set a high alarm. Byte 33 masks those flags
// out of IntL and powers up at FFh. Bytes 22-23 are Aux3 additional supply
// Vcc2, signed 100 uV. Bytes 24-25 are Custom laser frequency error, signed
// 1 MHz. Byte 11 latches the eight high/low alarm and warning flags for
// those monitors. A read clears a latch whose comparison is no longer true.
// A negative Vcc2 or frequency error does not set a high alarm. Byte 34
// masks those flags out of IntL and powers up at FFh. Page 00h bytes
// 128-143 and 148-163 are VendorName and VendorPN. Both are fixed
// space-padded strings, and a write does not change them. The slave does
// not stretch SCL. sda_oe drives a zero on the open-drain pad.
module cmis_sfp_slave #(
  parameter int PWR_DLY = 40,
  parameter [7:0] TXDIS_INIT = 8'hA0
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        scl_i,
  input  logic        sda_i,
  output logic        sda_oe,
  input  logic        lpmode,
  input  logic        reset_n,
  input  logic        force_fault,
  input  logic [15:0] temp_s16,
  input  logic [15:0] vcc_u16,
  input  logic [15:0] opt_tx_u16,
  input  logic [15:0] bias_tx_u16,
  input  logic [15:0] opt_rx_u16,
  input  logic [15:0] aux1_s16,
  input  logic [15:0] aux2_s16,
  input  logic [15:0] aux3_s16,
  input  logic [15:0] cust_s16,
  input  logic        tx_fail,
  input  logic        los_tx,
  input  logic        lol_tx,
  input  logic        los_rx,
  input  logic        lol_rx,
  output logic        int_n,
  output logic [2:0]  mod_state,
  output logic [7:0]  txdis_byte,
  output logic        flag_state,
  output logic [3:0]  dp_state,
  output logic [7:0]  dpdeinit_byte,
  output logic [3:0]  config_status,
  output logic [7:0]  active_appsel,
  output logic        dp_init_pend,
  output logic        out_status_rx,
  output logic        out_status_tx,
  output logic        dp_flag,
  output logic [7:0]  squelch_byte
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
  logic       fail_clr, los_tx_clr, lol_tx_clr, los_rx_clr, lol_rx_clr;
  logic       fail_f, los_tx_f, lol_tx_f, los_rx_f, lol_rx_f;
  logic [11:0] alm_f, alm_clr;
  logic [7:0]  mon_f;
  logic        mon_clr;
  logic [7:0]  aux_f;
  logic        aux_clr;
  logic [7:0]  a3_f;
  logic        a3_clr;
  integer      alm_seen;
  logic       sw_hit;
  logic       sw_resetting;
  logic       held;
  logic       raise_flag;
  logic [2:0] mod_state_q;
  logic [3:0] dp_q;
  logic [3:0] dp_prev;
  logic [15:0] dp_cnt;
  logic [15:0] pwr_cnt;
  logic [3:0] cfg_q;
  logic [15:0] cfg_cnt;
  logic [7:0] cfg_snap;
  logic [7:0] active_sel;
  logic       init_pend;
  logic       reinit;
  logic       apply_hit;
  logic       dp_flag_clr;
  integer ii;

  wire tx_mute = p10[CMIS_TXDIS][0] | p10[CMIS_SQFORCE][0];
  wire rx_up = (dp_q == CMIS_DP_INITD) || (dp_q == CMIS_DP_TXON) ||
               (dp_q == CMIS_DP_ACT) || (dp_q == CMIS_DP_TXOFF);

  wire start = scl_q && scl_i && sda_q && !sda_i;
  wire stop  = scl_q && scl_i && !sda_q && sda_i;
  wire rise  = !scl_q && scl_i;
  wire fall  = scl_q && !scl_i;
  wire lowpwr_s = mem[CMIS_CTL][4] | (mem[CMIS_CTL][6] & lpmode);
  // flag_alm / mask_alm bit order: Tx HA, LA, HW, LW, bias HA, LA, HW, LW,
  // then Rx HA, LA, HW, LW.
  wire [11:0] alm_cond = {
    opt_rx_u16 < CMIS_RX_LW, opt_rx_u16 > CMIS_RX_HW,
    opt_rx_u16 < CMIS_RX_LA, opt_rx_u16 > CMIS_RX_HA,
    bias_tx_u16 < CMIS_BI_LW, bias_tx_u16 > CMIS_BI_HW,
    bias_tx_u16 < CMIS_BI_LA, bias_tx_u16 > CMIS_BI_HA,
    opt_tx_u16 < CMIS_TX_LW, opt_tx_u16 > CMIS_TX_HW,
    opt_tx_u16 < CMIS_TX_LA, opt_tx_u16 > CMIS_TX_HA
  };
  wire signed [15:0] temp_cmp = temp_s16;
  // Byte 9: Temp HA, LA, HW, LW, then Vcc HA, LA, HW, LW.
  wire [7:0] mon_cond = {
    temp_cmp > CMIS_TEMP_HA, temp_cmp < CMIS_TEMP_LA,
    temp_cmp > CMIS_TEMP_HW, temp_cmp < CMIS_TEMP_LW,
    vcc_u16 > CMIS_VCC_HA, vcc_u16 < CMIS_VCC_LA,
    vcc_u16 > CMIS_VCC_HW, vcc_u16 < CMIS_VCC_LW
  };
  wire signed [15:0] aux1_cmp = aux1_s16;
  wire signed [15:0] aux2_cmp = aux2_s16;
  // Byte 10: Aux1 HA, LA, HW, LW, then Aux2 HA, LA, HW, LW.
  wire [7:0] aux_cond = {
    aux1_cmp > CMIS_AUX1_HA, aux1_cmp < CMIS_AUX1_LA,
    aux1_cmp > CMIS_AUX1_HW, aux1_cmp < CMIS_AUX1_LW,
    aux2_cmp > CMIS_AUX2_HA, aux2_cmp < CMIS_AUX2_LA,
    aux2_cmp > CMIS_AUX2_HW, aux2_cmp < CMIS_AUX2_LW
  };
  wire signed [15:0] aux3_cmp = aux3_s16;
  wire signed [15:0] cust_cmp = cust_s16;
  // Byte 11: Aux3 HA, LA, HW, LW, then Custom HA, LA, HW, LW.
  wire [7:0] a3_cond = {
    aux3_cmp > CMIS_AUX3_HA, aux3_cmp < CMIS_AUX3_LA,
    aux3_cmp > CMIS_AUX3_HW, aux3_cmp < CMIS_AUX3_LW,
    cust_cmp > CMIS_CUST_HA, cust_cmp < CMIS_CUST_LA,
    cust_cmp > CMIS_CUST_HW, cust_cmp < CMIS_CUST_LW
  };
  wire mon_hot = |(mon_f & ~mem[CMIS_MSK_MON]);
  wire aux_hot = |(aux_f & ~mem[CMIS_MSK_AUX]);
  wire a3_hot = |(a3_f & ~mem[CMIS_MSK_A3]);
  wire [11:0] alm_msk = {
    p10[CMIS_MSK_RX_LW][0], p10[CMIS_MSK_RX_HW][0],
    p10[CMIS_MSK_RX_LA][0], p10[CMIS_MSK_RX_HA][0],
    p10[CMIS_MSK_BI_LW][0], p10[CMIS_MSK_BI_HW][0],
    p10[CMIS_MSK_BI_LA][0], p10[CMIS_MSK_BI_HA][0],
    p10[CMIS_MSK_TX_LW][0], p10[CMIS_MSK_TX_HW][0],
    p10[CMIS_MSK_TX_LA][0], p10[CMIS_MSK_TX_HA][0]
  };
  wire lane_hot = (fail_f & ~p10[CMIS_MSK_FAIL][0]) |
                  (los_tx_f & ~p10[CMIS_MSK_LOSTX][0]) |
                  (lol_tx_f & ~p10[CMIS_MSK_LOLTX][0]) |
                  (los_rx_f & ~p10[CMIS_MSK_LOSRX][0]) |
                  (lol_rx_f & ~p10[CMIS_MSK_LOLRX][0]) |
                  |(alm_f & ~alm_msk);
  wire int_deassert = !((flag_sc && !mem[CMIS_MSK_SC][0]) || lane_hot || mon_hot || aux_hot || a3_hot);
  assign int_n = int_deassert;

  assign txdis_byte = p10[CMIS_TXDIS];
  assign flag_state = flag_sc;
  assign dp_state = dp_q;
  assign dpdeinit_byte = p10[CMIS_DPDEINIT];
  assign config_status = cfg_q;
  assign active_appsel = active_sel;
  assign dp_init_pend = init_pend;
  assign out_status_rx = rx_up;
  assign out_status_tx = (dp_q == CMIS_DP_ACT) && !tx_mute;
  assign squelch_byte = p10[CMIS_SQFORCE];
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

  task automatic note_cor;
    input [7:0] a;
    begin
      if (a == CMIS_MOD_FLG)
        flag_clr <= 1'b1;
      if (a == CMIS_MON_FLG)
        mon_clr <= 1'b1;
      if (a == CMIS_AUX_FLG)
        aux_clr <= 1'b1;
      if (a == CMIS_A3_FLG)
        a3_clr <= 1'b1;
      if (mem[CMIS_PAGE] == CMIS_STAT_PAGE) begin
        if (a == CMIS_DPFLAG)
          dp_flag_clr <= 1'b1;
        else if (a == CMIS_FAILTX)
          fail_clr <= 1'b1;
        else if (a == CMIS_LOSTX)
          los_tx_clr <= 1'b1;
        else if (a == CMIS_LOLTX)
          lol_tx_clr <= 1'b1;
        else if (a == CMIS_LOSRX)
          los_rx_clr <= 1'b1;
        else if (a == CMIS_LOLRX)
          lol_rx_clr <= 1'b1;
        else if (alm_bit(a) != 4'hF)
          alm_seen = alm_bit(a);
      end
    end
  endtask

  function automatic [3:0] alm_bit(input [7:0] a);
    begin
      if (a >= CMIS_ALM_TX && a < CMIS_ALM_TX + 8'd8)
        alm_bit = 4'(a - CMIS_ALM_TX);
      else if (a >= CMIS_ALM_RX && a < CMIS_ALM_RX + 8'd4)
        alm_bit = 4'd8 + 4'(a - CMIS_ALM_RX);
      else
        alm_bit = 4'hF;
    end
  endfunction

  function automatic [15:0] thresh_word(input [7:0] a);
    begin
      case (a)
        CMIS_TH_T_HA:  thresh_word = CMIS_TEMP_HA;
        CMIS_TH_T_LA:  thresh_word = CMIS_TEMP_LA;
        CMIS_TH_T_HW:  thresh_word = CMIS_TEMP_HW;
        CMIS_TH_T_LW:  thresh_word = CMIS_TEMP_LW;
        CMIS_TH_V_HA:  thresh_word = CMIS_VCC_HA;
        CMIS_TH_V_LA:  thresh_word = CMIS_VCC_LA;
        CMIS_TH_V_HW:  thresh_word = CMIS_VCC_HW;
        CMIS_TH_V_LW:  thresh_word = CMIS_VCC_LW;
        CMIS_TH_A1_HA: thresh_word = CMIS_AUX1_HA;
        CMIS_TH_A1_LA: thresh_word = CMIS_AUX1_LA;
        CMIS_TH_A1_HW: thresh_word = CMIS_AUX1_HW;
        CMIS_TH_A1_LW: thresh_word = CMIS_AUX1_LW;
        CMIS_TH_A2_HA: thresh_word = CMIS_AUX2_HA;
        CMIS_TH_A2_LA: thresh_word = CMIS_AUX2_LA;
        CMIS_TH_A2_HW: thresh_word = CMIS_AUX2_HW;
        CMIS_TH_A2_LW: thresh_word = CMIS_AUX2_LW;
        CMIS_TH_A3_HA: thresh_word = CMIS_AUX3_HA;
        CMIS_TH_A3_LA: thresh_word = CMIS_AUX3_LA;
        CMIS_TH_A3_HW: thresh_word = CMIS_AUX3_HW;
        CMIS_TH_A3_LW: thresh_word = CMIS_AUX3_LW;
        CMIS_TH_CU_HA: thresh_word = CMIS_CUST_HA;
        CMIS_TH_CU_LA: thresh_word = CMIS_CUST_LA;
        CMIS_TH_CU_HW: thresh_word = CMIS_CUST_HW;
        CMIS_TH_CU_LW: thresh_word = CMIS_CUST_LW;
        CMIS_TH_TX_HA: thresh_word = CMIS_TX_HA;
        CMIS_TH_TX_LA: thresh_word = CMIS_TX_LA;
        CMIS_TH_TX_HW: thresh_word = CMIS_TX_HW;
        CMIS_TH_TX_LW: thresh_word = CMIS_TX_LW;
        CMIS_TH_BI_HA: thresh_word = CMIS_BI_HA;
        CMIS_TH_BI_LA: thresh_word = CMIS_BI_LA;
        CMIS_TH_BI_HW: thresh_word = CMIS_BI_HW;
        CMIS_TH_BI_LW: thresh_word = CMIS_BI_LW;
        CMIS_TH_RX_HA: thresh_word = CMIS_RX_HA;
        CMIS_TH_RX_LA: thresh_word = CMIS_RX_LA;
        CMIS_TH_RX_HW: thresh_word = CMIS_RX_HW;
        CMIS_TH_RX_LW: thresh_word = CMIS_RX_LW;
        default:       thresh_word = 16'h0000;
      endcase
    end
  endfunction

  task automatic arm_alm_clr;
    begin
      case (alm_seen)
        0: alm_clr <= 12'h001;
        1: alm_clr <= 12'h002;
        2: alm_clr <= 12'h004;
        3: alm_clr <= 12'h008;
        4: alm_clr <= 12'h010;
        5: alm_clr <= 12'h020;
        6: alm_clr <= 12'h040;
        7: alm_clr <= 12'h080;
        8: alm_clr <= 12'h100;
        9: alm_clr <= 12'h200;
        10: alm_clr <= 12'h400;
        11: alm_clr <= 12'h800;
        default: alm_clr <= 12'h000;
      endcase
    end
  endtask

  function automatic [7:0] vend_at(input [127:0] word, input [7:0] off);
    integer bitidx;
    begin
      bitidx = 127 - 8 * off;
      vend_at = word[bitidx -: 8];
    end
  endfunction

  function automatic [7:0] peek(input [7:0] a);
    reg [15:0] tw;
    reg [3:0]  ab;
    begin
      if (a == 8'd3)
        peek = {4'b0, (force_fault ? CMIS_ST_FLT : (sw_resetting ? CMIS_ST_LOW : mod_state_q)), int_deassert};
      else if (a == CMIS_MOD_FLG)
        peek = {7'b0, flag_sc};
      else if (a == CMIS_MON_FLG)
        peek = mon_f;
      else if (a == CMIS_AUX_FLG)
        peek = aux_f;
      else if (a == CMIS_A3_FLG)
        peek = a3_f;
      else if (a == 8'd14)
        peek = temp_s16[15:8];
      else if (a == 8'd15)
        peek = temp_s16[7:0];
      else if (a == 8'd16)
        peek = vcc_u16[15:8];
      else if (a == 8'd17)
        peek = vcc_u16[7:0];
      else if (a == CMIS_AUX1_MON)
        peek = aux1_s16[15:8];
      else if (a == CMIS_AUX1_MON + 8'd1)
        peek = aux1_s16[7:0];
      else if (a == CMIS_AUX2_MON)
        peek = aux2_s16[15:8];
      else if (a == CMIS_AUX2_MON + 8'd1)
        peek = aux2_s16[7:0];
      else if (a == CMIS_AUX3_MON)
        peek = aux3_s16[15:8];
      else if (a == CMIS_AUX3_MON + 8'd1)
        peek = aux3_s16[7:0];
      else if (a == CMIS_CUST_MON)
        peek = cust_s16[15:8];
      else if (a == CMIS_CUST_MON + 8'd1)
        peek = cust_s16[7:0];
      else if (mem[CMIS_PAGE] == CMIS_VEND_PAGE &&
               a >= CMIS_VNAME && a < CMIS_VNAME + 8'd16)
        peek = vend_at(CMIS_VENDOR_NAME, a - CMIS_VNAME);
      else if (mem[CMIS_PAGE] == CMIS_VEND_PAGE &&
               a >= CMIS_VPN && a < CMIS_VPN + 8'd16)
        peek = vend_at(CMIS_VENDOR_PN, a - CMIS_VPN);
      else if (a < 8'd128)
        peek = mem[a];
      else if (mem[CMIS_PAGE] == CMIS_LANE_PAGE)
        peek = p10[a];
      else if (mem[CMIS_PAGE] == CMIS_STAT_PAGE && a == CMIS_DPDEINIT)
        peek = {4'h0, dp_q};
      else if (mem[CMIS_PAGE] == CMIS_STAT_PAGE && a == CMIS_OUTRX)
        peek = {7'h0, rx_up};
      else if (mem[CMIS_PAGE] == CMIS_STAT_PAGE && a == CMIS_OUTTX)
        peek = {7'h0, (dp_q == CMIS_DP_ACT) && !tx_mute};
      else if (mem[CMIS_PAGE] == CMIS_STAT_PAGE && a == CMIS_DPFLAG)
        peek = {7'h0, dp_flag};
      else if (mem[CMIS_PAGE] == CMIS_STAT_PAGE && a == CMIS_FAILTX)
        peek = {7'h0, fail_f};
      else if (mem[CMIS_PAGE] == CMIS_STAT_PAGE && a == CMIS_LOSTX)
        peek = {7'h0, los_tx_f};
      else if (mem[CMIS_PAGE] == CMIS_STAT_PAGE && a == CMIS_LOLTX)
        peek = {7'h0, lol_tx_f};
      else if (mem[CMIS_PAGE] == CMIS_STAT_PAGE && a == CMIS_LOSRX)
        peek = {7'h0, los_rx_f};
      else if (mem[CMIS_PAGE] == CMIS_STAT_PAGE && a == CMIS_LOLRX)
        peek = {7'h0, lol_rx_f};
      else if (mem[CMIS_PAGE] == CMIS_STAT_PAGE && alm_bit(a) != 4'hF) begin
        ab = alm_bit(a);
        peek = {7'h0, alm_f[ab]};
      end       else if (mem[CMIS_PAGE] == CMIS_TH_PAGE && a >= CMIS_TH_T_HA &&
                   a <= CMIS_TH_RX_LW + 8'd1) begin
        tw = a[0] ? thresh_word(a - 8'd1) : thresh_word(a);
        peek = a[0] ? tw[7:0] : tw[15:8];
      end
      else if (mem[CMIS_PAGE] == CMIS_STAT_PAGE && a == CMIS_OPT_TX)
        peek = opt_tx_u16[15:8];
      else if (mem[CMIS_PAGE] == CMIS_STAT_PAGE && a == CMIS_OPT_TX + 8'd1)
        peek = opt_tx_u16[7:0];
      else if (mem[CMIS_PAGE] == CMIS_STAT_PAGE && a == CMIS_BIAS_TX)
        peek = bias_tx_u16[15:8];
      else if (mem[CMIS_PAGE] == CMIS_STAT_PAGE && a == CMIS_BIAS_TX + 8'd1)
        peek = bias_tx_u16[7:0];
      else if (mem[CMIS_PAGE] == CMIS_STAT_PAGE && a == CMIS_OPT_RX)
        peek = opt_rx_u16[15:8];
      else if (mem[CMIS_PAGE] == CMIS_STAT_PAGE && a == CMIS_OPT_RX + 8'd1)
        peek = opt_rx_u16[7:0];
      else if (mem[CMIS_PAGE] == CMIS_STAT_PAGE && a == CMIS_CFGSTAT)
        peek = {4'h0, cfg_q};
      else if (mem[CMIS_PAGE] == CMIS_STAT_PAGE && a == CMIS_ACS0)
        peek = active_sel;
      else if (mem[CMIS_PAGE] == CMIS_STAT_PAGE && a == CMIS_DPPEND)
        peek = {7'h0, init_pend};
      else
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
      mem[CMIS_MSK_SC] <= 8'hFF;
      mem[CMIS_MSK_MON] <= 8'hFF;
      mem[CMIS_MSK_AUX] <= 8'hFF;
      mem[CMIS_MSK_A3] <= 8'hFF;
      mem[CMIS_PAGE] <= 8'h00;
      mem[CMIS_APP_BASE]     <= CMIS_H_128;
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
      p10[CMIS_SQFORCE] <= 8'hA0;
      p10[CMIS_DPDEINIT] <= 8'hFF;
      p10[CMIS_SCS0] <= CMIS_APP_128;
      p10[CMIS_MSK_FAIL] <= 8'hFF;
      p10[CMIS_MSK_LOSTX] <= 8'hFF;
      p10[CMIS_MSK_LOLTX] <= 8'hFF;
      p10[CMIS_MSK_TX_HA] <= 8'hFF;
      p10[CMIS_MSK_TX_LA] <= 8'hFF;
      p10[CMIS_MSK_TX_HW] <= 8'hFF;
      p10[CMIS_MSK_TX_LW] <= 8'hFF;
      p10[CMIS_MSK_BI_HA] <= 8'hFF;
      p10[CMIS_MSK_BI_LA] <= 8'hFF;
      p10[CMIS_MSK_BI_HW] <= 8'hFF;
      p10[CMIS_MSK_BI_LW] <= 8'hFF;
      p10[CMIS_MSK_LOSRX] <= 8'hFF;
      p10[CMIS_MSK_LOLRX] <= 8'hFF;
      p10[CMIS_MSK_RX_HA] <= 8'hFF;
      p10[CMIS_MSK_RX_LA] <= 8'hFF;
      p10[CMIS_MSK_RX_HW] <= 8'hFF;
      p10[CMIS_MSK_RX_LW] <= 8'hFF;
      alm_clr <= 12'h000;
      mon_clr <= 1'b0;
      aux_clr <= 1'b0;
      a3_clr <= 1'b0;
      alm_seen = -1;
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
      dp_flag_clr <= 1'b0;
      fail_clr <= 1'b0;
      los_tx_clr <= 1'b0;
      lol_tx_clr <= 1'b0;
      los_rx_clr <= 1'b0;
      lol_rx_clr <= 1'b0;
      sw_hit <= 1'b0;
      apply_hit <= 1'b0;
    end else begin
      alm_seen = -1;
      scl_q <= scl_i;
      sda_q <= sda_i;
      flag_clr <= 1'b0;
      dp_flag_clr <= 1'b0;
      fail_clr <= 1'b0;
      los_tx_clr <= 1'b0;
      lol_tx_clr <= 1'b0;
      los_rx_clr <= 1'b0;
      lol_rx_clr <= 1'b0;
      mon_clr <= 1'b0;
      aux_clr <= 1'b0;
      a3_clr <= 1'b0;
      sw_hit <= 1'b0;
      apply_hit <= 1'b0;
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
                  // Write-only trigger. A read of this byte stays zero.
                  if (sh[0])
                    apply_hit <= 1'b1;
                  ptr <= ptr + 8'd1;
                end else if (mem[CMIS_PAGE] == CMIS_LANE_PAGE) begin
                  p10[ptr] <= sh;
                  ptr <= ptr + 8'd1;
                end else if (mem[CMIS_PAGE] == CMIS_VEND_PAGE) begin
                  // VendorName and VendorPN are fixed. A write does not stick.
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
                note_cor(ptr);
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
                note_cor(ptr);
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
      arm_alm_clr();
    end
  end

  function automatic logic dp_steady(input [3:0] s);
    begin
      dp_steady = (s == CMIS_DP_DEACT) || (s == CMIS_DP_DEINIT) ||
                  (s == CMIS_DP_ACT) || (s == CMIS_DP_INITD);
    end
  endfunction

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      mod_state_q <= CMIS_ST_LOW;
      dp_q <= CMIS_DP_DEACT;
      dp_prev <= CMIS_DP_DEACT;
      dp_cnt <= 16'd0;
      flag_sc <= 1'b0;
      dp_flag <= 1'b0;
      fail_f <= 1'b0;
      los_tx_f <= 1'b0;
      lol_tx_f <= 1'b0;
      los_rx_f <= 1'b0;
      lol_rx_f <= 1'b0;
      alm_f <= 12'h000;
      mon_f <= 8'h00;
      aux_f <= 8'h00;
      a3_f <= 8'h00;
      sw_resetting <= 1'b0;
      held <= 1'b0;
      pwr_cnt <= 16'd0;
      cfg_q <= CMIS_CFG_NONE;
      cfg_cnt <= 16'd0;
      cfg_snap <= 8'h00;
      active_sel <= CMIS_APP_128;
      init_pend <= 1'b0;
      reinit <= 1'b0;
    end else if (!reset_n) begin
      mod_state_q <= CMIS_ST_LOW;
      sw_resetting <= 1'b0;
      pwr_cnt <= 16'd0;
      held <= 1'b1;
      cfg_q <= CMIS_CFG_NONE;
      cfg_cnt <= 16'd0;
      active_sel <= CMIS_APP_128;
      init_pend <= 1'b0;
      reinit <= 1'b0;
      dp_flag <= 1'b0;
      fail_f <= 1'b0;
      los_tx_f <= 1'b0;
      lol_tx_f <= 1'b0;
      los_rx_f <= 1'b0;
      lol_rx_f <= 1'b0;
      alm_f <= 12'h000;
      mon_f <= 8'h00;
      aux_f <= 8'h00;
      a3_f <= 8'h00;
    end else begin
      raise_flag = 1'b0;
      if (sw_hit) begin
        sw_resetting <= 1'b1;
        pwr_cnt <= PWR_DLY[15:0];
        cfg_q <= CMIS_CFG_NONE;
        cfg_cnt <= 16'd0;
        active_sel <= CMIS_APP_128;
        init_pend <= 1'b0;
        reinit <= 1'b0;
        fail_f <= 1'b0;
        los_tx_f <= 1'b0;
        lol_tx_f <= 1'b0;
        los_rx_f <= 1'b0;
        lol_rx_f <= 1'b0;
        alm_f <= 12'h000;
        mon_f <= 8'h00;
        aux_f <= 8'h00;
      a3_f <= 8'h00;
      end else if (sw_resetting) begin
        if (pwr_cnt == 16'd0) begin
          sw_resetting <= 1'b0;
          mod_state_q <= CMIS_ST_LOW;
          // LowPwrS already false means this state is left at once.
          raise_flag = lowpwr_s;
        end else begin
          pwr_cnt <= pwr_cnt - 16'd1;
        end
      end else if (force_fault) begin
        if (mod_state_q != CMIS_ST_FLT)
          raise_flag = 1'b1;
        mod_state_q <= CMIS_ST_FLT;
      end else if (held) begin
        held <= 1'b0;
        raise_flag = lowpwr_s;
        mod_state_q <= CMIS_ST_LOW;
      end else if (mod_state_q == CMIS_ST_FLT) begin
        mod_state_q <= CMIS_ST_LOW;
        raise_flag = lowpwr_s;
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
              // LowPwrExS is LowPwrS with every data path already down.
              raise_flag = !(lowpwr_s && (dp_q == CMIS_DP_DEACT));
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
              raise_flag = lowpwr_s;
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

      // ApplyDPInit. ConfigInProgress holds for one power dwell so a host
      // can observe it, then the staged byte is checked. AppSel 1..3 with
      // DataPathID 0 is lane 1 of an advertised one-lane application.
      // Anything else is rejected and the active set is left alone. A second
      // trigger during ConfigInProgress is ignored. Success copies the byte
      // into the active set, sets DPInitPending, and cycles a live lane
      // through DPDeactivated. Pending clears on the way into DPInit.
      if (!sw_hit && apply_hit && cfg_q != CMIS_CFG_BUSY) begin
        cfg_q <= CMIS_CFG_BUSY;
        cfg_cnt <= PWR_DLY[15:0];
        cfg_snap <= p10[CMIS_SCS0];
      end else if (!sw_hit && cfg_q == CMIS_CFG_BUSY) begin
        if (cfg_cnt != 16'd0) begin
          cfg_cnt <= cfg_cnt - 16'd1;
        end else if (sw_resetting || force_fault || (mod_state_q != CMIS_ST_RDY)) begin
          cfg_q <= CMIS_CFG_REJ;
        end else if ((cfg_snap[7:4] == 4'h0) || (cfg_snap[7:4] > 4'h3)) begin
          cfg_q <= CMIS_CFG_APP;
        end else if (cfg_snap[3:1] != 3'd0) begin
          cfg_q <= CMIS_CFG_DP;
        end else begin
          active_sel <= cfg_snap;
          cfg_q <= CMIS_CFG_OK;
          init_pend <= 1'b1;
          if (dp_q != CMIS_DP_DEACT)
            reinit <= 1'b1;
        end
      end

      // Lane 1 data path. A module that is not ModuleReady reports
      // DPDeactivated. DPDeinit holds the lane down. With DPDeinit clear,
      // the lane reaches DPInitialized, and then DPActivated unless
      // OutputDisableTx or OutputSquelchForceTx is set.
      if (sw_resetting || force_fault || (mod_state_q != CMIS_ST_RDY)) begin
        dp_q   <= CMIS_DP_DEACT;
        dp_cnt <= 16'd0;
        reinit <= 1'b0;
        init_pend <= 1'b0;
      end else if (reinit) begin
        if (dp_cnt != 16'd0) begin
          dp_cnt <= dp_cnt - 16'd1;
        end else begin
          dp_cnt <= PWR_DLY[15:0];
          if (dp_q == CMIS_DP_DEACT)
            reinit <= 1'b0;
          else if (dp_q == CMIS_DP_ACT || dp_q == CMIS_DP_TXON)
            dp_q <= CMIS_DP_TXOFF;
          else
            dp_q <= CMIS_DP_DEACT;
        end
      end else if (dp_cnt != 16'd0) begin
        dp_cnt <= dp_cnt - 16'd1;
      end else begin
        dp_cnt <= PWR_DLY[15:0];
        if (p10[CMIS_DPDEINIT][0]) begin
          if (dp_q == CMIS_DP_DEACT || dp_q == CMIS_DP_DEINIT)
            dp_q <= CMIS_DP_DEACT;
          else
            dp_q <= CMIS_DP_DEINIT;
        end else begin
          case (dp_q)
            CMIS_DP_DEACT: begin
              dp_q <= CMIS_DP_INIT;
              init_pend <= 1'b0;
            end
            CMIS_DP_INIT:   dp_q <= CMIS_DP_INITD;
            CMIS_DP_DEINIT: dp_q <= CMIS_DP_DEACT;
            CMIS_DP_INITD:  dp_q <= tx_mute ? CMIS_DP_INITD : CMIS_DP_TXON;
            CMIS_DP_TXON:   dp_q <= tx_mute ? CMIS_DP_TXOFF : CMIS_DP_ACT;
            CMIS_DP_ACT:    dp_q <= tx_mute ? CMIS_DP_TXOFF : CMIS_DP_ACT;
            CMIS_DP_TXOFF:  dp_q <= CMIS_DP_INITD;
            default:        dp_q <= CMIS_DP_DEACT;
          endcase
        end
      end

      if (dp_flag_clr)
        dp_flag <= 1'b0;
      if ((dp_q != dp_prev) && dp_steady(dp_q))
        dp_flag <= 1'b1;
      dp_prev <= dp_q;

      // Level-sensitive while the input is set, and held after it drops
      // until the host reads the byte. A read while the input is still set
      // leaves the flag set. Software reset drops the latches.
      if (!sw_hit) begin
        if (tx_fail)
          fail_f <= 1'b1;
        else if (fail_clr)
          fail_f <= 1'b0;
        if (los_tx)
          los_tx_f <= 1'b1;
        else if (los_tx_clr)
          los_tx_f <= 1'b0;
        if (lol_tx)
          lol_tx_f <= 1'b1;
        else if (lol_tx_clr)
          lol_tx_f <= 1'b0;
        if (los_rx)
          los_rx_f <= 1'b1;
        else if (los_rx_clr)
          los_rx_f <= 1'b0;
        if (lol_rx)
          lol_rx_f <= 1'b1;
        else if (lol_rx_clr)
          lol_rx_f <= 1'b0;
        for (ii = 0; ii < 12; ii = ii + 1) begin
          if (alm_cond[ii])
            alm_f[ii] <= 1'b1;
          else if (alm_clr[ii])
            alm_f[ii] <= 1'b0;
        end
        for (ii = 0; ii < 8; ii = ii + 1) begin
          if (mon_cond[ii])
            mon_f[ii] <= 1'b1;
          else if (mon_clr)
            mon_f[ii] <= 1'b0;
        end
        for (ii = 0; ii < 8; ii = ii + 1) begin
          if (aux_cond[ii])
            aux_f[ii] <= 1'b1;
          else if (aux_clr)
            aux_f[ii] <= 1'b0;
        end
        for (ii = 0; ii < 8; ii = ii + 1) begin
          if (a3_cond[ii])
            a3_f[ii] <= 1'b1;
          else if (a3_clr)
            a3_f[ii] <= 1'b0;
        end
      end
    end
  end
endmodule
