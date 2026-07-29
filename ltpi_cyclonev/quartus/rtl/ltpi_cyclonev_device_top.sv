// -----------------------------------------------------------------------------
// LTPI IP for Cyclone V FPGA - SPDX-License-Identifier: MIT
//
// ltpi_cyclonev_device_top.sv
//
// Example device-level top level for synthesizing the LTPI IP for a Cyclone V
// FPGA in Quartus Prime: reference clock in, LVDS TX/RX pins, GPIO pins.
// Adjust pin names/widths and the ROLE parameter to match your board, and
// assign real pin locations + I/O standards in ltpi_cyclonev.qsf.
// -----------------------------------------------------------------------------

import ltpi_pkg::*;

module ltpi_cyclonev_device_top #(
    parameter ltpi_role_e ROLE       = LTPI_ROLE_CONTROLLER,
    parameter int         REF_CLK_MHZ  = 50,
    parameter int         LINK_FREQ_MHZ = 25
) (
    input  logic REF_CLK,
    input  logic RESET_N,

    // LVDS pair to the LTPI link partner
    output logic LTPI_TX_D,
    output logic LTPI_TX_CLK,
    input  logic LTPI_RX_D,

    // Example GPIO channel pins (customize freely)
    input  logic [7:0] GPIO_LL_IN,
    input  logic [7:0] GPIO_NL_IN,
    output logic [7:0] GPIO_LL_OUT,
    output logic [7:0] GPIO_NL_OUT,

    // Diagnostics
    output logic LINK_UP_LED
);

    logic clk_link, pll_locked;
    logic rst;

    cv_pll #(
        .REF_CLK_MHZ(REF_CLK_MHZ),
        .LINK_FREQ_MHZ(LINK_FREQ_MHZ),
        .SIM_BEHAVIORAL(0)
    ) u_pll (
        .ref_clk(REF_CLK), .rst(~RESET_N), .clk_link(clk_link), .locked(pll_locked)
    );

    assign rst = ~RESET_N | ~pll_locked;

    logic core_tx_bit, core_rx_bit;

    ltpi_phy_cyclonev u_phy (
        .clk_link(clk_link), .rst(rst),
        .core_tx_bit(core_tx_bit), .core_rx_bit(core_rx_bit),
        .pin_tx_data(LTPI_TX_D), .pin_tx_clk(LTPI_TX_CLK), .pin_rx_data(LTPI_RX_D)
    );

    ltpi_link_state_e link_state;
    logic             link_up;
    logic [15:0]      crc_error_count;

    ltpi_top #(.ROLE(ROLE)) u_ltpi (
        .clk(clk_link), .rst(rst),
        .tx_bit(core_tx_bit), .rx_bit(core_rx_bit),
        .gpio_ll_tx(GPIO_LL_IN), .gpio_nl_tx(GPIO_NL_IN),
        .gpio_ll_rx(GPIO_LL_OUT), .gpio_nl_rx(GPIO_NL_OUT),
        .link_state(link_state), .link_up(link_up), .crc_error_count(crc_error_count)
    );

    assign LINK_UP_LED = link_up;

endmodule
