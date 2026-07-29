// -----------------------------------------------------------------------------
// LTPI IP for Cyclone V FPGA - SPDX-License-Identifier: MIT
//
// ltpi_symbol_serializer.sv
//
// Generic (vendor-agnostic) bit serializer: shifts a 10-bit 8b/10b symbol out
// one bit per clock, MSB first (bit 9 = 'a', first on the wire; bit 0 = 'j',
// last on the wire), and requests the next symbol one cycle ahead of time via
// `symbol_tick` so an encoder with 1-cycle latency can supply it just in time.
// -----------------------------------------------------------------------------

module ltpi_symbol_serializer (
    input  logic       clk,
    input  logic       rst,
    input  logic [9:0] sym_in,      // must be valid the cycle after symbol_tick
    output logic       symbol_tick, // 1-cycle pulse requesting the next symbol
    output logic       tx_bit       // serial output, one bit per clk
);

    logic [3:0] bit_cnt;
    logic [9:0] shift_reg;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bit_cnt     <= 4'd0;
            shift_reg   <= 10'd0;
            symbol_tick <= 1'b0;
            tx_bit      <= 1'b0;
        end else begin
            symbol_tick <= (bit_cnt == 4'd9);

            if (bit_cnt == 4'd0) begin
                shift_reg <= sym_in;
                tx_bit    <= sym_in[9];
            end else begin
                shift_reg <= {shift_reg[8:0], 1'b0};
                tx_bit    <= shift_reg[8];
            end

            bit_cnt <= (bit_cnt == 4'd9) ? 4'd0 : (bit_cnt + 4'd1);
        end
    end

endmodule
