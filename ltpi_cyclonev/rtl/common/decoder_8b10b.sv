// -----------------------------------------------------------------------------
// LTPI IP for Cyclone V FPGA
// SPDX-License-Identifier: MIT
//
// decoder_8b10b.sv
//
// Companion decoder for encoder_8b10b.sv. Reverses the 10-bit "abcdei fghj"
// symbol (data_in[9]=a first-received .. data_in[0]=j last-received) back to
// the original 8-bit byte, recognizing only the K28.5/K28.6/K28.7 control
// symbols used by LTPI (all other K-codes are treated as an unsupported code
// and flagged via code_err).
//
// Byte decoding does not depend on running disparity (each valid 6-bit/4-bit
// pattern maps to exactly one x/y regardless of which polarity produced it),
// so no disparity bookkeeping is required for correct operation. This is a
// deliberate scope reduction versus a fully generic 8b/10b decoder: disparity
// error detection is not implemented, only code validity checking.
// -----------------------------------------------------------------------------

module decoder_8b10b (
    input  logic       clk,
    input  logic       rst,
    input  logic       en,
    input  logic [9:0] data_in,
    output logic [7:0] data_out,   // registered, valid the cycle after en
    output logic       k_out,      // 1 = data_out is a K28.5/6/7 comma symbol
    output logic       code_err    // 1 = data_in is not a supported D or K code
);

    localparam logic [9:0] K28_5_NEG = 10'b00_1111_1010;
    localparam logic [9:0] K28_5_POS = 10'b11_0000_0101;
    localparam logic [9:0] K28_6_NEG = 10'b00_1111_0110;
    localparam logic [9:0] K28_6_POS = 10'b11_0000_1001;
    localparam logic [9:0] K28_7_NEG = 10'b00_1111_1000;
    localparam logic [9:0] K28_7_POS = 10'b11_0000_0111;

    // 6-bit "abcdei" -> EDCBA reverse lookup (see encoder_8b10b.sv for the
    // forward table this mirrors). Return value: bit[5]=valid, bits[4:0]=x.
    function automatic [5:0] decode6(input [5:0] code);
        logic       ok;
        logic [4:0] x;
        begin
            ok = 1'b1;
            case (code)
                6'b100111, 6'b011000: x = 5'd0;
                6'b011101, 6'b100010: x = 5'd1;
                6'b101101, 6'b010010: x = 5'd2;
                6'b110001            : x = 5'd3;
                6'b110101, 6'b001010: x = 5'd4;
                6'b101001            : x = 5'd5;
                6'b011001            : x = 5'd6;
                6'b111000, 6'b000111: x = 5'd7;
                6'b111001, 6'b000110: x = 5'd8;
                6'b100101            : x = 5'd9;
                6'b010101            : x = 5'd10;
                6'b110100            : x = 5'd11;
                6'b001101            : x = 5'd12;
                6'b101100            : x = 5'd13;
                6'b011100            : x = 5'd14;
                6'b010111, 6'b101000: x = 5'd15;
                6'b011011, 6'b100100: x = 5'd16;
                6'b100011            : x = 5'd17;
                6'b010011            : x = 5'd18;
                6'b110010            : x = 5'd19;
                6'b001011            : x = 5'd20;
                6'b101010            : x = 5'd21;
                6'b011010            : x = 5'd22;
                6'b111010, 6'b000101: x = 5'd23;
                6'b110011, 6'b001100: x = 5'd24;
                6'b100110            : x = 5'd25;
                6'b010110            : x = 5'd26;
                6'b110110, 6'b001001: x = 5'd27;
                6'b001110            : x = 5'd28;
                6'b101110, 6'b010001: x = 5'd29;
                6'b011110, 6'b100001: x = 5'd30;
                6'b101011, 6'b010100: x = 5'd31;
                default: begin ok = 1'b0; x = 5'bxxxxx; end
            endcase
            decode6 = {ok, x};
        end
    endfunction

    // 4-bit "fghj" -> HGF reverse lookup. y=7 folds both the Primary
    // (1110/0001) and Alternate (0111/1000) encodings to the same value.
    // Return value: bit[3]=valid, bits[2:0]=y.
    function automatic [3:0] decode4(input [3:0] code);
        logic       ok;
        logic [2:0] y;
        begin
            ok = 1'b1;
            case (code)
                4'b1011, 4'b0100: y = 3'd0;
                4'b1001            : y = 3'd1;
                4'b0101            : y = 3'd2;
                4'b1100, 4'b0011: y = 3'd3;
                4'b1101, 4'b0010: y = 3'd4;
                4'b1010            : y = 3'd5;
                4'b0110            : y = 3'd6;
                4'b1110, 4'b0001, 4'b0111, 4'b1000: y = 3'd7;
                default: begin ok = 1'b0; y = 3'bxxx; end
            endcase
            decode4 = {ok, y};
        end
    endfunction

    logic [4:0] x;
    logic [2:0] y;
    logic       x_ok, y_ok;
    logic       is_k;
    logic [7:0] k_byte;
    logic [5:0] dec6_r;
    logic [3:0] dec4_r;

    always_comb begin
        is_k   = 1'b1;
        k_byte = 8'h00;
        case (data_in)
            K28_5_NEG, K28_5_POS: k_byte = 8'hBC;
            K28_6_NEG, K28_6_POS: k_byte = 8'hDC;
            K28_7_NEG, K28_7_POS: k_byte = 8'hFC;
            default: is_k = 1'b0;
        endcase

        dec6_r = decode6(data_in[9:4]);
        dec4_r = decode4(data_in[3:0]);
        x_ok   = dec6_r[5];
        x      = dec6_r[4:0];
        y_ok   = dec4_r[3];
        y      = dec4_r[2:0];
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 8'h00;
            k_out    <= 1'b0;
            code_err <= 1'b0;
        end else if (en) begin
            if (is_k) begin
                data_out <= k_byte;
                k_out    <= 1'b1;
                code_err <= 1'b0;
            end else if (x_ok && y_ok) begin
                data_out <= {y, x};
                k_out    <= 1'b0;
                code_err <= 1'b0;
            end else begin
                data_out <= 8'h00;
                k_out    <= 1'b0;
                code_err <= 1'b1;
            end
        end
    end

endmodule
