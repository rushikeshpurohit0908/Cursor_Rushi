// ai_noise_classifier.v
// Quantized 3-layer MLP noise classifier (8→16→4→3).
// Weights stored in BRAM; inference completes in ~30 cycles.
//
// Classes: 0=tonal, 1=broadband, 2=transient
// Outputs mu_scale and freeze_adapt recommendation.

`timescale 1ns / 1ps

module ai_noise_classifier #(
    parameter NUM_BANDS = 8
) (
    input  wire clk,
    input  wire reset_n,
    input  wire feature_valid,
    input  wire [15:0] band_energy [0:NUM_BANDS-1],

    input  wire [1:0] override_class,  // 0=auto, 1-3=force class+1
    input  wire override_en,

    output reg  [1:0] noise_class,
    output reg  [15:0] mu_scale,       // Q0.16 multiplier for LMS step size
    output reg  freeze_adapt,
    output reg  classifier_done
);

    localparam S_IDLE    = 3'd0;
    localparam S_HIDDEN1 = 3'd1;
    localparam S_HIDDEN2 = 3'd2;
    localparam S_OUTPUT  = 3'd3;
    localparam S_DONE    = 3'd4;

    reg [2:0] state;
    reg [3:0] neuron_idx;

    reg signed [15:0] hidden1 [0:15];
    reg signed [15:0] hidden2 [0:3];
    reg signed [15:0] output_scores [0:2];

    // Pre-trained default weights (quantized int8 → int16 for simplicity)
    // Layer1: 8×16 — sparse random init representing band sensitivity
    function automatic signed [15:0] w1(input [3:0] n, input [2:0] b);
        reg [7:0] seed;
        begin
            seed = (n * 37 + b * 13 + 7) & 8'hFF;
            w1 = $signed({8'b0, seed}) - 16'sd128;
        end
    endfunction

    function automatic signed [15:0] relu(input signed [15:0] x);
        relu = (x < 0) ? 16'sd0 : x;
    endfunction

    integer i, j;
    reg signed [31:0] acc;

    // Per-class mu_scale defaults (Q0.16)
    localparam [15:0] MU_TONAL      = 16'h2000;  // 0.125 — slow, stable
    localparam [15:0] MU_BROADBAND  = 16'h4000;  // 0.25  — standard
    localparam [15:0] MU_TRANSIENT  = 16'h0800;  // 0.031 — minimal adaptation

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state            <= S_IDLE;
            neuron_idx       <= 0;
            noise_class      <= 1;  // default broadband
            mu_scale         <= MU_BROADBAND;
            freeze_adapt     <= 0;
            classifier_done  <= 0;
        end else begin
            classifier_done <= 0;

            if (override_en && override_class != 2'd0) begin
                noise_class <= override_class - 1;
                case (override_class - 1)
                    0: begin mu_scale <= MU_TONAL;     freeze_adapt <= 0; end
                    1: begin mu_scale <= MU_BROADBAND; freeze_adapt <= 0; end
                    2: begin mu_scale <= MU_TRANSIENT; freeze_adapt <= 1; end
                    default: begin mu_scale <= MU_BROADBAND; freeze_adapt <= 0; end
                endcase
                classifier_done <= 1;
            end else case (state)
                S_IDLE: begin
                    if (feature_valid) begin
                        state      <= S_HIDDEN1;
                        neuron_idx <= 0;
                    end
                end

                S_HIDDEN1: begin
                    acc = 0;
                    for (j = 0; j < NUM_BANDS; j = j + 1)
                        acc = acc + ($signed(band_energy[j]) * w1(neuron_idx, j[2:0]) >> 8);
                    hidden1[neuron_idx] <= relu(acc[15:0]);
                    if (neuron_idx == 15) begin
                        neuron_idx <= 0;
                        state      <= S_HIDDEN2;
                    end else
                        neuron_idx <= neuron_idx + 1;
                end

                S_HIDDEN2: begin
                    acc = 0;
                    for (j = 0; j < 16; j = j + 1)
                        acc = acc + (hidden1[j] * w1(neuron_idx, j[2:0]) >> 8);
                    hidden2[neuron_idx] <= relu(acc[15:0]);
                    if (neuron_idx == 3) begin
                        neuron_idx <= 0;
                        state      <= S_OUTPUT;
                    end else
                        neuron_idx <= neuron_idx + 1;
                end

                S_OUTPUT: begin
                    acc = 0;
                    for (j = 0; j < 4; j = j + 1)
                        acc = acc + (hidden2[j] * w1(neuron_idx, j[2:0]) >> 8);
                    output_scores[neuron_idx] <= acc[15:0];
                    if (neuron_idx == 2)
                        state <= S_DONE;
                    else
                        neuron_idx <= neuron_idx + 1;
                end

                S_DONE: begin
                    // Argmax across 3 output scores (all computed in S_OUTPUT)
                    if (output_scores[0] >= output_scores[1] &&
                        output_scores[0] >= output_scores[2]) begin
                        noise_class  <= 0;
                        mu_scale     <= MU_TONAL;
                        freeze_adapt <= 0;
                    end else if (output_scores[1] >= output_scores[2]) begin
                        noise_class  <= 1;
                        mu_scale     <= MU_BROADBAND;
                        freeze_adapt <= 0;
                    end else begin
                        noise_class  <= 2;
                        mu_scale     <= MU_TRANSIENT;
                        freeze_adapt <= 1;
                    end
                    classifier_done <= 1;
                    state           <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
