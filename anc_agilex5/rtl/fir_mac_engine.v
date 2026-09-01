// fir_mac_engine.v
// Time-multiplexed FIR multiply-accumulate engine.
// Processes one tap per clock cycle; full filter output in FILTER_TAPS cycles.

`timescale 1ns / 1ps

module fir_mac_engine #(
    parameter FILTER_TAPS  = 256,
    parameter DATA_WIDTH   = 32,
    parameter COEFF_WIDTH  = 32
) (
    input  wire clk,
    input  wire reset_n,
    input  wire start,
    input  wire signed [DATA_WIDTH-1:0]  sample_in,
    input  wire signed [COEFF_WIDTH-1:0] coeff_in,
    input  wire [$clog2(FILTER_TAPS)-1:0] tap_addr,

    output reg  done,
    output reg  signed [DATA_WIDTH+COEFF_WIDTH-1:0] accum_out,
    output reg  [$clog2(FILTER_TAPS)-1:0] tap_idx
);

    reg running;
    reg signed [DATA_WIDTH+COEFF_WIDTH-1:0] accum;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            running   <= 0;
            done      <= 0;
            accum     <= 0;
            accum_out <= 0;
            tap_idx   <= 0;
        end else begin
            done <= 0;

            if (start && !running) begin
                running <= 1;
                accum   <= sample_in * coeff_in;
                tap_idx <= 1;
            end else if (running) begin
                accum <= accum + (sample_in * coeff_in);
                if (tap_idx == FILTER_TAPS - 1) begin
                    running   <= 0;
                    done      <= 1;
                    accum_out <= accum + (sample_in * coeff_in);
                    tap_idx   <= 0;
                end else
                    tap_idx <= tap_idx + 1;
            end
        end
    end

endmodule
