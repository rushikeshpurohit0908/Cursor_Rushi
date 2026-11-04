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
  logic [7:0]  tx_os;
  logic [2:0]  state_code;

  fc_link_sm #(.STREAK(4)) dut (
    .clk(clk), .rst_n(rst_n), .port_en(port_en), .locked(locked),
    .rx_fire(rx_fire), .rx_sync(rx_sync), .rx_data(rx_data),
    .link_up(link_up), .tx_os(tx_os), .state_code(state_code)
  );

  integer errors = 0;

  task automatic check_ls;
    input [2:0] st;
    input [7:0] os;
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

  task automatic fire(input [7:0] os);
    begin
      @(posedge clk);
      rx_sync <= FC_SYNC_CTRL;
      rx_data <= {56'h0, os};
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

  task automatic fires(input [7:0] os, input integer n);
    integer k;
    begin
      for (k = 0; k < n; k = k + 1)
        fire(os);
    end
  endtask

  initial begin
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
