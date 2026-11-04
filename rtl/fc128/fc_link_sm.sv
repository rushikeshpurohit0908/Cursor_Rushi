// Link initialization for one FC128 bridge link.
//
// Ordered sets are the FC-FS words in fc128_defs.vh (first character in [7:0]).
// Bring-up follows the usual FC port sequence
// (OLS -> LR -> LRR -> Idle -> Active). A peer that is already sending Idle
// also reaches Active, so a testbench that only sources Idle still links up.
//
// The sequence is safe on a delayed loopback. Primitives that belong to an
// earlier state are ignored, so a stale OLS sitting in the gearbox cannot
// pull the state backward. One NOS drops the link back to OLS.
module fc_link_sm #(
  parameter int STREAK = 4
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        port_en,
  input  logic        locked,
  input  logic        rx_fire,
  input  logic [1:0]  rx_sync,
  input  logic [63:0] rx_data,
  output logic        link_up,
  output logic [31:0] tx_os,
  output logic [2:0]  state_code
);
  `include "fc128_defs.vh"

  logic [2:0]  st;
  logic [7:0]  streak;
  logic [31:0] streak_os;

  function automatic [2:0] advance(input [2:0] cur, input [31:0] os);
    begin
      advance = cur;
      if (os == FC_IDLE) begin
        if (cur == FC_LS_ACQ)
          advance = FC_LS_ACT;
        else if (cur != FC_LS_ACT)
          advance = FC_LS_ACQ;
      end else if (os == FC_OLS) begin
        if (cur == FC_LS_OLS)
          advance = FC_LS_LR;
        else if (cur == FC_LS_ACT)
          advance = FC_LS_OLS;
      end else if (os == FC_LR) begin
        if (cur == FC_LS_OLS || cur == FC_LS_LR || cur == FC_LS_ACT)
          advance = FC_LS_LRR;
      end else if (os == FC_LRR) begin
        if (cur == FC_LS_OLS || cur == FC_LS_LR || cur == FC_LS_LRR)
          advance = FC_LS_ACQ;
      end
    end
  endfunction

  // 1 when this primitive is left over from a state we have already left.
  function automatic logic ignore_os(input [2:0] cur, input [31:0] os);
    begin
      ignore_os = 1'b0;
      if (os == FC_OLS && (cur == FC_LS_LR || cur == FC_LS_LRR || cur == FC_LS_ACQ))
        ignore_os = 1'b1;
      else if (os == FC_LR && (cur == FC_LS_LRR || cur == FC_LS_ACQ))
        ignore_os = 1'b1;
      else if (os == FC_LRR && (cur == FC_LS_ACQ || cur == FC_LS_ACT))
        ignore_os = 1'b1;
      else if (os == FC_IDLE && cur == FC_LS_ACT)
        ignore_os = 1'b1;
    end
  endfunction

  function automatic logic is_prim(input [31:0] os);
    begin
      is_prim = (os == FC_IDLE) || (os == FC_OLS) || (os == FC_LR) || (os == FC_LRR);
    end
  endfunction

  assign link_up    = (st == FC_LS_ACT);
  assign state_code = st;

  always_comb begin
    case (st)
      FC_LS_DOWN: tx_os = FC_NOS;
      FC_LS_OLS:  tx_os = FC_OLS;
      FC_LS_LR:   tx_os = FC_LR;
      FC_LS_LRR:  tx_os = FC_LRR;
      default:    tx_os = FC_IDLE;
    endcase
  end

  wire        ctrl_os = rx_fire && (rx_sync == FC_SYNC_CTRL);
  wire [31:0] os_b    = rx_data[31:0];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st        <= FC_LS_DOWN;
      streak    <= 8'h00;
      streak_os <= 8'h00;
    end else if (!port_en || !locked) begin
      st        <= FC_LS_DOWN;
      streak    <= 8'h00;
      streak_os <= 8'h00;
    end else if (st == FC_LS_DOWN) begin
      st        <= FC_LS_OLS;
      streak    <= 8'h00;
      streak_os <= 8'h00;
    end else if (ctrl_os && os_b == FC_NOS) begin
      st        <= FC_LS_OLS;
      streak    <= 8'h00;
      streak_os <= 8'h00;
    end else if (ctrl_os && is_prim(os_b) && ignore_os(st, os_b)) begin
      st        <= st;
      streak    <= streak;
      streak_os <= streak_os;
    end else if (ctrl_os && is_prim(os_b)) begin
      if (streak_os == os_b && streak != 8'h00) begin
        if (streak + 8'd1 >= 8'(STREAK)) begin
          st        <= advance(st, os_b);
          streak    <= 8'h00;
          streak_os <= 8'h00;
        end else begin
          streak <= streak + 8'd1;
        end
      end else begin
        streak    <= 8'd1;
        streak_os <= os_b;
      end
    end else if (rx_fire) begin
      streak    <= 8'h00;
      streak_os <= 8'h00;
    end
  end
endmodule
