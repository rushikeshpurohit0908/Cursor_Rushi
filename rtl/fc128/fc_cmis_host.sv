// CMIS host for one SFP112 cage.
//
// The two-wire interface is the CMIS management interface (7-bit address
// 0x50). While poll_en is set and ModPrsL is low, the host does five things:
//   * read-modify-write lower byte 26 so LowPwrRequestSW follows low_pwr_sw
//     and a SoftwareReset pulse is a single write of bit 3. Bits 6 and 5
//     (LowPwrAllowRequestHW, SquelchMethodSelect) are left as the module
//     set them.
//   * select page 10h and read-modify-write byte 130 bit 0, OutputDisableTx
//     for lane 1, byte 132 bit 0, OutputSquelchForceTx, and byte 128 bit 0,
//     DPDeinit for lane 1. Other bits in those bytes are preserved.
//   * write page 10h byte 145 when the staged AppSel byte changes, then on
//     apply_pulse write byte 143 bit 0. Byte 143 is the write-only
//     ApplyDPInit trigger (single-byte write).
//   * select page 11h and read lane 1: DPState, OutputStatusRx,
//     OutputStatusTx, DPStateChangedFlag, DPInitPending, ConfigStatus,
//     and the active AppSel.
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
  input  logic        mod_prs_n,

  output logic        busy,
  output logic        present,
  output logic        nack,
  output logic        armed,
  output logic        low_pwr_rb,
  output logic        tx_disable_rb,
  output logic        tx_squelch_rb,
  output logic        dp_deinit_rb,
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
  output logic [3:0]  dp_state,
  output logic        rx_status,
  output logic        tx_status,
  output logic        dp_changed,
  output logic        dp_pending,
  output logic        lane_valid,
  output logic [3:0]  config_status,
  output logic [7:0]  active_appsel,

  output logic        scl_oe,
  output logic        sda_oe,
  input  logic        scl_i,
  input  logic        sda_i
);
  `include "fc_cmis.vh"

  localparam int GAPW = (GAP < 1) ? 1 : GAP;
  localparam [4:0] OP_RD26  = 5'd0;
  localparam [4:0] OP_WR26  = 5'd1;
  localparam [4:0] OP_PG    = 5'd2;
  localparam [4:0] OP_RD130 = 5'd3;
  localparam [4:0] OP_WR130 = 5'd4;
  localparam [4:0] OP_POLL  = 5'd5;
  localparam [4:0] OP_RD128 = 5'd6;
  localparam [4:0] OP_WR128 = 5'd7;
  localparam [4:0] OP_RD143 = 5'd8;
  localparam [4:0] OP_WR143 = 5'd9;
  localparam [4:0] OP_RD11  = 5'd10;
  localparam [4:0] OP_RD235 = 5'd11;
  localparam [4:0] OP_RD132 = 5'd12;
  localparam [4:0] OP_WR132 = 5'd13;
  localparam [4:0] OP_RD145 = 5'd14;
  localparam [4:0] OP_WR145 = 5'd15;
  localparam [4:0] OP_RD202 = 5'd16;
  localparam [4:0] OP_RD206 = 5'd17;

  logic        cmd_valid, cmd_ready, cmd_write, cmd_done, cmd_nack;
  logic [7:0]  cmd_addr, cmd_wdata, rx_data;
  logic [5:0]  cmd_rlen;
  logic        rx_valid;
  logic [4:0]  rx_index;
  logic [7:0]  cap [0:31];
  logic [4:0]  op, nxt;
  logic        launch, inflight, wait_gap;
  logic        ctrl_ok, tx_ok, sq_ok, deinit_ok, as_ok, lane_ok, sw_pend, apply_pend;
  logic [7:0]  as_rb;
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

  function automatic [7:0] merge_bit0(input [7:0] old, input logic ena);
    begin
      merge_bit0 = (old & 8'hFE) | (ena ? 8'h01 : 8'h00);
    end
  endfunction

  assign busy  = launch || inflight;
  assign armed = ctrl_ok && tx_ok && deinit_ok;

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
      nxt       <= OP_RD130;
      launch    <= 1'b0;
      inflight  <= 1'b0;
      wait_gap  <= 1'b0;
      ctrl_ok   <= 1'b0;
      tx_ok     <= 1'b0;
      sq_ok     <= 1'b0;
      deinit_ok <= 1'b0;
      as_ok     <= 1'b0;
      as_rb     <= 8'h00;
      lane_ok   <= 1'b0;
      sw_pend   <= 1'b0;
      apply_pend <= 1'b0;
      gapcnt    <= 16'd0;
      present   <= 1'b0;
      nack      <= 1'b0;
      low_pwr_rb <= 1'b0;
      tx_disable_rb <= 1'b0;
      tx_squelch_rb <= 1'b0;
      dp_deinit_rb <= 1'b0;
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
      dp_state <= 4'h0;
      rx_status <= 1'b0;
      tx_status <= 1'b0;
      dp_changed <= 1'b0;
      dp_pending <= 1'b0;
      lane_valid <= 1'b0;
      config_status <= 4'h0;
      active_appsel <= 8'h00;
    end else begin
      if (rx_valid)
        cap[rx_index] <= rx_data;

      if (sw_reset_pulse)
        sw_pend <= 1'b1;
      if (apply_pulse)
        apply_pend <= 1'b1;

      cmd_valid <= 1'b0;
      if (launch && cmd_ready) begin
        cmd_valid <= 1'b1;
        launch    <= 1'b0;
        inflight  <= 1'b1;
      end else if (cmd_done) begin
        inflight <= 1'b0;
        if (cmd_nack || mod_prs_n) begin
          nack      <= 1'b1;
          present   <= 1'b0;
          ctrl_ok   <= 1'b0;
          tx_ok     <= 1'b0;
          sq_ok     <= 1'b0;
          deinit_ok <= 1'b0;
          as_ok     <= 1'b0;
          lane_ok   <= 1'b0;
          lane_valid <= 1'b0;
          wait_gap  <= 1'b1;
          gapcnt    <= GAPW[15:0];
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
              op        <= nxt;
              cmd_write <= 1'b0;
              cmd_rlen  <= (nxt == OP_RD11) ? CMIS_DP_N : 6'd1;
              if (nxt == OP_RD128 || nxt == OP_RD11)
                cmd_addr <= CMIS_DPDEINIT;
              else if (nxt == OP_RD143)
                cmd_addr <= CMIS_APPLY;
              else if (nxt == OP_RD132)
                cmd_addr <= CMIS_SQFORCE;
              else if (nxt == OP_RD145)
                cmd_addr <= CMIS_SCS0;
              else
                cmd_addr <= CMIS_TXDIS;
              launch <= 1'b1;
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
            OP_RD132: begin
              op        <= OP_WR132;
              cmd_write <= 1'b1;
              cmd_addr  <= CMIS_SQFORCE;
              cmd_wdata <= merge_bit0(cap[0], tx_squelch);
              cmd_rlen  <= 6'd1;
              launch    <= 1'b1;
            end
            OP_WR132: begin
              tx_squelch_rb <= tx_squelch;
              sq_ok         <= 1'b1;
            end
            OP_RD128: begin
              if (cap[0][0] == dp_deinit) begin
                dp_deinit_rb <= dp_deinit;
                deinit_ok    <= 1'b1;
              end else begin
                op        <= OP_WR128;
                cmd_write <= 1'b1;
                cmd_addr  <= CMIS_DPDEINIT;
                cmd_wdata <= merge_bit0(cap[0], dp_deinit);
                cmd_rlen  <= 6'd1;
                launch    <= 1'b1;
              end
            end
            OP_WR128: begin
              dp_deinit_rb <= dp_deinit;
              deinit_ok    <= 1'b1;
            end
            OP_RD145: begin
              if (cap[0] == staged_appsel) begin
                as_rb <= staged_appsel;
                as_ok <= 1'b1;
              end else begin
                op        <= OP_WR145;
                cmd_write <= 1'b1;
                cmd_addr  <= CMIS_SCS0;
                cmd_wdata <= staged_appsel;
                cmd_rlen  <= 6'd1;
                launch    <= 1'b1;
              end
            end
            OP_WR145: begin
              as_rb <= staged_appsel;
              as_ok <= 1'b1;
            end
            OP_RD143: begin
              op        <= OP_WR143;
              cmd_write <= 1'b1;
              cmd_addr  <= CMIS_APPLY;
              cmd_wdata <= merge_bit0(cap[0], 1'b1);
              cmd_rlen  <= 6'd1;
              launch    <= 1'b1;
            end
            OP_WR143: begin
              if (!apply_pulse)
                apply_pend <= 1'b0;
            end
            OP_RD11: begin
              // Bytes 128..134. Lane 1 is the low nibble and bit 0.
              dp_state   <= cap[0][3:0];
              rx_status  <= cap[CMIS_OUTRX - CMIS_DPDEINIT][0];
              tx_status  <= cap[CMIS_OUTTX - CMIS_DPDEINIT][0];
              dp_changed <= cap[CMIS_DPFLAG - CMIS_DPDEINIT][0];
              op         <= OP_RD235;
              cmd_write  <= 1'b0;
              cmd_addr   <= CMIS_DPPEND;
              cmd_rlen   <= 6'd1;
              launch     <= 1'b1;
            end
            OP_RD235: begin
              dp_pending <= cap[0][0];
              op         <= OP_RD202;
              cmd_write  <= 1'b0;
              cmd_addr   <= CMIS_CFGSTAT;
              cmd_rlen   <= 6'd1;
              launch     <= 1'b1;
            end
            OP_RD202: begin
              config_status <= cap[0][3:0];
              op            <= OP_RD206;
              cmd_write     <= 1'b0;
              cmd_addr      <= CMIS_ACS0;
              cmd_rlen      <= 6'd1;
              launch        <= 1'b1;
            end
            OP_RD206: begin
              active_appsel <= cap[0];
              lane_valid    <= 1'b1;
              lane_ok       <= 1'b1;
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
              lane_ok        <= 1'b0;
              wait_gap       <= 1'b1;
              gapcnt         <= GAPW[15:0];
            end
            default: ;
          endcase
        end
      end else if (!inflight && !launch) begin
        if (mod_prs_n || !poll_en) begin
          if (mod_prs_n) begin
            present    <= 1'b0;
            ctrl_ok    <= 1'b0;
            tx_ok      <= 1'b0;
            sq_ok      <= 1'b0;
            deinit_ok  <= 1'b0;
            as_ok      <= 1'b0;
            lane_ok    <= 1'b0;
            lane_valid <= 1'b0;
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
          nxt       <= OP_RD130;
          cmd_write <= 1'b1;
          cmd_addr  <= CMIS_PAGE;
          cmd_wdata <= CMIS_LANE_PAGE;
          cmd_rlen  <= 6'd1;
          launch    <= 1'b1;
        end else if (!sq_ok || (tx_squelch != tx_squelch_rb)) begin
          op        <= OP_PG;
          nxt       <= OP_RD132;
          cmd_write <= 1'b1;
          cmd_addr  <= CMIS_PAGE;
          cmd_wdata <= CMIS_LANE_PAGE;
          cmd_rlen  <= 6'd1;
          launch    <= 1'b1;
        end else if (!deinit_ok || (dp_deinit != dp_deinit_rb)) begin
          op        <= OP_PG;
          nxt       <= OP_RD128;
          cmd_write <= 1'b1;
          cmd_addr  <= CMIS_PAGE;
          cmd_wdata <= CMIS_LANE_PAGE;
          cmd_rlen  <= 6'd1;
          launch    <= 1'b1;
        end else if (!as_ok || (staged_appsel != as_rb)) begin
          op        <= OP_PG;
          nxt       <= OP_RD145;
          cmd_write <= 1'b1;
          cmd_addr  <= CMIS_PAGE;
          cmd_wdata <= CMIS_LANE_PAGE;
          cmd_rlen  <= 6'd1;
          launch    <= 1'b1;
        end else if (apply_pend) begin
          op        <= OP_PG;
          nxt       <= OP_RD143;
          cmd_write <= 1'b1;
          cmd_addr  <= CMIS_PAGE;
          cmd_wdata <= CMIS_LANE_PAGE;
          cmd_rlen  <= 6'd1;
          launch    <= 1'b1;
        end else if (!lane_ok) begin
          op        <= OP_PG;
          nxt       <= OP_RD11;
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
