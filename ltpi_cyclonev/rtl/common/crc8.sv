// -----------------------------------------------------------------------------
// LTPI IP for Cyclone V FPGA
// SPDX-License-Identifier: MIT
//
// crc8.sv
//
// CRC-8 generator/checker matching the LTPI specification (section 2.4):
//   Polynomial : x^8 + x^2 + x^1 + 1   (0x07)
//   Init value : 0x00
//   No input bit reflection, no result reflection.
// Processes one byte per clock when `en` is asserted, MSB first. Assert
// `init` together with the first byte of a frame to clear the accumulator.
// -----------------------------------------------------------------------------

module crc8 (
    input  logic       clk,
    input  logic       rst,
    input  logic       en,        // consume data_in this cycle
    input  logic       init,      // start a new CRC accumulation this cycle
    input  logic [7:0] data_in,
    output logic [7:0] crc_out    // registered CRC-8 value (valid one cycle after last byte)
);

    function automatic [7:0] crc8_next(input [7:0] crc_in, input [7:0] data);
        logic [7:0] crc;
        logic       fb;
        integer     i;
        begin
            crc = crc_in;
            for (i = 7; i >= 0; i = i - 1) begin
                fb  = crc[7] ^ data[i];
                crc = {crc[6:0], 1'b0};
                if (fb) crc = crc ^ 8'h07;
            end
            crc8_next = crc;
        end
    endfunction

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            crc_out <= 8'h00;
        end else if (en) begin
            crc_out <= crc8_next(init ? 8'h00 : crc_out, data_in);
        end
    end

endmodule
