// -----------------------------------------------------------------------------
// LTPI IP for Cyclone V FPGA
// SPDX-License-Identifier: MIT
//
// ltpi_pkg.sv
//
// Shared constants and types for the LTPI (LVDS Tunneling Protocol & Interface)
// link layer. Values below are taken directly from the Open Compute Project
// "DC-SCM 2.x LTPI Specification" (publicly available at opencompute.org).
// -----------------------------------------------------------------------------

package ltpi_pkg;

    // -------------------------------------------------------------------
    // Roles
    // -------------------------------------------------------------------
    typedef enum logic {
        LTPI_ROLE_CONTROLLER = 1'b0,   // HPM side
        LTPI_ROLE_TARGET     = 1'b1    // SCM side
    } ltpi_role_e;

    // -------------------------------------------------------------------
    // Frame geometry
    // -------------------------------------------------------------------
    localparam int FRAME_BYTES        = 16;   // total bytes per LTPI frame, incl. comma+CRC
    localparam int FRAME_PAYLOAD_BYTES = 14;   // bytes[1..14] covered by the CRC-8
    localparam int FRAME_PAYLOAD_BITS  = FRAME_PAYLOAD_BYTES * 8; // packed-bus width for bytes[1..14]
    localparam int BASE_FREQ_MHZ      = 25;    // mandatory baseline link frequency (SDR)

    // -------------------------------------------------------------------
    // Comma symbols (8-bit value pre-8b/10b-encoding). These select which
    // family of frame the current 16-byte frame belongs to.
    // -------------------------------------------------------------------
    localparam logic [7:0] COMMA_K28_5 = 8'hBC;   // Link Detect / Link Speed frames
    localparam logic [7:0] COMMA_K28_6 = 8'hDC;   // Advertise / Configure / Accept frames
    localparam logic [7:0] COMMA_K28_7 = 8'hFC;   // Operational frames (I/O / Data)

    // -------------------------------------------------------------------
    // Frame subtypes (byte[1] of the frame, meaning depends on comma symbol)
    // -------------------------------------------------------------------
    // Comma == K28.5
    localparam logic [7:0] SUBTYPE_LINK_DETECT = 8'h00;
    localparam logic [7:0] SUBTYPE_LINK_SPEED  = 8'h01;

    // Comma == K28.6
    localparam logic [7:0] SUBTYPE_ADVERTISE   = 8'h00;
    localparam logic [7:0] SUBTYPE_CONFIGURE   = 8'h01;
    localparam logic [7:0] SUBTYPE_ACCEPT      = 8'h02;

    // Comma == K28.7
    localparam logic [7:0] SUBTYPE_IO_FRAME    = 8'h00;
    localparam logic [7:0] SUBTYPE_DATA_FRAME  = 8'h01;

    // -------------------------------------------------------------------
    // Link Detect Frame - Speed Capabilities (Base Frequency = 25MHz mandatory)
    // -------------------------------------------------------------------
    localparam logic [15:0] SPEED_CAP_X1_25MHZ_SDR = 16'h0001; // only mandatory rate supported

    // -------------------------------------------------------------------
    // Link state machine states (shared training + operational FSM)
    // -------------------------------------------------------------------
    typedef enum logic [3:0] {
        LS_RESET       = 4'd0,
        LS_DETECT      = 4'd1,  // exchanging/looking for K28.5 Link Detect frames
        LS_SPEED       = 4'd2,  // exchanging K28.5 Link Speed frames
        LS_ADVERTISE   = 4'd3,  // exchanging K28.6 Advertise frames
        LS_CONFIGURE   = 4'd4,  // exchanging K28.6 Configure frames
        LS_ACCEPT      = 4'd5,  // exchanging K28.6 Accept frames
        LS_OPERATIONAL = 4'd6,  // exchanging K28.7 Default I/O / Data frames
        LS_LINK_LOST   = 4'd7   // consecutive CRC errors / timeout -> re-train
    } ltpi_link_state_e;

    // Number of consecutive good frames required before advancing a training stage
    localparam int TRAIN_GOOD_FRAMES = 3;

    // Number of consecutive CRC errors on Operational frames before declaring Link Lost
    localparam int LINK_LOST_CRC_ERRORS = 3;

endpackage : ltpi_pkg
