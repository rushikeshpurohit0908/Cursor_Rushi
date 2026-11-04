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
//     for lane 1. Other bits in that byte are preserved.
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
  input  logic        mod_prs_n,

  output logic        busy,
  output logic        present,
  output logic        nack,
  output logic        armed,
  output logic        low_pwr_rb,
  output logic        tx_disable_rb,
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

  output logic        scl_oe,
  output logic        sda_oe,
  input  logic        scl_i,
  input  logic        sda_i
);
  `include "fc_cmis.vh"

  localparam int GAPW = (GAP < 1) ? 1 : GAP;
  localparam [2:0] OP_RD26  = 3'd0;
  localparam [2:0] OP_WR26  = 3'd1;
  localparam [2:0] OP_PG    = 3'd2;
  localparam [2:0] OP_RD130 = 3'd3;
  localparam [2:0] OP_WR130 = 3'd4;
  localparam [2:0] OP_POLL  = 3'd5;

  logic        cmd_valid, cmd_ready, cmd_write, cmd_done, cmd_nack;
  logic [7:0]  cmd_addr, cmd_wdata, rx_data;
  logic [5:0]  cmd_rlen;
  logic        rx_valid;
  logic [4:0]  rx_index;
  logic [7:0]  cap [0:31];
  logic [2:0]  op;
  logic        launch, inflight, wait_gap;
  logic        ctrl_ok, tx_ok, sw_pend;
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

  function automatic [7:0] merge_tx(input [7:0] old, input logic dis);
    begin
      merge_tx = (old & 8'hFE) | (dis ? 8'h01 : 8'h00);
    end
  endfunction

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
      sw_pend   <= 1'b0;
      gapcnt    <= 16'd0;
      present   <= 1'b0;
      nack      <= 1'b0;
      low_pwr_rb <= 1'b0;
      tx_disable_rb <= 1'b0;
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
    end else begin
      if (rx_valid)
        cap[rx_index] <= rx_data;

      if (sw_reset_pulse)
        sw_pend <= 1'b1;

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
              cmd_wdata <= merge_tx(cap[0], tx_disable);
              cmd_rlen  <= 6'd1;
              launch    <= 1'b1;
            end
            OP_WR130: begin
              tx_disable_rb <= tx_disable;
              tx_ok         <= 1'b1;
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
