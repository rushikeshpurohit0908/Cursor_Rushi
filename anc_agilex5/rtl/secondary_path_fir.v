// secondary_path_fir.v
// Fixed secondary-path model (Ŝ) — 128-tap FIR applied to reference signal.
// Coefficients loaded from BRAM/CSR at init; read-only during adaptation.

`timescale 1ns / 1ps

module secondary_path_fir #(
    parameter FILTER_TAPS = 128,
    parameter DATA_WIDTH  = 32,
    parameter COEFF_WIDTH = 32
) (
    input  wire clk,
    input  wire reset_n,
    input  wire valid_in,
    input  wire signed [DATA_WIDTH-1:0] x_in,

    output reg  valid_out,
    output reg  signed [DATA_WIDTH-1:0] x_filtered,

    // Coefficient access (from BRAM or CSR loader)
    input  wire coeff_wr_en,
    input  wire [$clog2(FILTER_TAPS)-1:0] coeff_wr_addr,
    input  wire signed [COEFF_WIDTH-1:0] coeff_wr_data,
    input  wire [$clog2(FILTER_TAPS)-1:0] coeff_rd_addr,
    output wire signed [COEFF_WIDTH-1:0] coeff_rd_data
);

    reg signed [DATA_WIDTH-1:0] delay_line [0:FILTER_TAPS-1];
    reg signed [COEFF_WIDTH-1:0] coeffs [0:FILTER_TAPS-1];

    reg [$clog2(FILTER_TAPS)-1:0] tap;
    reg signed [DATA_WIDTH+COEFF_WIDTH+7:0] mac_accum;
    reg mac_active;

    integer i;

    initial begin
        for (i = 0; i < FILTER_TAPS; i = i + 1)
            coeffs[i] = (i == 0) ? 32'h7FFF_0000 : 32'h0;
    end

    assign coeff_rd_data = coeffs[coeff_rd_addr];

    always @(posedge clk) begin
        if (coeff_wr_en)
            coeffs[coeff_wr_addr] <= coeff_wr_data;
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            valid_out  <= 0;
            x_filtered <= 0;
            tap        <= 0;
            mac_accum  <= 0;
            mac_active <= 0;
            for (i = 0; i < FILTER_TAPS; i = i + 1)
                delay_line[i] <= 0;
        end else begin
            valid_out <= 0;

            if (valid_in) begin
                for (i = FILTER_TAPS-1; i > 0; i = i - 1)
                    delay_line[i] <= delay_line[i-1];
                delay_line[0] <= x_in;

                mac_active <= 1;
                tap        <= 0;
                mac_accum  <= delay_line[0] * coeffs[0];
            end else if (mac_active) begin
                if (tap == FILTER_TAPS - 2) begin
                    mac_active <= 0;
                    x_filtered <= mac_accum[DATA_WIDTH+COEFF_WIDTH-1:COEFF_WIDTH];
                    valid_out  <= 1;
                end else begin
                    tap <= tap + 1;
                    mac_accum <= mac_accum + (delay_line[tap+1] * coeffs[tap+1]);
                end
            end
        end
    end

endmodule
