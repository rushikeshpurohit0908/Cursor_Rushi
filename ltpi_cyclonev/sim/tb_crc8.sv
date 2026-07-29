// -----------------------------------------------------------------------------
// LTPI IP for Cyclone V FPGA - SPDX-License-Identifier: MIT
//
// tb_crc8.sv - self-checking testbench for crc8.sv (LTPI spec section 2.4:
// CRC-8, polynomial x^8+x^2+x^1+1 = 0x07, init 0x00, no reflection).
// Cross-checked against an independently published catalogue check value
// (CRC-8/SMBUS: poly=0x07 init=0x00 refin=false refout=false, check=0xF4 for
// ASCII "123456789"), which uses the identical CRC-8 definition as the LTPI
// specification.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_crc8;

    logic       clk = 0;
    logic       rst = 1;
    logic       en  = 0;
    logic       init = 0;
    logic [7:0] data_in;
    logic [7:0] crc_out;

    crc8 u_crc (.clk(clk), .rst(rst), .en(en), .init(init), .data_in(data_in), .crc_out(crc_out));

    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;

    localparam int MAX_LEN = 16;
    logic [7:0] vec [0:MAX_LEN-1];
    integer     vec_len;

    task automatic pulse_clk;
        begin @(posedge clk); #1; end
    endtask

    function automatic [7:0] sw_crc8;
        logic [7:0] crc;
        logic       fb;
        integer     i, b;
        begin
            crc = 8'h00;
            for (b = 0; b < vec_len; b = b + 1) begin
                for (i = 7; i >= 0; i = i - 1) begin
                    fb  = crc[7] ^ vec[b][i];
                    crc = {crc[6:0], 1'b0};
                    if (fb) crc = crc ^ 8'h07;
                end
            end
            sw_crc8 = crc;
        end
    endfunction

    task automatic check_vec(input string name, input logic [7:0] fixed_expect, input logic use_fixed);
        integer     i;
        logic [7:0] expect_val;
        begin
            expect_val = use_fixed ? fixed_expect : sw_crc8();
            rst = 1; en = 0; pulse_clk(); rst = 0;
            for (i = 0; i < vec_len; i = i + 1) begin
                data_in = vec[i];
                init    = (i == 0);
                en      = 1;
                pulse_clk();
            end
            en = 0;
            checks++;
            if (crc_out !== expect_val) begin
                errors++;
                $display("ERROR: %s expected=0x%02x got=0x%02x", name, expect_val, crc_out);
            end else begin
                $display("OK: %s crc=0x%02x", name, crc_out);
            end
        end
    endtask

    initial begin
        integer i;

        vec_len = 1;
        vec[0] = 8'h00;
        check_vec("single zero byte", 8'h00, 1'b0);

        vec_len = 4;
        vec[0]=8'h01; vec[1]=8'h02; vec[2]=8'h03; vec[3]=8'h04;
        check_vec("4 incrementing bytes", 8'h00, 1'b0);

        vec_len = 4;
        for (i = 0; i < 4; i = i + 1) vec[i] = 8'hFF;
        check_vec("4 x 0xFF bytes", 8'h00, 1'b0);

        vec_len = 14;
        vec[0]=8'h00; vec[1]=8'h01; vec[2]=8'hBC; vec[3]=8'h00; vec[4]=8'h55; vec[5]=8'hAA; vec[6]=8'h12;
        vec[7]=8'h34; vec[8]=8'h56; vec[9]=8'h78; vec[10]=8'h9A; vec[11]=8'hBC; vec[12]=8'hDE; vec[13]=8'hF0;
        check_vec("14-byte LTPI-like payload", 8'h00, 1'b0);

        // Independent, published catalogue check value: CRC-8/SMBUS
        vec_len = 9;
        vec[0]=8'h31; vec[1]=8'h32; vec[2]=8'h33; vec[3]=8'h34; vec[4]=8'h35;
        vec[5]=8'h36; vec[6]=8'h37; vec[7]=8'h38; vec[8]=8'h39;
        check_vec("CRC-8/SMBUS published check value (\"123456789\")", 8'hF4, 1'b1);

        if (errors == 0)
            $display("TB_CRC8: ALL CHECKS PASSED (%0d checks)", checks);
        else begin
            $display("TB_CRC8: FAILED with %0d error(s)", errors);
            $fatal(1);
        end
        $finish;
    end

endmodule
