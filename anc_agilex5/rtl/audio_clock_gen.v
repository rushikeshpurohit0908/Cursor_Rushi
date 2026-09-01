// audio_clock_gen.v
// Generates I2S master clocks from a system reference clock.
//
// Default: 48 kHz sample rate, 64 BCLK periods per frame, 256 MCLK periods
// per sample → MCLK = 12.288 MHz, BCLK = 3.072 MHz, LRCK = 48 kHz.
//
// For sys_clk = 100 MHz the dividers are approximate integer ratios; for
// production use a dedicated 24.576 MHz audio crystal is preferred.

`timescale 1ns / 1ps

module audio_clock_gen #(
    parameter SYS_CLK_HZ   = 100_000_000,
    parameter SAMPLE_RATE  = 48_000,
    parameter MCLK_RATIO   = 256,
    parameter BCLK_RATIO   = 64
) (
    input  wire sys_clk,
    input  wire reset_n,
    output reg  mclk,
    output reg  bclk,
    output reg  lrck,
    output reg  sample_tick   // one-cycle pulse at SAMPLE_RATE
);

    localparam integer MCLK_HZ  = SAMPLE_RATE * MCLK_RATIO;
    localparam integer BCLK_HZ  = SAMPLE_RATE * BCLK_RATIO;
    localparam integer MCLK_DIV = SYS_CLK_HZ / MCLK_HZ;
    localparam integer BCLK_DIV = SYS_CLK_HZ / BCLK_HZ;
    localparam integer LRCK_DIV = SYS_CLK_HZ / SAMPLE_RATE;

    reg [15:0] mclk_cnt;
    reg [15:0] bclk_cnt;
    reg [31:0] lrck_cnt;

    always @(posedge sys_clk or negedge reset_n) begin
        if (!reset_n) begin
            mclk_cnt <= 0;
            bclk_cnt <= 0;
            lrck_cnt <= 0;
            mclk     <= 0;
            bclk     <= 0;
            lrck     <= 0;
            sample_tick <= 0;
        end else begin
            sample_tick <= 0;

            if (mclk_cnt >= MCLK_DIV/2 - 1) begin
                mclk_cnt <= 0;
                mclk     <= ~mclk;
            end else
                mclk_cnt <= mclk_cnt + 1;

            if (bclk_cnt >= BCLK_DIV/2 - 1) begin
                bclk_cnt <= 0;
                bclk     <= ~bclk;
            end else
                bclk_cnt <= bclk_cnt + 1;

            if (lrck_cnt >= LRCK_DIV - 1) begin
                lrck_cnt <= 0;
                lrck     <= ~lrck;
                sample_tick <= 1;
            end else
                lrck_cnt <= lrck_cnt + 1;
        end
    end

endmodule
