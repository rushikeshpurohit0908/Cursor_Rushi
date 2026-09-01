// i2s_rx.v
// I2S/TDM receiver — deserializes multi-slot audio from ADC.
// Philips I2S format: 1 BCLK delay after LRCK edge, MSB first.

`timescale 1ns / 1ps

module i2s_rx #(
    parameter DATA_WIDTH = 24,
    parameter TDM_SLOTS  = 2
) (
    input  wire bclk,
    input  wire lrck,
    input  wire sdin,
    input  wire reset_n,

    output reg                       sample_valid,
    output reg  signed [DATA_WIDTH-1:0] slot_data [0:TDM_SLOTS-1]
);

    localparam TOTAL_BITS = DATA_WIDTH * TDM_SLOTS;

    reg [$clog2(TOTAL_BITS)-1:0] bit_idx;
    reg [TOTAL_BITS-1:0]           shift_reg;
    reg                            lrck_d;

    integer i;

    always @(posedge bclk or negedge reset_n) begin
        if (!reset_n) begin
            bit_idx      <= 0;
            shift_reg    <= 0;
            lrck_d       <= 0;
            sample_valid <= 0;
            for (i = 0; i < TDM_SLOTS; i = i + 1)
                slot_data[i] <= 0;
        end else begin
            sample_valid <= 0;
            lrck_d       <= lrck;

            // Shift in one bit per BCLK (skip LRCK transition cycle in simple mode)
            shift_reg <= {shift_reg[TOTAL_BITS-2:0], sdin};

            if (bit_idx == TOTAL_BITS - 1) begin
                bit_idx <= 0;
                for (i = 0; i < TDM_SLOTS; i = i + 1)
                    slot_data[i] <= $signed(shift_reg[(i+1)*DATA_WIDTH-1 -: DATA_WIDTH]);
                sample_valid <= 1;
            end else
                bit_idx <= bit_idx + 1;
        end
    end

endmodule
