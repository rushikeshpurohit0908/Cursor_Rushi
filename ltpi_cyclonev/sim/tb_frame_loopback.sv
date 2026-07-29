// -----------------------------------------------------------------------------
// LTPI IP for Cyclone V FPGA - SPDX-License-Identifier: MIT
//
// tb_frame_loopback.sv - end-to-end bit-serial loopback test:
//   ltpi_frame_tx -> ltpi_symbol_serializer -> (wire, w/ junk startup bits)
//   -> ltpi_symbol_align -> ltpi_frame_rx
//
// Drives a sequence of frames with varying comma types and payload content,
// checks that ltpi_frame_rx reconstructs every field exactly and reports
// crc_ok=1, then deliberately corrupts one transmitted bit and checks that
// the corresponding frame is correctly flagged crc_ok=0.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

import ltpi_pkg::*;

module tb_frame_loopback;

    logic clk = 0;
    logic rst = 1;
    always #5 clk = ~clk;

    // ---------------- TX side ----------------
    logic [1:0]                    comma_sel;
    logic [FRAME_PAYLOAD_BITS-1:0] frame_bytes_tx;
    logic [9:0]                    tx_sym;
    logic                          tx_frame_tick;

    ltpi_frame_tx u_ftx (
        .clk(clk), .rst(rst), .symbol_tick(ser_tick),
        .comma_sel(comma_sel), .frame_bytes(frame_bytes_tx),
        .sym_out(tx_sym), .frame_tick(tx_frame_tick)
    );

    logic ser_tick, tx_bit;
    ltpi_symbol_serializer u_ser (.clk(clk), .rst(rst), .sym_in(tx_sym),
                                   .symbol_tick(ser_tick), .tx_bit(tx_bit));

    // ---------------- Channel (with startup junk + optional single bit-flip) ----------------
    logic       junk_active;
    logic [4:0] junk_shift;
    integer     flip_at_bit = -1;
    integer     bit_counter;
    logic       wire_bit;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            junk_active <= 1'b1;
            junk_shift  <= 5'b11010;
            bit_counter <= 0;
        end else begin
            if (junk_active) begin
                junk_shift <= {junk_shift[3:0], 1'b0};
                if (junk_shift == 5'b00000) junk_active <= 1'b0;
            end else begin
                bit_counter <= bit_counter + 1;
            end
        end
    end

    assign wire_bit = junk_active ? junk_shift[4] : tx_bit;
    assign rx_bit   = (bit_counter == flip_at_bit) ? ~wire_bit : wire_bit;

    // ---------------- RX side ----------------
    logic       rx_bit;
    logic [9:0] rx_sym;
    logic       rx_sym_valid, rx_locked;

    ltpi_symbol_align u_align (.clk(clk), .rst(rst), .rx_bit(rx_bit),
                                .sym_out(rx_sym), .sym_valid(rx_sym_valid), .bit_locked(rx_locked));

    logic                          frame_valid;
    logic [7:0]                    comma_byte_rx;
    logic                          crc_ok;
    logic [FRAME_PAYLOAD_BITS-1:0] frame_bytes_rx;

    ltpi_frame_rx u_frx (
        .clk(clk), .rst(rst), .sym_in(rx_sym), .sym_valid(rx_sym_valid),
        .frame_valid(frame_valid), .comma_byte(comma_byte_rx), .crc_ok(crc_ok),
        .frame_bytes(frame_bytes_rx)
    );

    // ---------------- Stimulus / golden model ----------------
    localparam int NFRAMES = 6;
    logic [1:0] exp_comma_sel [0:NFRAMES-1];
    logic [7:0] exp_bytes     [0:NFRAMES-1][0:FRAME_PAYLOAD_BYTES-1];
    logic       exp_crc_ok    [0:NFRAMES-1];

    function automatic [7:0] comma_byte_of(input [1:0] sel);
        case (sel)
            2'd0: comma_byte_of = COMMA_K28_5;
            2'd1: comma_byte_of = COMMA_K28_6;
            default: comma_byte_of = COMMA_K28_7;
        endcase
    endfunction

    integer cur_frame = 0;
    integer errors = 0;
    integer checks = 0;

    initial begin
        for (int f = 0; f < NFRAMES; f++) begin
            exp_comma_sel[f] = f % 3;
            for (int b = 0; b < FRAME_PAYLOAD_BYTES; b++)
                exp_bytes[f][b] = (f * 17 + b * 5 + 3) & 8'hFF;
            exp_crc_ok[f] = 1'b1; // corrupted frame (index 3) overridden below
        end
        exp_crc_ok[3] = 1'b0;
    end

    // Drive TX frame content combinationally from the "current frame" pointer,
    // advancing on each tx_frame_tick.
    assign comma_sel = exp_comma_sel[cur_frame];

    always_comb begin
        for (int b = 0; b < FRAME_PAYLOAD_BYTES; b++)
            frame_bytes_tx[b*8 +: 8] = exp_bytes[cur_frame][b];
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) cur_frame <= 0;
        else if (tx_frame_tick && (cur_frame < NFRAMES - 1)) cur_frame <= cur_frame + 1;
    end

    // Corrupt exactly one bit that lands inside frame index 3's transmission
    // window. Frame period = 160 bits; account for the ~4-cycle pipeline
    // delay in frame_tx before the first real bit appears on the wire, plus
    // a fixed offset comfortably inside a payload byte (not the comma).
    initial begin
        flip_at_bit = 3 * 160 + 45;
    end

    // ---------------- Checker ----------------
    integer rx_frame_no = 0;

    always_ff @(posedge clk) begin
        if (frame_valid) begin
            checks++;
            if (rx_frame_no >= NFRAMES) begin
                // extra trailing frame (tx holds last frame steady) - ignore
            end else begin
                if (comma_byte_rx !== comma_byte_of(exp_comma_sel[rx_frame_no])) begin
                    errors++;
                    $display("ERROR: frame %0d comma mismatch: exp=0x%02x got=0x%02x",
                              rx_frame_no, comma_byte_of(exp_comma_sel[rx_frame_no]), comma_byte_rx);
                end
                if (crc_ok !== exp_crc_ok[rx_frame_no]) begin
                    errors++;
                    $display("ERROR: frame %0d crc_ok mismatch: exp=%0b got=%0b", rx_frame_no, exp_crc_ok[rx_frame_no], crc_ok);
                end else if (crc_ok) begin
                    for (int b = 0; b < FRAME_PAYLOAD_BYTES; b++) begin
                        if (frame_bytes_rx[b*8 +: 8] !== exp_bytes[rx_frame_no][b]) begin
                            errors++;
                            $display("ERROR: frame %0d byte[%0d] mismatch: exp=0x%02x got=0x%02x",
                                      rx_frame_no, b, exp_bytes[rx_frame_no][b], frame_bytes_rx[b*8 +: 8]);
                        end
                    end
                    $display("OK: frame %0d comma=0x%02x crc_ok=%0b", rx_frame_no, comma_byte_rx, crc_ok);
                end else begin
                    $display("OK: frame %0d correctly flagged crc_ok=0 (corrupted)", rx_frame_no);
                end
            end
            rx_frame_no++;
        end
    end

    initial begin
        rst = 1;
        repeat (3) @(posedge clk);
        rst = 0;

        // Run long enough for NFRAMES * 160 bits plus alignment/junk overhead
        repeat (NFRAMES * 170 + 200) @(posedge clk);

        $display("TB_FRAME_LOOPBACK: locked=%0b, %0d frames observed", rx_locked, rx_frame_no);

        if (rx_frame_no < NFRAMES) begin
            errors++;
            $display("ERROR: expected at least %0d frames, only observed %0d", NFRAMES, rx_frame_no);
        end

        if (errors == 0)
            $display("TB_FRAME_LOOPBACK: ALL CHECKS PASSED (%0d checks)", checks);
        else begin
            $display("TB_FRAME_LOOPBACK: FAILED with %0d error(s)", errors);
            $fatal(1);
        end
        $finish;
    end

endmodule
