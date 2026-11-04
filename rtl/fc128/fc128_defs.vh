// Shared constants for the FC128 PoC datapath.
//
// A control block carries an FC-FS ordered set in [31:0], first character in
// [7:0]. The bytes are the FC-FS / FC-PH transmission characters (K28.5 plus
// three data characters), not an internal code. EOF has a second form for
// positive beginning running disparity; both forms are recognized. The 64-bit
// container is this bridge's block. CSR bit 5 packs four of them into a
// Clause 119 256b/257b word on the system lanes (fc_xcode.vh). K28.5
// restores as 0xBC.

localparam [1:0] FC_SYNC_DATA = 2'b01;
localparam [1:0] FC_SYNC_CTRL = 2'b10;

localparam [7:0] FC_K28_5 = 8'hBC;
localparam [7:0] FC_D5_2  = 8'h45;
localparam [7:0] FC_D9_2  = 8'h49;
localparam [7:0] FC_D10_2 = 8'h4A;
localparam [7:0] FC_D10_4 = 8'h8A;
localparam [7:0] FC_D10_5 = 8'hAA;
localparam [7:0] FC_D21_1 = 8'h35;
localparam [7:0] FC_D21_2 = 8'h55;
localparam [7:0] FC_D21_3 = 8'h75;
localparam [7:0] FC_D21_4 = 8'h95;
localparam [7:0] FC_D21_5 = 8'hB5;
localparam [7:0] FC_D21_6 = 8'hD5;
localparam [7:0] FC_D21_7 = 8'hF5;
localparam [7:0] FC_D22_1 = 8'h36;
localparam [7:0] FC_D22_2 = 8'h56;
localparam [7:0] FC_D23_0 = 8'h17;
localparam [7:0] FC_D23_1 = 8'h37;
localparam [7:0] FC_D23_2 = 8'h57;
localparam [7:0] FC_D24_2 = 8'h58;
localparam [7:0] FC_D25_0 = 8'h19;
localparam [7:0] FC_D25_1 = 8'h39;
localparam [7:0] FC_D25_2 = 8'h59;
localparam [7:0] FC_D31_5 = 8'hBF;

// Primitive signals. Negative beginning running disparity.
localparam [31:0] FC_IDLE = {FC_D21_5, FC_D21_5, FC_D21_4, FC_K28_5}; // BC 95 B5 B5
localparam [31:0] FC_RRDY = {FC_D10_2, FC_D10_2, FC_D21_4, FC_K28_5}; // BC 95 4A 4A

// Primitive sequences. NOS, then OLS -> LR -> LRR -> Idle.
localparam [31:0] FC_NOS = {FC_D5_2,  FC_D31_5, FC_D21_2, FC_K28_5}; // BC 55 BF 45
localparam [31:0] FC_OLS = {FC_D21_2, FC_D10_4, FC_D21_1, FC_K28_5}; // BC 35 8A 55
localparam [31:0] FC_LR  = {FC_D9_2,  FC_D31_5, FC_D9_2,  FC_K28_5}; // BC 49 BF 49
localparam [31:0] FC_LRR = {FC_D9_2,  FC_D31_5, FC_D21_1, FC_K28_5}; // BC 35 BF 49

// SOF delimiters. Negative beginning running disparity only.
localparam [31:0] FC_SOFC1 = {FC_D23_0, FC_D23_0, FC_D21_5, FC_K28_5}; // BC B5 17 17
localparam [31:0] FC_SOFI1 = {FC_D23_2, FC_D23_2, FC_D21_5, FC_K28_5}; // BC B5 57 57
localparam [31:0] FC_SOFN1 = {FC_D23_1, FC_D23_1, FC_D21_5, FC_K28_5}; // BC B5 37 37
localparam [31:0] FC_SOFI2 = {FC_D21_2, FC_D21_2, FC_D21_5, FC_K28_5}; // BC B5 55 55
localparam [31:0] FC_SOFN2 = {FC_D21_1, FC_D21_1, FC_D21_5, FC_K28_5}; // BC B5 35 35
localparam [31:0] FC_SOFI3 = {FC_D22_2, FC_D22_2, FC_D21_5, FC_K28_5}; // BC B5 56 56
localparam [31:0] FC_SOFN3 = {FC_D22_1, FC_D22_1, FC_D21_5, FC_K28_5}; // BC B5 36 36
localparam [31:0] FC_SOFC4 = {FC_D25_0, FC_D25_0, FC_D21_5, FC_K28_5}; // BC B5 19 19
localparam [31:0] FC_SOFI4 = {FC_D25_2, FC_D25_2, FC_D21_5, FC_K28_5}; // BC B5 59 59
localparam [31:0] FC_SOFN4 = {FC_D25_1, FC_D25_1, FC_D21_5, FC_K28_5}; // BC B5 39 39
localparam [31:0] FC_SOFF  = {FC_D24_2, FC_D24_2, FC_D21_5, FC_K28_5}; // BC B5 58 58

