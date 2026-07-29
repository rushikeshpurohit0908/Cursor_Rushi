// -----------------------------------------------------------------------------
// LTPI IP for Cyclone V FPGA
// SPDX-License-Identifier: MIT
//
// encoder_8b10b.sv
//
// Clean-room 8b/10b encoder (Widmer & Franaszek / IBM coding scheme, public
// domain algorithm, patent expired) implementing:
//   - All 256 data characters D0.0 .. D31.7
//   - Only the three control characters actually used by LTPI: K28.5, K28.6,
//     K28.7 (comma symbols for Link Detect/Speed, Advertise/Configure/Accept
//     and Operational frames respectively).
//
// This is intentionally NOT a fully generic 8b/10b encoder (it does not
// support K28.0..K28.4, K23.7, K27.7, K29.7 or K30.7) because LTPI never uses
// them; scope is kept to what the protocol requires to reduce complexity and
// risk of transcription errors versus the published coding tables.
//
// Bit convention: data_out[9] is the first bit placed on the wire ("a"),
// data_out[0] is the last bit placed on the wire ("j"), i.e.
//   data_out = { a,b,c,d,e,i, f,g,h,j }
// which mirrors the conventional "abcdei fghj" notation used throughout the
// 8b/10b literature. Running disparity starts at RD- (encoded as 1'b0) after
// reset, per the standard.
// -----------------------------------------------------------------------------

