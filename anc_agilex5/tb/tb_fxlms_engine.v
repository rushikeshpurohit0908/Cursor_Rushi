// tb_fxlms_engine.v
// Simulation testbench for FxLMS ANC engine with synthetic sine-wave noise.

`timescale 1ns / 1ps

module tb_fxlms_engine;

    localparam CLK_PERIOD = 10;  // 100 MHz

    reg clk;
    reg reset_n;
    reg enable;
    reg bypass;
    reg reset_adapt;
    reg freeze_adapt;
    reg [15:0] mu;
    reg [15:0] mu_scale;
    reg valid_in;
    reg signed [31:0] ref_sample;
    reg signed [31:0] error_sample;

    wire valid_out;
    wire signed [31:0] anti_noise;
    wire clip_flag;
    wire [31:0] sample_count;

    fxlms_engine #(
        .FILTER_TAPS(64),       // smaller for faster sim
        .SECONDARY_TAPS(32),
        .DATA_WIDTH(32),
        .COEFF_WIDTH(32)
    ) dut (
        .clk(clk),
        .reset_n(reset_n),
        .enable(enable),
        .bypass(bypass),
        .reset_adapt(reset_adapt),
        .freeze_adapt(freeze_adapt),
        .mu(mu),
        .mu_scale(mu_scale),
        .valid_in(valid_in),
        .ref_sample(ref_sample),
        .error_sample(error_sample),
        .valid_out(valid_out),
        .anti_noise(anti_noise),
        .clip_flag(clip_flag),
        .sample_count(sample_count),
        .coeff_wr_en(0),
        .coeff_wr_addr(0),
        .coeff_wr_data(0),
        .coeff_rd_addr(0),
        .coeff_rd_data(),
        .sec_wr_en(0),
        .sec_wr_addr(0),
        .sec_wr_data(0)
    );

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    integer n;
    real phase;
    real tone_freq = 500.0;  // 500 Hz tonal noise
    real sample_rate = 48000.0;

    initial begin
        $dumpfile("tb_fxlms_engine.vcd");
        $dumpvars(0, tb_fxlms_engine);

        reset_n      = 0;
        enable       = 0;
        bypass       = 0;
        reset_adapt  = 0;
        freeze_adapt = 0;
        mu           = 16'h4000;
        mu_scale     = 16'h4000;
        valid_in     = 0;
        ref_sample   = 0;
        error_sample = 0;

        #(CLK_PERIOD * 20);
        reset_n = 1;
        #(CLK_PERIOD * 10);
        enable = 1;

        // Feed 4096 samples of 500 Hz sine as reference; error = delayed copy
        for (n = 0; n < 4096; n = n + 1) begin
            phase = 2.0 * 3.14159265 * tone_freq * n / sample_rate;
            ref_sample   = $rtoi(0.5 * 32'h6000_0000 * $sin(phase));
            error_sample = $rtoi(0.3 * 32'h6000_0000 * $sin(phase - 0.1));

            valid_in = 1;
            @(posedge clk);
            valid_in = 0;

            // Wait for engine to finish processing this sample
            repeat (128) @(posedge clk);
        end

        $display("FxLMS simulation complete. Samples processed: %0d", sample_count);
        $display("Final anti_noise output: %0d", anti_noise);
        $finish;
    end

endmodule