// EOF delimiters. _P is the positive beginning-running-disparity form.
localparam [31:0] FC_EOFT    = {FC_D21_3, FC_D21_3, FC_D21_4, FC_K28_5}; // BC 95 75 75
localparam [31:0] FC_EOFT_P  = {FC_D21_3, FC_D21_3, FC_D21_5, FC_K28_5}; // BC B5 75 75
localparam [31:0] FC_EOFDT   = {FC_D21_4, FC_D21_4, FC_D21_4, FC_K28_5}; // BC 95 95 95
localparam [31:0] FC_EOFDT_P = {FC_D21_4, FC_D21_4, FC_D21_5, FC_K28_5}; // BC B5 95 95
localparam [31:0] FC_EOFA    = {FC_D21_7, FC_D21_7, FC_D21_4, FC_K28_5}; // BC 95 F5 F5
localparam [31:0] FC_EOFA_P  = {FC_D21_7, FC_D21_7, FC_D21_5, FC_K28_5}; // BC B5 F5 F5
localparam [31:0] FC_EOFN    = {FC_D21_6, FC_D21_6, FC_D21_4, FC_K28_5}; // BC 95 D5 D5
localparam [31:0] FC_EOFN_P  = {FC_D21_6, FC_D21_6, FC_D21_5, FC_K28_5}; // BC B5 D5 D5
localparam [31:0] FC_EOFDTI   = {FC_D21_4, FC_D21_4, FC_D10_4, FC_K28_5}; // BC 8A 95 95
localparam [31:0] FC_EOFDTI_P = {FC_D21_4, FC_D21_4, FC_D10_5, FC_K28_5}; // BC AA 95 95
localparam [31:0] FC_EOFNI    = {FC_D21_6, FC_D21_6, FC_D10_4, FC_K28_5}; // BC 8A D5 D5
localparam [31:0] FC_EOFNI_P  = {FC_D21_6, FC_D21_6, FC_D10_5, FC_K28_5}; // BC AA D5 D5

// Delimiters this bridge transmits. One frame is a Class 3 sequence.
localparam [31:0] FC_SOF = FC_SOFI3;
localparam [31:0] FC_EOF = FC_EOFT;

// Per-port line rate, CSR 0x218 + 32*port bits [1:0].
// 128GFC stripes a 112.2G client across two 58G lanes.
// 64GFC keeps lane 0 only (57.8G on one 58G lane).
// 32GFC keeps lane 0 and inserts one IDLE after every 66-bit block so a
// 28.05G client fills half of that lane. The IDLE is removed after the
// system transcode. 2'b11 is reserved and is stored as 128GFC.
localparam [1:0] FC_RATE_128 = 2'b00;
localparam [1:0] FC_RATE_64  = 2'b01;
localparam [1:0] FC_RATE_32  = 2'b10;

// fc_link_sm state codes. Active is the only state that passes frames.
localparam [2:0] FC_LS_DOWN = 3'd0;
localparam [2:0] FC_LS_OLS  = 3'd1;
localparam [2:0] FC_LS_LR   = 3'd2;
localparam [2:0] FC_LS_LRR  = 3'd3;
localparam [2:0] FC_LS_ACQ  = 3'd4;
localparam [2:0] FC_LS_ACT  = 3'd5;

// SOF layout: {16'h0, length[15:0], ordered_set[31:0]}
// EOF layout: {crc32[31:0], ordered_set[31:0]}
// Other primitives: {32'h0, ordered_set[31:0]}
// length is the FC payload in bytes. When FEC is enabled the codeword on the
// wire is length+16 and the CRC covers the length payload bytes only.

function automatic logic fc_is_sof(input [31:0] os);
  begin
    fc_is_sof = (os == FC_SOFC1) || (os == FC_SOFI1) || (os == FC_SOFN1) ||
                (os == FC_SOFI2) || (os == FC_SOFN2) || (os == FC_SOFI3) ||
                (os == FC_SOFN3) || (os == FC_SOFC4) || (os == FC_SOFI4) ||
                (os == FC_SOFN4) || (os == FC_SOFF);
  end
endfunction

// EOFt, EOFn, and EOFdt end a frame that is still checked for CRC.
function automatic logic fc_is_eof_good(input [31:0] os);
  begin
    fc_is_eof_good = (os == FC_EOFT) || (os == FC_EOFT_P) ||
                     (os == FC_EOFN) || (os == FC_EOFN_P) ||
                     (os == FC_EOFDT) || (os == FC_EOFDT_P);
  end
endfunction

// Abort and invalid EOF discard the frame.
function automatic logic fc_is_eof_bad(input [31:0] os);
  begin
    fc_is_eof_bad = (os == FC_EOFA) || (os == FC_EOFA_P) ||
                    (os == FC_EOFNI) || (os == FC_EOFNI_P) ||
                    (os == FC_EOFDTI) || (os == FC_EOFDTI_P);
  end
endfunction
