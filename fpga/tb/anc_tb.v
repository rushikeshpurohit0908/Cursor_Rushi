`timescale 1ns / 1ps
`include "anc_pkg.v"

module anc_tb;
    reg clk = 0;
    reg rst_n = 0;
    reg sample_en = 0;
    reg signed [`ANC_DATA_W-1:0] reference_in = 0;
    reg signed [`ANC_DATA_W-1:0] primary_in = 0;

    wire input_ready;
    wire output_valid;
    wire signed [`ANC_DATA_W-1:0] anc_out, noise_est, mu_debug;

    localparam MAX_SAMPLES = 512;
    reg [15:0] ref_mem [0:MAX_SAMPLES-1];
    reg [15:0] pri_mem [0:MAX_SAMPLES-1];
    reg [15:0] exp_mem [0:MAX_SAMPLES-1];

    integer i, samples_sent, samples_recv, errors;
    real max_err;

    anc_top dut (
        .clk(clk), .rst_n(rst_n),
        .sample_en(sample_en),
        .reference_in(reference_in), .primary_in(primary_in),
        .input_ready(input_ready), .output_valid(output_valid),
        .anc_out(anc_out), .noise_est(noise_est), .mu_debug(mu_debug)
    );

    always #5 clk = ~clk;

    initial begin
        $readmemh("vectors/reference.hex", ref_mem);
        $readmemh("vectors/primary.hex", pri_mem);
        $readmemh("vectors/expected_output.hex", exp_mem);

        rst_n = 0;
        #100;
        rst_n = 1;
        #20;

        samples_sent = 0;
        samples_recv = 0;
        errors = 0;
        max_err = 0.0;

        while (samples_sent < MAX_SAMPLES) begin
            @(posedge clk);
            sample_en <= 1'b0;
            if (input_ready && samples_sent < MAX_SAMPLES) begin
                reference_in <= $signed(ref_mem[samples_sent]);
                primary_in <= $signed(pri_mem[samples_sent]);
                sample_en <= 1'b1;
                samples_sent = samples_sent + 1;
            end
            if (output_valid) begin
                if (samples_recv < MAX_SAMPLES) begin
                    if (anc_out !== $signed(exp_mem[samples_recv])) begin
                        errors = errors + 1;
                    end
                    samples_recv = samples_recv + 1;
                end
            end
        end

        // Drain pipeline
        for (i = 0; i < 200; i = i + 1) begin
            @(posedge clk);
            sample_en <= 1'b0;
            if (output_valid && samples_recv < MAX_SAMPLES) begin
                if (anc_out !== $signed(exp_mem[samples_recv]))
                    errors = errors + 1;
                samples_recv = samples_recv + 1;
            end
        end

        $display("ANC TB: sent=%0d recv=%0d errors=%0d", samples_sent, samples_recv, errors);
        if (errors == 0)
            $display("PASS: FPGA model matches expected vectors");
        else
            $display("FAIL: %0d mismatches (fixed-point tolerance expected)", errors);
        $finish;
    end
endmodule
