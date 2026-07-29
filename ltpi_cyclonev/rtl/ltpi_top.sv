// -----------------------------------------------------------------------------
// LTPI IP for Cyclone V FPGA - SPDX-License-Identifier: MIT
//
// ltpi_top.sv
//
// Top-level LTPI core: wires together the bit-serial PHY interface (tx_bit /
// rx_bit, one clock domain, see docs/ARCHITECTURE.md for the CDC
// simplification this implies), the protocol layer (serializer/aligner,
// frame tx/rx, link training FSM) and the GPIO channel. Usable for either
// LTPI role (HPM/Controller or SCM/Target); the ROLE parameter is currently
// only informational (see ltpi_link_ctrl.sv), reserved for future
// role-specific behavior (e.g. distinct Configure/Accept semantics).
//
// `clk` is expected to be the recovered/generated LTPI link clock (see
// rtl/phy/cyclonev/cv_pll.sv), i.e. this module operates entirely in the
// link-bit-rate clock domain, not the host fabric's general-purpose clock.
// -----------------------------------------------------------------------------

import ltpi_pkg::*;

module ltpi_top #(
    parameter ltpi_role_e ROLE = LTPI_ROLE_CONTROLLER
) (
    input  logic clk,
    input  logic rst,

    // ---- Bit-serial LTPI PHY interface ----
    output logic tx_bit,
    input  logic rx_bit,

    // ---- GPIO channel (Default I/O Frame) ----
    input  logic [7:0] gpio_ll_tx,   // Low-Latency GPIOs to send, sampled every frame
    input  logic [7:0] gpio_nl_tx,   // Normal-Latency GPIOs to send
    output logic [7:0] gpio_ll_rx,   // Low-Latency GPIOs received from peer
    output logic [7:0] gpio_nl_rx,   // Normal-Latency GPIOs received from peer

    // ---- Diagnostics ----
    output ltpi_link_state_e link_state,
    output logic             link_up,
    output logic [15:0]      crc_error_count
);

    // ---- Double-flop synchronizers on the GPIO inputs (they typically come
    //      from asynchronous board-level sources / a different clock domain) ----
    logic [7:0] gpio_ll_tx_meta, gpio_ll_tx_sync;
    logic [7:0] gpio_nl_tx_meta, gpio_nl_tx_sync;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            gpio_ll_tx_meta <= 8'h00; gpio_ll_tx_sync <= 8'h00;
            gpio_nl_tx_meta <= 8'h00; gpio_nl_tx_sync <= 8'h00;
        end else begin
            gpio_ll_tx_meta <= gpio_ll_tx;   gpio_ll_tx_sync <= gpio_ll_tx_meta;
            gpio_nl_tx_meta <= gpio_nl_tx;   gpio_nl_tx_sync <= gpio_nl_tx_meta;
        end
    end

    // ---- TX path ----
    logic [1:0] tx_comma_sel;
    logic [FRAME_PAYLOAD_BITS-1:0] tx_frame_bytes;
    logic [9:0] tx_sym;
    logic       tx_symbol_tick, tx_frame_tick;

    ltpi_frame_tx u_frame_tx (
        .clk(clk), .rst(rst), .symbol_tick(tx_symbol_tick),
        .comma_sel(tx_comma_sel), .frame_bytes(tx_frame_bytes),
        .sym_out(tx_sym), .frame_tick(tx_frame_tick)
    );

    ltpi_symbol_serializer u_serializer (
        .clk(clk), .rst(rst), .sym_in(tx_sym),
        .symbol_tick(tx_symbol_tick), .tx_bit(tx_bit)
    );

    // ---- RX path ----
    logic [9:0] rx_sym;
    logic       rx_sym_valid, rx_bit_locked;

    ltpi_symbol_align u_aligner (
        .clk(clk), .rst(rst), .rx_bit(rx_bit),
        .sym_out(rx_sym), .sym_valid(rx_sym_valid), .bit_locked(rx_bit_locked)
    );

    logic                          rx_frame_valid;
    logic [7:0]                    rx_comma_byte;
    logic                          rx_crc_ok;
    logic [FRAME_PAYLOAD_BITS-1:0] rx_frame_bytes;

    ltpi_frame_rx u_frame_rx (
        .clk(clk), .rst(rst), .sym_in(rx_sym), .sym_valid(rx_sym_valid),
        .frame_valid(rx_frame_valid), .comma_byte(rx_comma_byte), .crc_ok(rx_crc_ok),
        .frame_bytes(rx_frame_bytes)
    );

    // ---- Link training / operational FSM ----
    logic [7:0] frame_counter_diag;

    ltpi_link_ctrl u_link_ctrl (
        .clk(clk), .rst(rst),
        .tx_frame_tick(tx_frame_tick), .tx_comma_sel(tx_comma_sel), .tx_frame_bytes(tx_frame_bytes),
        .rx_frame_valid(rx_frame_valid), .rx_comma_byte(rx_comma_byte), .rx_crc_ok(rx_crc_ok),
        .rx_frame_bytes(rx_frame_bytes),
        .ll_gpio_tx(gpio_ll_tx_sync), .nl_gpio_tx(gpio_nl_tx_sync),
        .ll_gpio_rx(gpio_ll_rx), .nl_gpio_rx(gpio_nl_rx),
        .link_state(link_state), .link_up(link_up),
        .frame_counter(frame_counter_diag), .crc_error_count(crc_error_count)
    );

endmodule
