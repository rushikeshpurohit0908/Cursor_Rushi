// -----------------------------------------------------------------------------
// LTPI IP for Cyclone V FPGA - SPDX-License-Identifier: MIT
//
// ltpi_frame_tx.sv
//
// Builds and continuously transmits 16-byte LTPI frames:
//   byte 0       : comma symbol (K28.5 / K28.6 / K28.7, selected by comma_sel)
//   bytes 1..14  : frame_bytes[0..13] (subtype + payload), CRC-8 accumulated
//   byte 15      : CRC-8 checksum over bytes 1..14
//
// One byte is encoded per `symbol_tick` (driven by ltpi_symbol_serializer).
// `frame_tick` pulses one symbol period before the frame boundary so
// ltpi_link_ctrl.sv has time to register the next frame's comma_sel and
// frame_bytes before they are latched in.
//
// `frame_bytes` is a packed bus (rather than an unpacked array) for maximum
// tool portability at module boundaries: byte i (i=0..13, i.e. frame bytes
// 1..14) occupies bits [i*8 +: 8].
// -----------------------------------------------------------------------------

import ltpi_pkg::*;

module ltpi_frame_tx (
    input  logic                          clk,
    input  logic                          rst,
    input  logic                          symbol_tick, // from ltpi_symbol_serializer

    input  logic [1:0]                    comma_sel,   // 0=K28.5, 1=K28.6, 2=K28.7
    input  logic [FRAME_PAYLOAD_BITS-1:0] frame_bytes, // bytes[1..14], byte i at [i*8 +: 8]

    output logic [9:0]                    sym_out,     // to ltpi_symbol_serializer.sym_in
    output logic                          frame_tick   // 1 symbol period before frame boundary
);

    function automatic [7:0] comma_of(input [1:0] sel);
        case (sel)
            2'd0: comma_of = COMMA_K28_5;
            2'd1: comma_of = COMMA_K28_6;
            default: comma_of = COMMA_K28_7;
        endcase
    endfunction

    logic [3:0] byte_idx; // 0..15
    logic       enc_en, enc_k_in;
    logic [7:0] enc_data_in;
    logic       enc_kerr, enc_rd;

    encoder_8b10b u_enc (
        .clk(clk), .rst(rst), .en(enc_en), .k_in(enc_k_in), .data_in(enc_data_in),
        .data_out(sym_out), .k_err(enc_kerr), .rd_state(enc_rd)
    );

    logic       crc_en, crc_init;
    logic [7:0] crc_in, crc_out;

    crc8 u_crc (
        .clk(clk), .rst(rst), .en(crc_en), .init(crc_init), .data_in(crc_in), .crc_out(crc_out)
    );

    // Note: the CRC accumulator consumes frame_bytes[byte_idx] one symbol
    // period "ahead" of the encoder transmitting that same byte (the
    // encoder is busy sending the comma while CRC ingests frame_bytes[0],
    // etc.) so that the checksum is guaranteed ready well before byte_idx
    // reaches 15, when it actually needs to be transmitted.
    always_comb begin
        enc_en     = symbol_tick;
        crc_en     = symbol_tick && (byte_idx <= 4'd13);
        crc_init   = (byte_idx == 4'd0);
        crc_in     = frame_bytes[int'((byte_idx <= 4'd13) ? byte_idx : 4'd13) * 8 +: 8];
        frame_tick = symbol_tick && (byte_idx == 4'd14);

        if (byte_idx == 4'd0) begin
            enc_k_in    = 1'b1;
            enc_data_in = comma_of(comma_sel);
        end else if (byte_idx <= 4'd14) begin
            enc_k_in    = 1'b0;
            enc_data_in = frame_bytes[int'(byte_idx - 4'd1) * 8 +: 8];
        end else begin // byte_idx == 15: transmit checksum
            enc_k_in    = 1'b0;
            enc_data_in = crc_out;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            byte_idx <= 4'd0;
        end else if (symbol_tick) begin
            byte_idx <= (byte_idx == 4'd15) ? 4'd0 : (byte_idx + 4'd1);
        end
    end

endmodule
