// codec_init.v
// Table-driven I2C register programmer for SSM2518 or WM8960.
// Kick off with start_init; walks ROM until terminator (0xFF, 0xFF).

`timescale 1ns / 1ps

module codec_init #(
    parameter CODEC_SEL = 0  // 0=SSM2518, 1=WM8960, 2=none (Pmod I2S2)
) (
    input  wire clk,
    input  wire reset_n,
    input  wire start_init,

    output reg        i2c_start,
    output reg  [6:0] i2c_addr,
    output reg  [7:0] i2c_reg,
    output reg  [7:0] i2c_data,
    input  wire       i2c_busy,
    input  wire       i2c_done,

    output reg        ready,
    output reg        busy
);

    // ROM: {reg[7:0], val[7:0]} — 0xFFFF terminates
    // SSM2518 (addr 0x34): reset, clocks, I2S 24-bit slave, unmute, power-up
    // WM8960  (addr 0x1A): reset, PLL/clock, I2S, headphone out, unmute
    localparam ROM_DEPTH = 16;

    function automatic [15:0] rom_ssm(input [3:0] idx);
        case (idx)
            4'd0:  rom_ssm = 16'h0080; // R0 software reset
            4'd1:  rom_ssm = 16'h0100; // R1 power control — bring up
            4'd2:  rom_ssm = 16'h0202; // R2 clock: BCLK/MCLK slave, 256fs
            4'd3:  rom_ssm = 16'h0302; // R3 SAI: I2S, 24-bit
            4'd4:  rom_ssm = 16'h0400; // R4 SAI mapping default
            4'd5:  rom_ssm = 16'h0600; // R6 left volume 0 dB
            4'd6:  rom_ssm = 16'h0700; // R7 right volume 0 dB
            4'd7:  rom_ssm = 16'h0800; // R8 unmute
            default: rom_ssm = 16'hFFFF;
        endcase
    endfunction

    function automatic [15:0] rom_wm(input [3:0] idx);
        case (idx)
            4'd0:  rom_wm = 16'h0F00; // R15 reset
            4'd1:  rom_wm = 16'h1916; // R25 VMID / VREF
            4'd2:  rom_wm = 16'h1A00; // R26 power mgmt 2
            4'd3:  rom_wm = 16'h0400; // R4 clocking
            4'd4:  rom_wm = 16'h0702; // R7 audio interface I2S 24-bit
            4'd5:  rom_wm = 16'h027F; // R2 LOUT1 0 dB + update
            4'd6:  rom_wm = 16'h037F; // R3 ROUT1 0 dB + update
            4'd7:  rom_wm = 16'h2F00; // R47 mixer
            4'd8:  rom_wm = 16'h2201; // R34 LOUT2 mixer
            default: rom_wm = 16'hFFFF;
        endcase
    endfunction

    localparam [6:0] ADDR_SSM = 7'h34;
    localparam [6:0] ADDR_WM  = 7'h1A;

    localparam S_IDLE  = 2'd0;
    localparam S_ISSUE = 2'd1;
    localparam S_WAIT  = 2'd2;
    localparam S_DONE  = 2'd3;

    reg [1:0] state;
    reg [3:0] idx;
    reg [15:0] entry;

    always @(*) begin
        if (CODEC_SEL == 0)
            entry = rom_ssm(idx);
        else if (CODEC_SEL == 1)
            entry = rom_wm(idx);
        else
            entry = 16'hFFFF;
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state     <= S_IDLE;
            idx       <= 0;
            i2c_start <= 0;
            i2c_addr  <= (CODEC_SEL == 1) ? ADDR_WM : ADDR_SSM;
            i2c_reg   <= 0;
            i2c_data  <= 0;
            ready     <= (CODEC_SEL == 2);
            busy      <= 0;
        end else begin
            i2c_start <= 0;

            if (CODEC_SEL == 2) begin
                ready <= 1;
                busy  <= 0;
            end else case (state)
                S_IDLE: begin
                    if (start_init) begin
                        idx   <= 0;
                        busy  <= 1;
                        ready <= 0;
                        state <= S_ISSUE;
                    end
                end

                S_ISSUE: begin
                    if (entry == 16'hFFFF)
                        state <= S_DONE;
                    else if (!i2c_busy) begin
                        i2c_reg   <= entry[15:8];
                        i2c_data  <= entry[7:0];
                        i2c_start <= 1;
                        state     <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    if (i2c_done) begin
                        idx   <= idx + 1;
                        state <= S_ISSUE;
                    end
                end

                S_DONE: begin
                    ready <= 1;
                    busy  <= 0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