module encoder_8b10b (
    input  logic       clk,
    input  logic       rst,
    input  logic       en,          // consume data_in / advance RD this cycle
    input  logic       k_in,        // 1 = encode data_in as a K28.5/6/7 control symbol
    input  logic [7:0] data_in,
    output logic [9:0] data_out,    // registered, valid the cycle after en
    output logic       k_err,       // k_in asserted with unsupported data_in
    output logic       rd_state     // registered running disparity (0=RD-,1=RD+)
);

    localparam logic RD_NEG = 1'b0;
    localparam logic RD_POS = 1'b1;

    // ------------------------------------------------------------------
    // 5b/6b sub-table: EDCBA -> RD- reference codeword "abcdei"
    // ------------------------------------------------------------------
    function automatic [5:0] neg6_of(input [4:0] x);
        case (x)
            5'd0 : neg6_of = 6'b100111;
            5'd1 : neg6_of = 6'b011101;
            5'd2 : neg6_of = 6'b101101;
            5'd3 : neg6_of = 6'b110001;
            5'd4 : neg6_of = 6'b110101;
            5'd5 : neg6_of = 6'b101001;
            5'd6 : neg6_of = 6'b011001;
            5'd7 : neg6_of = 6'b111000;
            5'd8 : neg6_of = 6'b111001;
            5'd9 : neg6_of = 6'b100101;
            5'd10: neg6_of = 6'b010101;
            5'd11: neg6_of = 6'b110100;
            5'd12: neg6_of = 6'b001101;
            5'd13: neg6_of = 6'b101100;
            5'd14: neg6_of = 6'b011100;
            5'd15: neg6_of = 6'b010111;
            5'd16: neg6_of = 6'b011011;
            5'd17: neg6_of = 6'b100011;
            5'd18: neg6_of = 6'b010011;
            5'd19: neg6_of = 6'b110010;
            5'd20: neg6_of = 6'b001011;
            5'd21: neg6_of = 6'b101010;
            5'd22: neg6_of = 6'b011010;
            5'd23: neg6_of = 6'b111010;
            5'd24: neg6_of = 6'b110011;
            5'd25: neg6_of = 6'b100110;
            5'd26: neg6_of = 6'b010110;
            5'd27: neg6_of = 6'b110110;
            5'd28: neg6_of = 6'b001110;
            5'd29: neg6_of = 6'b101110;
            5'd30: neg6_of = 6'b011110;
            5'd31: neg6_of = 6'b101011;
            default: neg6_of = 6'b000000;
        endcase
    endfunction

    // Sub-blocks whose RD+ codeword is the bit complement of the RD- codeword
    // (i.e. "dual"/disparity-carrying codes). All other x values reuse the
    // same codeword regardless of RD. NOTE: x=7 has equal ones/zeros in its
    // codeword yet is still a dual/switching code - this is a documented
    // exception in the IBM 8b/10b scheme, not a disparity-derived property,
    // so it must be listed explicitly rather than inferred from a bit count.
    function automatic logic is_dual6(input [4:0] x);
        case (x)
            5'd0, 5'd1, 5'd2, 5'd4, 5'd7, 5'd8, 5'd15, 5'd16,
            5'd23, 5'd24, 5'd27, 5'd29, 5'd30, 5'd31: is_dual6 = 1'b1;
            default: is_dual6 = 1'b0;
        endcase
    endfunction

    localparam logic [5:0] K28_NEG6 = 6'b001111; // exclusively used by K28.x

    // ------------------------------------------------------------------
    // 3b/4b sub-table: HGF -> RD- reference codeword "fghj" (D characters,
    // HGF/y = 0..6; y=7 is handled separately below via Primary/Alternate
    // selection). Just like x=7 above, y=3 is a documented dual/switching
    // exception despite having equal ones/zeros.
    // ------------------------------------------------------------------
    function automatic [3:0] neg4_of(input [2:0] y);
        case (y)
            3'd0: neg4_of = 4'b1011;
            3'd1: neg4_of = 4'b1001;
            3'd2: neg4_of = 4'b0101;
            3'd3: neg4_of = 4'b1100;
            3'd4: neg4_of = 4'b1101;
            3'd5: neg4_of = 4'b1010;
            3'd6: neg4_of = 4'b0110;
            default: neg4_of = 4'b0000;
        endcase
    endfunction

    function automatic logic is_dual4(input [2:0] y);
        case (y)
            3'd0, 3'd3, 3'd4: is_dual4 = 1'b1;
            default: is_dual4 = 1'b0;
        endcase
    endfunction

    // Primary/Alternate D.x.7 selection (see spec / Wikipedia 8b/10b tables):
    // Alternate (0111) is used instead of Primary (1110) only for specific
    // EDCBA values, depending on the disparity going into the 3b/4b stage.
    function automatic logic use_alt7(input [4:0] x, input logic rd_mid);
        if (rd_mid == RD_NEG)
            use_alt7 = (x == 5'd17) || (x == 5'd18) || (x == 5'd20);
        else
            use_alt7 = (x == 5'd11) || (x == 5'd13) || (x == 5'd14);
    endfunction

    // ------------------------------------------------------------------
    // K28.5 / K28.6 / K28.7 3b/4b overrides (these differ from the D-code
    // table for the same HGF value, and are always dual/switching)
    // ------------------------------------------------------------------
    function automatic [3:0] neg4_k(input [2:0] y);
        case (y)
            3'd5: neg4_k = 4'b0101; // K28.5
            3'd6: neg4_k = 4'b1001; // K28.6
            3'd7: neg4_k = 4'b0111; // K28.7 (matches D.x.A7)
            default: neg4_k = 4'b0000;
        endcase
    endfunction

    logic [4:0] x;
    logic [2:0] y;
    logic [5:0] neg6, code6;
    logic [3:0] neg4, code4;
    logic       dual6, dual4;
    logic       rd_mid, rd_next;
    logic       k_valid;

    always_comb begin
        x = data_in[4:0];
        y = data_in[7:5];
        k_valid = (data_in == 8'hBC) || (data_in == 8'hDC) || (data_in == 8'hFC);

        if (k_in) begin
            neg6  = K28_NEG6;
            dual6 = 1'b1;
        end else begin
            neg6  = neg6_of(x);
            dual6 = is_dual6(x);
        end

        code6  = dual6 ? ((rd_state == RD_NEG) ? neg6 : ~neg6) : neg6;
        rd_mid = dual6 ? ~rd_state : rd_state;

        if (k_in) begin
            neg4  = neg4_k(y);
            dual4 = 1'b1;
        end else if (y == 3'd7) begin
            neg4  = use_alt7(x, rd_mid) ? 4'b0111 : 4'b1110;
            dual4 = 1'b1;
        end else begin
            neg4  = neg4_of(y);
            dual4 = is_dual4(y);
        end

        code4   = dual4 ? ((rd_mid == RD_NEG) ? neg4 : ~neg4) : neg4;
        rd_next = dual4 ? ~rd_mid : rd_mid;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_out <= 10'h0;
            k_err    <= 1'b0;
            rd_state <= RD_NEG;
        end else if (en) begin
            data_out <= {code6, code4};
            k_err    <= k_in && !k_valid;
            rd_state <= (k_in && !k_valid) ? rd_state : rd_next;
        end
    end

endmodule
