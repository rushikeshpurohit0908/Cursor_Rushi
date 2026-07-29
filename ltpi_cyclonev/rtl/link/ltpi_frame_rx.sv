// -----------------------------------------------------------------------------
// LTPI IP for Cyclone V FPGA - SPDX-License-Identifier: MIT
//
// ltpi_frame_rx.sv
//
// Consumes a stream of already bit/symbol-aligned 10-bit codewords (from
// ltpi_symbol_align.sv) and reassembles 16-byte LTPI frames. Frame position
// is self-synchronizing: any decoded comma (K28.5/K28.6/K28.7) is always
// treated as byte 0 of a new frame, so a single missed/garbled frame cannot
// permanently desynchronize byte counting - the very next real comma
// re-anchors it. A frame that turns out not to have started with a comma
// (or gets a garbled comma) will simply fail its CRC check.
//
// `frame_bytes` is a packed bus (see ltpi_frame_tx.sv): byte i (i=0..13,
// i.e. frame bytes 1..14) occupies bits [i*8 +: 8].
// -----------------------------------------------------------------------------

import ltpi_pkg::*;

module ltpi_frame_rx (
    input  logic       clk,
    input  logic       rst,

    input  logic [9:0] sym_in,
    input  logic       sym_valid,

    output logic                          frame_valid, // 1-cycle pulse: a full frame was captured
    output logic [7:0]                    comma_byte,  // BC/DC/FC seen at byte 0 of this frame
    output logic                          crc_ok,
    output logic [FRAME_PAYLOAD_BITS-1:0] frame_bytes  // bytes[1..14], valid with frame_valid
);

    logic       dec_en, dec_valid_d;
    logic [7:0] dec_out;
    logic       dec_k, dec_err;

    decoder_8b10b u_dec (
        .clk(clk), .rst(rst), .en(sym_valid), .data_in(sym_in),
        .data_out(dec_out), .k_out(dec_k), .code_err(dec_err)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) dec_valid_d <= 1'b0;
        else     dec_valid_d <= sym_valid;
    end

    logic [3:0] byte_pos; // 0 = idle/waiting for comma, 1..14 = payload, 15 = CRC byte
    logic       crc_en, crc_init;
    logic [7:0] crc_out;

    assign crc_en   = dec_valid_d && !dec_k && (byte_pos >= 4'd1) && (byte_pos <= 4'd14);
    assign crc_init = dec_valid_d && !dec_k && (byte_pos == 4'd1);

    crc8 u_crc (
        .clk(clk), .rst(rst), .en(crc_en), .init(crc_init), .data_in(dec_out), .crc_out(crc_out)
    );

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            byte_pos    <= 4'd0;
            comma_byte  <= 8'h00;
            frame_valid <= 1'b0;
            crc_ok      <= 1'b0;
            frame_bytes <= '0;
        end else begin
            frame_valid <= 1'b0;

            if (dec_valid_d) begin
                if (dec_k) begin
                    comma_byte <= dec_out;
                    byte_pos   <= 4'd1;
                end else if (byte_pos >= 4'd1 && byte_pos <= 4'd14) begin
                    frame_bytes[int'(byte_pos - 4'd1) * 8 +: 8] <= dec_out;
                    byte_pos <= byte_pos + 4'd1;
                end else if (byte_pos == 4'd15) begin
                    frame_valid <= 1'b1;
                    crc_ok      <= (dec_out == crc_out);
                    byte_pos    <= 4'd0;
                end
                // byte_pos == 0 (idle, never synced yet): ignore until a comma arrives
            end
        end
    end

endmodule
