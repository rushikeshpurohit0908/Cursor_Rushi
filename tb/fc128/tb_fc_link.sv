`timescale 1ns/1ps
// Link bring-up, stale-primitive filtering, Idle shortcut, and NOS drop.
module tb_fc_link;
  `include "fc128_defs.vh"

  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;

  logic        port_en = 0;
  logic        locked = 0;
  logic        rx_fire = 0;
  logic [1:0]  rx_sync = 0;
  logic [63:0] rx_data = 0;
  logic        link_up;
  logic [31:0] tx_os;
  logic [2:0]  state_code;

  fc_link_sm #(.STREAK(4)) dut (
    .clk(clk), .rst_n(rst_n), .port_en(port_en), .locked(locked),
    .rx_fire(rx_fire), .rx_sync(rx_sync), .rx_data(rx_data),
    .link_up(link_up), .tx_os(tx_os), .state_code(state_code)
  );

  integer errors = 0;

  task automatic check_ls;
    input [2:0] st;
    input [31:0] os;
    input up;
    input [255:0] tag;
    begin
      if (state_code !== st || tx_os !== os || link_up !== up) begin
        $display("FAIL %0s state %0d exp %0d os %h exp %h up %b exp %b",
                 tag, state_code, st, tx_os, os, link_up, up);
        errors = errors + 1;
      end
    end
  endtask

  task automatic fire(input [31:0] os);
    begin
      @(posedge clk);
      rx_sync <= FC_SYNC_CTRL;
      rx_data <= {32'h0, os};
      rx_fire <= 1'b1;
      @(posedge clk);
      @(negedge clk);
      rx_fire <= 1'b0;
    end
  endtask

  task automatic fire_data;
    begin
      @(posedge clk);
      rx_sync <= FC_SYNC_DATA;
      rx_data <= 64'h0123_4567_89AB_CDEF;
      rx_fire <= 1'b1;
      @(posedge clk);
      @(negedge clk);
      rx_fire <= 1'b0;
    end
  endtask

  task automatic fires(input [31:0] os, input integer n);
    integer k;
    begin
      for (k = 0; k < n; k = k + 1)
        fire(os);
    end
  endtask

  task automatic check_word;
    input [31:0] got;
    input [31:0] exp;
    input [255:0] tag;
    begin
      if (got !== exp) begin
        $display("FAIL %0s word %h exp %h", tag, got, exp);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    check_word(FC_IDLE, 32'hB5B595BC, "IDLE");
    check_word(FC_RRDY, 32'h4A4A95BC, "R_RDY");
    check_word(FC_NOS,  32'h45BF55BC, "NOS");
    check_word(FC_OLS,  32'h558A35BC, "OLS");
    check_word(FC_LR,   32'h49BF49BC, "LR");
    check_word(FC_LRR,  32'h49BF35BC, "LRR");
    check_word(FC_SOF,  32'h5656B5BC, "SOFi3");
    check_word(FC_EOF,  32'h757595BC, "EOFt");
    check_word(FC_EOFN, 32'hD5D595BC, "EOFn");
    if (!fc_is_sof(FC_SOFN3) || !fc_is_sof(FC_SOFF) || fc_is_sof(FC_EOFDT_P) ||
        !fc_is_eof_good(FC_EOFN_P) || !fc_is_eof_good(FC_EOFT_P) ||
        !fc_is_eof_bad(FC_EOFA) || !fc_is_eof_bad(FC_EOFNI_P) ||
        fc_is_eof_good(FC_IDLE) || fc_is_eof_bad(FC_RRDY)) begin
      $display("FAIL ordered-set classify");
      errors = errors + 1;
    end

    repeat (3) @(posedge clk);
    @(negedge clk);
    rst_n = 1;
    @(posedge clk);
    @(negedge clk);
    check_ls(FC_LS_DOWN, FC_NOS, 1'b0, "reset");

    port_en = 1;
    @(posedge clk);
    @(negedge clk);
    check_ls(FC_LS_DOWN, FC_NOS, 1'b0, "enabled still down");

    locked = 1;
    @(posedge clk);
    @(negedge clk);
    check_ls(FC_LS_OLS, FC_OLS, 1'b0, "lock enters OLS");

    fires(FC_OLS, 3);
    check_ls(FC_LS_OLS, FC_OLS, 1'b0, "three OLS hold");
    fire_data();
    fires(FC_OLS, 3);
    check_ls(FC_LS_OLS, FC_OLS, 1'b0, "data breaks OLS streak");
    fire(FC_OLS);
    check_ls(FC_LS_LR, FC_LR, 1'b0, "fourth OLS enters LR");

    fires(FC_OLS, 6);
    check_ls(FC_LS_LR, FC_LR, 1'b0, "stale OLS ignored");
    fires(FC_LR, 4);
    check_ls(FC_LS_LRR, FC_LRR, 1'b0, "LR enters LRR");
    fires(FC_LR, 4);
    check_ls(FC_LS_LRR, FC_LRR, 1'b0, "stale LR ignored");
    fires(FC_LRR, 4);
    check_ls(FC_LS_ACQ, FC_IDLE, 1'b0, "LRR enters acquire");
    fires(FC_LRR, 4);
    check_ls(FC_LS_ACQ, FC_IDLE, 1'b0, "stale LRR ignored");
    fires(FC_IDLE, 3);
    check_ls(FC_LS_ACQ, FC_IDLE, 1'b0, "three IDLE hold");
    fire(FC_IDLE);
    check_ls(FC_LS_ACT, FC_IDLE, 1'b1, "IDLE enters active");

    fires(FC_IDLE, 4);
    check_ls(FC_LS_ACT, FC_IDLE, 1'b1, "IDLE stays active");
    fire(FC_NOS);
    check_ls(FC_LS_OLS, FC_OLS, 1'b0, "NOS drops the link");

    fires(FC_IDLE, 4);
    check_ls(FC_LS_ACQ, FC_IDLE, 1'b0, "IDLE from OLS acquires");
    fires(FC_IDLE, 4);
    check_ls(FC_LS_ACT, FC_IDLE, 1'b1, "second IDLE run is active");

    fires(FC_LR, 4);
    check_ls(FC_LS_LRR, FC_LRR, 1'b0, "LR from active sends LRR");

    locked = 0;
    @(posedge clk);
    @(negedge clk);
    check_ls(FC_LS_DOWN, FC_NOS, 1'b0, "unlock sends NOS");

    if (errors == 0)
      $display("PASS tb_fc_link");
    else
      $display("FAIL tb_fc_link errors=%0d", errors);
    $finish;
  end
endmodule
