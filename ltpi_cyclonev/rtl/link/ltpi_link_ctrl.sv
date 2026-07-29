// -----------------------------------------------------------------------------
// LTPI IP for Cyclone V FPGA - SPDX-License-Identifier: MIT
//
// ltpi_link_ctrl.sv
//
// LTPI link training and operational state machine. Both link partners run
// this identical FSM; it advances Detect -> Speed -> Advertise -> Configure
// -> Accept -> Operational once it has observed TRAIN_GOOD_FRAMES
// consecutive, correctly-CRC'd received frames matching its *own* current
// stage (this assumes both sides begin training at roughly the same time,
// which is the normal LTPI bring-up scenario; re-synchronizing with a peer
// that is already further ahead mid-training is a documented simplification
// / extension point, see docs/ARCHITECTURE.md).
//
// Scope simplifications versus the full DC-SCM LTPI specification:
//   - Only one link speed (Base Frequency x1, 25MHz SDR) is advertised or
//     accepted - the specification's mandatory minimum.
//   - Capabilities are fixed (8 Low-Latency + 8 Normal-Latency GPIOs only;
//     UART/I2C/SMBus/Data/OEM channel bytes are transmitted as zero and
//     received values are exposed on ltpi_top.sv for future extension).
//   - Normal-Latency GPIOs use a 1:1 mapping (Frame Counter is transmitted
//     but not required to decode NL GPIO identity), rather than the
//     multi-frame "virtual GPIO" windowing scheme in section 2.2.1.1 of the
//     specification (which supports more NL GPIOs than fit in one frame).
// -----------------------------------------------------------------------------

import ltpi_pkg::*;

