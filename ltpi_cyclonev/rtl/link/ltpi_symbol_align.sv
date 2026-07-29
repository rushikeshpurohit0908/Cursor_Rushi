// -----------------------------------------------------------------------------
// LTPI IP for Cyclone V FPGA - SPDX-License-Identifier: MIT
//
// ltpi_symbol_align.sv
//
// Generic (vendor-agnostic) bit-to-symbol aligner. While unlocked, it scans
// every bit position for any of the six known LTPI comma bit patterns
// (K28.5/K28.6/K28.7, either running-disparity polarity); a match
// establishes the 10-bit symbol boundary. Once locked, alignment is held by
// simply free-running a /10 bit counter rather than continuing to search for
// commas on every cycle.
//
// Note this deliberately does NOT keep re-triggering on comma sightings
// after lock: K28.5/K28.1 are "safe" commas that provably cannot appear at a
// misaligned bit offset within a stream of validly encoded symbols, but
// K28.7 (used by LTPI Operational frames) does not have that guarantee -
// combined with certain neighbouring symbols it can form a false comma
// pattern that straddles a real symbol boundary (this is a documented
// property of 8b/10b, see e.g. the "Control symbols" notes in the public
// IBM 8b/10b coding tables). LTPI link bring-up always establishes bit
// alignment using K28.5 first (Link Detect/Speed stage) before any K28.7
// traffic is ever sent, so searching only until the first lock and then
// trusting the established phase (re-acquiring only via an external reset,
// e.g. issued by ltpi_link_ctrl.sv after a Link Lost event) is both
// sufficient and immune to the K28.7 false-comma edge case.
// -----------------------------------------------------------------------------

module ltpi_symbol_align (
    input  logic       clk,
    input  logic       rst,
    input  logic       rx_bit,      // one bit sampled per clk
    output logic [9:0] sym_out,     // registered, valid when sym_valid pulses
    output logic        sym_valid,
    output logic        bit_locked  // 1 once at least one comma has been found
);

    localparam [9:0] PAT_K28_5_NEG = 10'b0011111010;
    localparam [9:0] PAT_K28_5_POS = 10'b1100000101;
    localparam [9:0] PAT_K28_6_NEG = 10'b0011110110;
    localparam [9:0] PAT_K28_6_POS = 10'b1100001001;
    localparam [9:0] PAT_K28_7_NEG = 10'b0011111000;
    localparam [9:0] PAT_K28_7_POS = 10'b1100000111;

    function automatic logic is_comma(input [9:0] w);
        is_comma = (w == PAT_K28_5_NEG) || (w == PAT_K28_5_POS) ||
                   (w == PAT_K28_6_NEG) || (w == PAT_K28_6_POS) ||
                   (w == PAT_K28_7_NEG) || (w == PAT_K28_7_POS);
    endfunction

    logic [8:0] window;
    logic [3:0] phase_cnt;
    logic       locked;
    logic [9:0] candidate;

    assign candidate  = {window, rx_bit};
    assign bit_locked = locked;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            window    <= 9'd0;
            phase_cnt <= 4'd0;
            locked    <= 1'b0;
            sym_valid <= 1'b0;
            sym_out   <= 10'd0;
        end else begin
            sym_valid <= 1'b0;

            if (!locked) begin
                if (is_comma(candidate)) begin
                    locked    <= 1'b1;
                    phase_cnt <= 4'd0;
                    sym_out   <= candidate;
                    sym_valid <= 1'b1;
                end
            end else begin
                if (phase_cnt == 4'd9) begin
                    phase_cnt <= 4'd0;
                    sym_out   <= candidate;
                    sym_valid <= 1'b1;
                end else begin
                    phase_cnt <= phase_cnt + 4'd1;
                end
            end

            window <= candidate[8:0];
        end
    end

endmodule
