// Top-level AI-ANC FPGA module with ready/valid handshaking
// Uses lightweight band-classifier AI mu selector (default) — see mlp_controller.v for full MLP option
module anc_top (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         sample_en,
    input  wire signed [`ANC_DATA_W-1:0] reference_in,
    input  wire signed [`ANC_DATA_W-1:0] primary_in,
    output wire                         input_ready,
    output wire                         output_valid,
    output wire signed [`ANC_DATA_W-1:0] anc_out,
    output wire signed [`ANC_DATA_W-1:0] noise_est,
    output wire signed [`ANC_DATA_W-1:0] mu_debug
);
    reg signed [`ANC_DATA_W-1:0] mu_effective;

    wire feat_valid;
    wire signed [`ANC_DATA_W-1:0] features [0:`ANC_NUM_FEAT-1];
    wire mu_valid;
    wire signed [`ANC_DATA_W-1:0] mu_pred, gain_pred;

    wire nlms_busy;
    wire nlms_valid;
    wire signed [`ANC_DATA_W-1:0] error_q, noise_q;

    assign input_ready = !nlms_busy;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            mu_effective <= 16'sd655;
        else if (mu_valid)
            mu_effective <= (mu_pred * gain_pred) >>> `ANC_FRAC_BITS;
    end

    feature_extractor u_feat (
        .clk(clk), .rst_n(rst_n),
        .sample_en(sample_en && input_ready),
        .sample_in(reference_in),
        .feat_valid(feat_valid), .feat(features)
    );

    ai_mu_selector u_ai (
        .clk(clk), .rst_n(rst_n),
        .feat_valid(feat_valid), .feat(features),
        .mu_valid(mu_valid), .mu_q15(mu_pred), .gain_q15(gain_pred)
    );

    nlms_filter u_nlms (
        .clk(clk), .rst_n(rst_n),
        .sample_en(sample_en && input_ready),
        .reference_in(reference_in), .primary_in(primary_in),
        .mu_q15(mu_effective), .busy(nlms_busy), .valid_out(nlms_valid),
        .error_out(error_q), .noise_est_out(noise_q)
    );

    assign output_valid = nlms_valid;
    assign anc_out = error_q;
    assign noise_est = noise_q;
    assign mu_debug = mu_effective;
endmodule