module ltpi_link_ctrl (
    input  logic       clk,
    input  logic       rst,

    // TX side (drives ltpi_frame_tx)
    input  logic       tx_frame_tick,
    output logic [1:0] tx_comma_sel,
    output logic [FRAME_PAYLOAD_BITS-1:0] tx_frame_bytes,

    // RX side (fed from ltpi_frame_rx)
    input  logic        rx_frame_valid,
    input  logic [7:0]  rx_comma_byte,
    input  logic         rx_crc_ok,
    input  logic [FRAME_PAYLOAD_BITS-1:0] rx_frame_bytes,

    // GPIO channel (Default I/O Frame, Low-Latency + Normal-Latency)
    input  logic [7:0] ll_gpio_tx,
    input  logic [7:0] nl_gpio_tx,
    output logic [7:0] ll_gpio_rx,
    output logic [7:0] nl_gpio_rx,

    // Diagnostics
    output ltpi_link_state_e link_state,
    output logic             link_up,
    output logic [7:0]       frame_counter,
    output logic [15:0]      crc_error_count
);

    function automatic ltpi_link_state_e stage_of(input logic [7:0] comma, input logic [7:0] subtype);
        if (comma == COMMA_K28_5 && subtype == SUBTYPE_LINK_DETECT) stage_of = LS_DETECT;
        else if (comma == COMMA_K28_5 && subtype == SUBTYPE_LINK_SPEED) stage_of = LS_SPEED;
        else if (comma == COMMA_K28_6 && subtype == SUBTYPE_ADVERTISE) stage_of = LS_ADVERTISE;
        else if (comma == COMMA_K28_6 && subtype == SUBTYPE_CONFIGURE) stage_of = LS_CONFIGURE;
        else if (comma == COMMA_K28_6 && subtype == SUBTYPE_ACCEPT) stage_of = LS_ACCEPT;
        else if (comma == COMMA_K28_7 && (subtype == SUBTYPE_IO_FRAME || subtype == SUBTYPE_DATA_FRAME)) stage_of = LS_OPERATIONAL;
        else stage_of = LS_RESET; // sentinel: unrecognized
    endfunction

    function automatic ltpi_link_state_e next_stage(input ltpi_link_state_e s);
        case (s)
            LS_DETECT:    next_stage = LS_SPEED;
            LS_SPEED:     next_stage = LS_ADVERTISE;
            LS_ADVERTISE: next_stage = LS_CONFIGURE;
            LS_CONFIGURE: next_stage = LS_ACCEPT;
            LS_ACCEPT:    next_stage = LS_OPERATIONAL;
            default:      next_stage = LS_OPERATIONAL;
        endcase
    endfunction

    ltpi_link_state_e state, state_n;
    logic [1:0] good_count, good_count_n;
    logic [7:0] rx_subtype;
    logic [7:0] frame_counter_n;
    logic [15:0] crc_err_n;

    assign rx_subtype = rx_frame_bytes[7:0];
    assign link_state  = state;
    assign link_up      = (state == LS_OPERATIONAL);
    assign tx_comma_sel = (state == LS_DETECT || state == LS_SPEED) ? 2'd0 :
                          (state == LS_OPERATIONAL)                 ? 2'd2 : 2'd1;

    // ------------------------------------------------------------------
    // TX frame content per state
    // ------------------------------------------------------------------
    always_comb begin
        tx_frame_bytes = '0;
        case (state)
            LS_DETECT: begin
                tx_frame_bytes[7:0]   = SUBTYPE_LINK_DETECT;
                tx_frame_bytes[15:8]  = 8'h10; // LTPI revision 1.0 (BCD)
                tx_frame_bytes[23:16] = SPEED_CAP_X1_25MHZ_SDR[7:0];
                tx_frame_bytes[31:24] = SPEED_CAP_X1_25MHZ_SDR[15:8];
            end
            LS_SPEED: begin
                tx_frame_bytes[7:0]   = SUBTYPE_LINK_SPEED;
                tx_frame_bytes[15:8]  = 8'h10;
                tx_frame_bytes[23:16] = SPEED_CAP_X1_25MHZ_SDR[7:0];
                tx_frame_bytes[31:24] = SPEED_CAP_X1_25MHZ_SDR[15:8];
            end
            LS_ADVERTISE: begin
                tx_frame_bytes[7:0]   = SUBTYPE_ADVERTISE;
                tx_frame_bytes[23:16] = 8'd8; // GPIO capability: 8 NL GPIOs
            end
            LS_CONFIGURE: begin
                tx_frame_bytes[7:0]   = SUBTYPE_CONFIGURE;
                tx_frame_bytes[23:16] = 8'd8;
            end
            LS_ACCEPT: begin
                tx_frame_bytes[7:0]   = SUBTYPE_ACCEPT;
                tx_frame_bytes[23:16] = 8'd8;
            end
            default: begin // LS_OPERATIONAL (and transient LS_RESET/LS_LINK_LOST)
                tx_frame_bytes[7:0]   = SUBTYPE_IO_FRAME;
                tx_frame_bytes[15:8]  = frame_counter;
                tx_frame_bytes[23:16] = ll_gpio_tx;
                tx_frame_bytes[31:24] = 8'h00; // LL GPIO1 (unused, reserved for future extension)
                tx_frame_bytes[39:32] = nl_gpio_tx;
                tx_frame_bytes[47:40] = 8'h00; // NL GPIO1 (unused, reserved for future extension)
            end
        endcase
    end

    // ------------------------------------------------------------------
    // Training / operational state machine
    // ------------------------------------------------------------------
    always_comb begin
        state_n         = state;
        good_count_n    = good_count;
        frame_counter_n = frame_counter;
        crc_err_n       = crc_error_count;

        if (rx_frame_valid) begin
            if (state == LS_OPERATIONAL) begin
                if (rx_crc_ok) begin
                    crc_err_n = 16'd0;
                end else begin
                    crc_err_n = crc_error_count + 16'd1;
                    if (crc_error_count + 1 >= LINK_LOST_CRC_ERRORS) begin
                        state_n      = LS_DETECT;
                        good_count_n = 2'd0;
                        crc_err_n    = 16'd0;
                    end
                end
            end else begin
                if (rx_crc_ok && (stage_of(rx_comma_byte, rx_subtype) == state)) begin
                    if (good_count == TRAIN_GOOD_FRAMES - 1) begin
                        state_n      = next_stage(state);
                        good_count_n = 2'd0;
                    end else begin
                        good_count_n = good_count + 2'd1;
                    end
                end else begin
                    good_count_n = 2'd0;
                end
            end
        end

        if (tx_frame_tick)
            frame_counter_n = frame_counter + 8'd1;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state           <= LS_DETECT;
            good_count      <= 2'd0;
            frame_counter   <= 8'd0;
            crc_error_count <= 16'd0;
            ll_gpio_rx      <= 8'h00;
            nl_gpio_rx      <= 8'h00;
        end else begin
            state           <= state_n;
            good_count      <= good_count_n;
            frame_counter   <= frame_counter_n;
            crc_error_count <= crc_err_n;

            if (rx_frame_valid && rx_crc_ok && (rx_comma_byte == COMMA_K28_7) && (rx_subtype == SUBTYPE_IO_FRAME)) begin
                ll_gpio_rx <= rx_frame_bytes[23:16];
                nl_gpio_rx <= rx_frame_bytes[39:32];
            end
        end
    end

endmodule
