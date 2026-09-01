// tb_i2c_codec.v — walks SSM2518 init ROM through the I2C master.

`timescale 1ns / 1ps

module tb_i2c_codec;

    reg clk;
    reg reset_n;
    reg start_init;

    wire i2c_start, i2c_busy, i2c_done, i2c_ack;
    wire [6:0] i2c_addr;
    wire [7:0] i2c_reg, i2c_data;
    wire ready, busy;
    wire scl, sda;

    pullup (scl);
    pullup (sda);

    initial clk = 0;
    always #5 clk = ~clk;

    i2c_master #(.SYS_CLK_HZ(100_000_000), .I2C_HZ(1_000_000)) u_i2c (
        .clk(clk), .reset_n(reset_n),
        .start(i2c_start), .slave_addr(i2c_addr),
        .reg_addr(i2c_reg), .wr_data(i2c_data),
        .busy(i2c_busy), .done(i2c_done), .ack_error(i2c_ack),
        .scl(scl), .sda(sda)
    );

    codec_init #(.CODEC_SEL(0)) u_init (
        .clk(clk), .reset_n(reset_n), .start_init(start_init),
        .i2c_start(i2c_start), .i2c_addr(i2c_addr),
        .i2c_reg(i2c_reg), .i2c_data(i2c_data),
        .i2c_busy(i2c_busy), .i2c_done(i2c_done),
        .ready(ready), .busy(busy)
    );

    initial begin
        $dumpfile("tb_i2c_codec.vcd");
        $dumpvars(0, tb_i2c_codec);
        reset_n = 0;
        start_init = 0;
        repeat (20) @(posedge clk);
        reset_n = 1;
        repeat (10) @(posedge clk);
        start_init = 1;
        @(posedge clk);
        start_init = 0;

        wait (ready);
        $display("SSM2518 init complete, codec ready");
        $finish;
    end

    initial begin
        #5_000_000;
        $display("TIMEOUT waiting for codec ready");
        $finish;
    end

endmodule
