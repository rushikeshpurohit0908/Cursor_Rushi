// -----------------------------------------------------------------------------
// LTPI IP for Cyclone V FPGA - SPDX-License-Identifier: MIT
//
// cv_pll.sv
//
// Generates the LTPI link clock for a Cyclone V device from a board
// reference clock.
//
// IMPORTANT: the ALTPLL instantiation below is a reasonable starting point
// (single output clock, integer multiply/divide) but PLL parameters are
// device/speed-grade/board specific. Before synthesizing for real hardware:
//   1. Open Quartus Prime -> IP Catalog -> "PLL" (or MegaWizard "ALTPLL")
//   2. Target your exact Cyclone V part/speed grade and reference clock
//      frequency, request one output clock at LINK_FREQ_MHZ, and let Quartus
//      regenerate this module (or a wrapper you instantiate from cv_pll's
//      call site) with verified multiply/divide/phase settings.
//   3. Re-run TimeQuest timing analysis to confirm the generated clock meets
//      your target frequency and jitter budget.
//
// For quick bring-up or simulation-only use where a jitter-clean clock is
// not required, set SIM_BEHAVIORAL=1 to fall back to a simple integer clock
// divider instead of instantiating the ALTPLL megafunction (useful in
// environments without access to the Quartus/ALTPLL simulation library).
// -----------------------------------------------------------------------------

module cv_pll #(
    parameter int REF_CLK_MHZ  = 50,  // board reference oscillator frequency
    parameter int LINK_FREQ_MHZ = 25, // desired LTPI link (bit) clock frequency
    parameter bit SIM_BEHAVIORAL = 0  // 1 = plain clock divider (sim/bring-up only)
) (
    input  logic ref_clk,
    input  logic rst,
    output logic clk_link,
    output logic locked
);

    generate
        if (SIM_BEHAVIORAL) begin : gen_behavioral
            // Simple integer divider fallback. Only exact when
            // REF_CLK_MHZ is an even multiple of LINK_FREQ_MHZ.
            localparam int DIV = (REF_CLK_MHZ >= 2 * LINK_FREQ_MHZ) ?
                                  (REF_CLK_MHZ / LINK_FREQ_MHZ) : 2;
            localparam int HALF = (DIV < 2) ? 1 : (DIV / 2);

            logic [15:0] cnt;
            logic        div_clk;

            always_ff @(posedge ref_clk or posedge rst) begin
                if (rst) begin
                    cnt     <= 16'd0;
                    div_clk <= 1'b0;
                end else if (cnt == HALF - 1) begin
                    cnt     <= 16'd0;
                    div_clk <= ~div_clk;
                end else begin
                    cnt <= cnt + 16'd1;
                end
            end

            assign clk_link = div_clk;

            logic [3:0] lock_cnt;
            always_ff @(posedge ref_clk or posedge rst) begin
                if (rst) begin
                    lock_cnt <= 4'd0;
                    locked   <= 1'b0;
                end else if (!locked) begin
                    lock_cnt <= lock_cnt + 4'd1;
                    locked   <= (lock_cnt == 4'hF);
                end
            end
        end else begin : gen_altpll
            // Placeholder ALTPLL instantiation - regenerate via Quartus IP
            // Catalog for your target device/speed grade before synthesis.
            wire pll_locked;
            wire [5:0] pll_clk; // c0..c5; only clk[0] (c0) is used here

            altpll #(
                .intended_device_family("Cyclone V"),
                .operation_mode("NORMAL"),
                .inclk0_input_frequency(1_000_000_000 / REF_CLK_MHZ), // ps
                .clk0_divide_by(REF_CLK_MHZ),
                .clk0_multiply_by(LINK_FREQ_MHZ),
                .clk0_phase_shift("0"),
                .pll_type("AUTO"),
                .lpm_type("altpll")
            ) u_altpll (
                .inclk    ({1'b0, ref_clk}),
                .areset   (rst),
                .clk      (pll_clk),
                .locked   (pll_locked),
                .fbin     (1'b1),
                .pllena   (1'b1),
                .clkena   (6'b111111)
            );

            assign clk_link = pll_clk[0];
            assign locked   = pll_locked;
        end
    endgenerate

endmodule
