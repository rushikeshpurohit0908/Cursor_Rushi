// -----------------------------------------------------------------------------
// LTPI IP for Cyclone V FPGA - SPDX-License-Identifier: MIT
//
// tb_symbol_align.sv - drives ltpi_symbol_serializer with a stream of *bona
// fide* 8b/10b symbols (produced by encoder_8b10b, so the "no accidental
// comma at a mis-aligned bit offset" guarantee that real LTPI traffic relies
// on actually holds), prefixed by a few junk bits to emulate an unknown
// initial phase, and checks that ltpi_symbol_align recovers every symbol
// bit-exact once it locks.
//
// The expected symbol sequence is pre-computed by running a throwaway
// encoder_8b10b instance over the exact same (k_in,data_in) sequence before
// the real test starts; replaying the same deterministic input sequence
// through the "live" encoder driving the serializer reproduces the identical
// output sequence, which sidesteps having to track queue timing against the
// asynchronous, phase-shifted output of the align module under test.
// -----------------------------------------------------------------------------
`timescale 1ns/1ps

module tb_symbol_align;

    logic clk = 0;
    always #5 clk = ~clk;

    localparam int NSYM = 64; // 4 x 16-symbol LTPI-shaped frames

    logic [7:0] seq_data [0:NSYM-1];
    logic       seq_k    [0:NSYM-1];
    logic [9:0] test_syms [0:NSYM-1];

    initial begin
        for (int i = 0; i < NSYM; i++) begin
            if (i % 16 == 0) begin
                seq_k[i]    = 1'b1;
                seq_data[i] = 8'hFC; // K28.7, operational comma
            end else begin
                seq_k[i]    = 1'b0;
                seq_data[i] = (i * 47 + 11) & 8'hFF;
            end
        end
    end

    // ---- Pass 1: compute the golden expected symbol sequence ----
    logic       gclk = 0, grst;
    logic       g_en, g_k;
    logic [7:0] g_data;
    logic [9:0] g_out;
    logic       g_kerr, g_rd;

    encoder_8b10b u_gold (.clk(gclk), .rst(grst), .en(g_en), .k_in(g_k),
                           .data_in(g_data), .data_out(g_out), .k_err(g_kerr), .rd_state(g_rd));

    logic golden_done = 1'b0;

    initial begin
        grst = 1; g_en = 0; g_k = 0; g_data = 0;
        #1 gclk = 0;
        repeat (2) begin gclk = 1; #1; gclk = 0; #1; end
        grst = 0;
        for (int i = 0; i < NSYM; i++) begin
            g_k = seq_k[i]; g_data = seq_data[i]; g_en = 1;
            gclk = 1; #1; gclk = 0; #1;
            test_syms[i] = g_out;
            g_en = 0;
        end
        golden_done = 1'b1;
    end

    // ---- Pass 2: real-time encoder feeding the serializer under test ----
    logic       rst = 1;
    logic       enc_en, enc_k_in;
    logic [7:0] enc_data_in;
    logic [9:0] enc_data_out;
    logic       enc_kerr, enc_rd;

    encoder_8b10b u_enc (.clk(clk), .rst(rst), .en(enc_en), .k_in(enc_k_in),
                          .data_in(enc_data_in), .data_out(enc_data_out),
                          .k_err(enc_kerr), .rd_state(enc_rd));

    logic [9:0] ser_sym_in;
    logic       ser_tick;
    logic       tx_bit;
    assign ser_sym_in = enc_data_out;

    ltpi_symbol_serializer u_ser (.clk(clk), .rst(rst), .sym_in(ser_sym_in),
                                   .symbol_tick(ser_tick), .tx_bit(tx_bit));

    // ---- Junk prefix to emulate an unknown initial bit phase ----
    logic       junk_active;
    logic [4:0] junk_shift;
    logic       rx_bit;
    assign rx_bit = junk_active ? junk_shift[4] : tx_bit;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            junk_active <= 1'b1;
            junk_shift  <= 5'b10110;
        end else if (junk_active) begin
            junk_shift <= {junk_shift[3:0], 1'b0};
            if (junk_shift == 5'b00000) junk_active <= 1'b0;
        end
    end

    // ---- Receiver under test ----
    logic [9:0] al_sym_out;
    logic       al_sym_valid, al_locked;

    ltpi_symbol_align u_align (.clk(clk), .rst(rst), .rx_bit(rx_bit),
                                .sym_out(al_sym_out), .sym_valid(al_sym_valid),
                                .bit_locked(al_locked));

    // ---- Feed the real encoder in lockstep with symbol_tick requests ----
    integer idx;
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            idx         <= 0;
            enc_en      <= 1'b1;
            enc_k_in    <= seq_k[0];
            enc_data_in <= seq_data[0];
        end else begin
            enc_en <= 1'b0;
            if (ser_tick && (idx < NSYM - 1)) begin
                idx         <= idx + 1;
                enc_en      <= 1'b1;
                enc_k_in    <= seq_k[idx + 1];
                enc_data_in <= seq_data[idx + 1];
            end
        end
    end

    // ---- Checker ----
    integer errors = 0;
    integer checks = 0;
    integer exp_idx = 0;
    logic   first_match_seen = 1'b0;

    always_ff @(posedge clk) begin
        if (al_sym_valid) begin
            if (!first_match_seen) begin
                for (int k = 0; k < NSYM; k++) begin
                    if (!first_match_seen && (test_syms[k] === al_sym_out)) begin
                        exp_idx = k;
                        first_match_seen = 1'b1;
                    end
                end
            end
            checks++;
            if (al_sym_out !== test_syms[exp_idx]) begin
                errors++;
                $display("ERROR: symbol %0d mismatch: expected=%010b got=%010b", exp_idx, test_syms[exp_idx], al_sym_out);
            end
            exp_idx = (exp_idx == NSYM - 1) ? exp_idx : (exp_idx + 1);
        end
    end

    initial begin
        wait (golden_done); // ensure the golden expected-symbol table is ready first
        repeat (3) @(posedge clk);
        rst = 0;

        repeat (NSYM * 10 + 60) @(posedge clk);

        $display("TB_SYMBOL_ALIGN: locked=%0b, %0d checks performed", al_locked, checks);

        if (!al_locked) begin
            errors++;
            $display("ERROR: aligner never achieved lock");
        end
        if (checks < NSYM - 2) begin
            errors++;
            $display("ERROR: too few symbols observed (%0d, expected close to %0d)", checks, NSYM);
        end
        // A handful of extra pulses at the tail is expected/benign: once the
        // stimulus sequence is exhausted, ser_sym_in simply holds the last
        // encoded symbol steady, so the serializer keeps re-transmitting it
        // for the remainder of the simulation's drain time.
        if (checks > NSYM + 8) begin
            errors++;
            $display("ERROR: too many symbols observed (%0d, expected close to %0d) - spurious resync?", checks, NSYM);
        end

        if (errors == 0)
            $display("TB_SYMBOL_ALIGN: ALL CHECKS PASSED (%0d checks)", checks);
        else begin
            $display("TB_SYMBOL_ALIGN: FAILED with %0d error(s)", errors);
            $fatal(1);
        end
        $finish;
    end

endmodule
