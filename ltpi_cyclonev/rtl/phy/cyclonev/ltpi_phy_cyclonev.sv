// -----------------------------------------------------------------------------
// LTPI IP for Cyclone V FPGA - SPDX-License-Identifier: MIT
//
// ltpi_phy_cyclonev.sv
//
// Thin Cyclone V I/O wrapper around ltpi_top's bit-serial interface for the
// mandatory baseline LTPI rate (Base Frequency x1, 25MHz SDR - one bit per
// clk_link edge). At this modest rate no dedicated SERDES/DDIO primitive is
// required: a plain register at the I/O boundary is automatically packed
// into the Cyclone V IOE output/input register by the Quartus fitter as long
// as the pin is assigned an LVDS I/O standard and the register is the only
// logic between the pin and clk_link (true LVDS output buffers on Cyclone V
// cannot be tri-stated, which is fine here since LTPI drives its output
// continuously).
//
// `rx_bit` is sampled with a 2-flop synchronizer for metastability hardening.
// This is adequate when clk_link_rx below is generated from the *same*
// reference clock as the local clk_link (shared/mesochronous clocking, a
// common LTPI board arrangement); see docs/ARCHITECTURE.md for the fully
// asynchronous (independently clocked partner) alternative, which needs a
// second PLL locked to the incoming LVDS_RX_CLK pin plus a frame-level CDC
// crossing (ltpi_frame_rx's outputs change slowly - about once per 160 bit
// periods - so a toggle-handshake synchronizer is sufficient there; see the
// architecture doc for the recommended structure).
//
// For higher link speeds (DDR / multiple x Base Frequency), replace the
// plain output/input registers below with altddio_out / altddio_in
// megafunction instances (2 bits per clk_link edge) and a matching x2
// clk_link frequency from cv_pll.sv; ltpi_top.sv's protocol layer above this
// PHY does not need to change; only the bit-serialization would need to
// double up before/after this wrapper, which is left as an extension point.
// -----------------------------------------------------------------------------

module ltpi_phy_cyclonev (
    input  logic clk_link,
    input  logic rst,

    // Core-facing (ltpi_top.sv)
    input  logic core_tx_bit,
    output logic core_rx_bit,

    // Pin-facing (assign LVDS I/O standard + pin location in the Quartus .qsf)
    output logic pin_tx_data,
    output logic pin_tx_clk,
    input  logic pin_rx_data
);

    // ---- TX: register the bit and forward the link clock ----
    always_ff @(posedge clk_link or posedge rst) begin
        if (rst) pin_tx_data <= 1'b0;
        else     pin_tx_data <= core_tx_bit;
    end

    assign pin_tx_clk = clk_link;

    // ---- RX: 2-flop metastability synchronizer ----
    logic rx_meta;
    always_ff @(posedge clk_link or posedge rst) begin
        if (rst) begin
            rx_meta      <= 1'b0;
            core_rx_bit  <= 1'b0;
        end else begin
            rx_meta     <= pin_rx_data;
            core_rx_bit <= rx_meta;
        end
    end

endmodule
