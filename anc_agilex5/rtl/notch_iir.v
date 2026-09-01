// notch_iir.v
// Biquad notch for tonal-noise assist. Direct-form I, Q1.15 coefficients.
// y[n] = b0*x + b1*x1 + b2*x2 - a1*y1 - a2*y2
// Default coefficients are a 500 Hz notch at 48 kHz (can be overwritten).

`timescale 1ns / 1ps

module notch_iir #(
    parameter DATA_WIDTH = 32
) (
    input  wire clk,
    input  wire reset_n,
    input  wire enable,
    input  wire valid_in,
    input  wire signed [DATA_WIDTH-1:0] x_in,
    input  wire signed [15:0] b0,
    input  wire signed [15:0] b1,
    input  wire signed [15:0] b2,
    input  wire signed [15:0] a1,
    input  wire signed [15:0] a2,
    output reg  valid_out,
    output reg  signed [DATA_WIDTH-1:0] y_out
);

    reg signed [DATA_WIDTH-1:0] x1, x2, y1, y2;
    reg signed [DATA_WIDTH+16:0] acc;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            x1        <= 0;
            x2        <= 0;
            y1        <= 0;
            y2        <= 0;
            y_out     <= 0;
            valid_out <= 0;
            acc       <= 0;
        end else begin
            valid_out <= 0;
            if (valid_in) begin
                if (!enable) begin
                    y_out     <= x_in;
                    valid_out <= 1;
                end else begin
                    acc = (x_in * b0) + (x1 * b1) + (x2 * b2)
                        - (y1 * a1) - (y2 * a2);
                    y_out <= acc[DATA_WIDTH+15:16];
                    x2 <= x1;
                    x1 <= x_in;
                    y2 <= y1;
                    y1 <= acc[DATA_WIDTH+15:16];
                    valid_out <= 1;
                end
            end
        end
    end

endmodule
