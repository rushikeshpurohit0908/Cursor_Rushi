// -----------------------------------------------------------------------------
// LTPI IP for Cyclone V FPGA - SPDX-License-Identifier: MIT
//
// tb_ltpi_top_link.sv
//
// Full end-to-end integration test: two ltpi_top instances (Controller and
// Target) cross-connected back to back over their bit-serial tx/rx ports,
// simulating link bring-up (Detect -> Speed -> Advertise -> Configure ->
// Accept -> Operational) from cold reset, then verifying GPIO values written
// on each side are correctly observed on the other once the link is up, and
// that changing a GPIO value propagates within a few frames.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

import ltpi_pkg::*;

module tb_ltpi_top_link;

    logic clk = 0;
    logic rst = 1;
    always #5 clk = ~clk;

    logic [7:0] ctrl_ll_tx = 8'hA5, ctrl_nl_tx = 8'h3C;
    logic [7:0] tgt_ll_tx  = 8'h5A, tgt_nl_tx  = 8'hC3;

    logic [7:0] ctrl_ll_rx, ctrl_nl_rx, tgt_ll_rx, tgt_nl_rx;

    logic ctrl_tx_bit, tgt_tx_bit;

    ltpi_link_state_e ctrl_state, tgt_state;
    logic             ctrl_link_up, tgt_link_up;
    logic [15:0]      ctrl_crc_err, tgt_crc_err;

    ltpi_top #(.ROLE(LTPI_ROLE_CONTROLLER)) u_controller (
        .clk(clk), .rst(rst),
        .tx_bit(ctrl_tx_bit), .rx_bit(tgt_tx_bit),
        .gpio_ll_tx(ctrl_ll_tx), .gpio_nl_tx(ctrl_nl_tx),
        .gpio_ll_rx(ctrl_ll_rx), .gpio_nl_rx(ctrl_nl_rx),
        .link_state(ctrl_state), .link_up(ctrl_link_up), .crc_error_count(ctrl_crc_err)
    );

    ltpi_top #(.ROLE(LTPI_ROLE_TARGET)) u_target (
        .clk(clk), .rst(rst),
        .tx_bit(tgt_tx_bit), .rx_bit(ctrl_tx_bit),
        .gpio_ll_tx(tgt_ll_tx), .gpio_nl_tx(tgt_nl_tx),
        .gpio_ll_rx(tgt_ll_rx), .gpio_nl_rx(tgt_nl_rx),
        .link_state(tgt_state), .link_up(tgt_link_up), .crc_error_count(tgt_crc_err)
    );

    integer errors = 0;

    task automatic check(input logic cond, input string msg);
        begin
            if (!cond) begin
                errors++;
                $display("ERROR: %s", msg);
            end else begin
                $display("OK: %s", msg);
            end
        end
    endtask

    initial begin
        rst = 1;
        repeat (5) @(posedge clk);
        rst = 0;

        $display("TB_LTPI_TOP_LINK: waiting for both sides to reach LS_OPERATIONAL...");

        fork
            begin : wait_ctrl
                wait (ctrl_link_up);
            end
            begin : wait_tgt
                wait (tgt_link_up);
            end
            begin : timeout
                repeat (60 * 160 + 500) @(posedge clk); // ~60 frame periods, generous margin
                if (!(ctrl_link_up && tgt_link_up)) begin
                    $display("ERROR: link training timed out (ctrl_state=%0d tgt_state=%0d)", ctrl_state, tgt_state);
                    errors++;
                    $display("TB_LTPI_TOP_LINK: FAILED with %0d error(s)", errors);
                    $fatal(1);
                end
            end
        join_any
        disable timeout;

        check(ctrl_link_up, "controller reached LS_OPERATIONAL");
        check(tgt_link_up,  "target reached LS_OPERATIONAL");

        // Let a handful of Operational frames flow so GPIO values settle
        repeat (5 * 160) @(posedge clk);

        check(ctrl_ll_rx === tgt_ll_tx, $sformatf("controller sees target's LL GPIOs (exp=0x%02x got=0x%02x)", tgt_ll_tx, ctrl_ll_rx));
        check(ctrl_nl_rx === tgt_nl_tx, $sformatf("controller sees target's NL GPIOs (exp=0x%02x got=0x%02x)", tgt_nl_tx, ctrl_nl_rx));
        check(tgt_ll_rx  === ctrl_ll_tx, $sformatf("target sees controller's LL GPIOs (exp=0x%02x got=0x%02x)", ctrl_ll_tx, tgt_ll_rx));
        check(tgt_nl_rx  === ctrl_nl_tx, $sformatf("target sees controller's NL GPIOs (exp=0x%02x got=0x%02x)", ctrl_nl_tx, tgt_nl_rx));

        check(ctrl_crc_err == 16'd0, "controller has no CRC errors");
        check(tgt_crc_err  == 16'd0, "target has no CRC errors");

        // Change a GPIO value at runtime and confirm it propagates
        ctrl_ll_tx = 8'h7E;
        repeat (5 * 160) @(posedge clk);
        check(tgt_ll_rx === 8'h7E, $sformatf("target observes updated controller LL GPIO (got=0x%02x)", tgt_ll_rx));

        if (errors == 0)
            $display("TB_LTPI_TOP_LINK: ALL CHECKS PASSED");
        else begin
            $display("TB_LTPI_TOP_LINK: FAILED with %0d error(s)", errors);
            $fatal(1);
        end
        $finish;
    end

endmodule
