// i2s_tx.v
// I2S/TDM transmitter — serializes anti-noise samples to DAC.

`timescale 1ns / 1ps

module i2s_tx #(
    parameter DATA_WIDTH = 24,
    parameter TDM_SLOTS  = 2
) (
    input  wire bclk,
    input  wire lrck,
    input  wire reset_n,
    input  wire                       sample_valid,
    input  wire signed [DATA_WIDTH-1:0] slot_data [0:TDM_SLOTS-1],

    output reg sdout
);

    localparam TOTAL_BITS = DATA_WIDTH * TDM_SLOTS;

    reg [TOTAL_BITS-1:0] shift_reg;
    reg [$clog2(TOTAL_BITS)-1:0] bit_idx;
    reg loaded;

    integer i;

    always @(posedge bclk or negedge reset_n) begin
        if (!reset_n) begin
            shift_reg <= 0;
            bit_idx   <= TOTAL_BITS - 1;
            sdout     <= 0;
            loaded    <= 0;
        end else begin
            if (sample_valid && !loaded) begin
                for (i = 0; i < TDM_SLOTS; i = i + 1)
                    shift_reg[(i+1)*DATA_WIDTH-1 -: DATA_WIDTH] <= slot_data[i];
                bit_idx <= TOTAL_BITS - 1;
                loaded  <= 1;
            end

            if (loaded) begin
                sdout <= shift_reg[bit_idx];
                if (bit_idx == 0) begin
                    loaded  <= 0;
                    bit_idx <= TOTAL_BITS - 1;
                end else
                    bit_idx <= bit_idx - 1;
            end
        end
    end

endmodule
