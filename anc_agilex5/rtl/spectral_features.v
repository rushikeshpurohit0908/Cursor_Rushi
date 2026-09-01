// spectral_features.v
// Lightweight 8-band Goertzel filter bank for AI noise classification.
// Runs at decimated rate (feature_valid every FEATURE_DECIM samples).

`timescale 1ns / 1ps

module spectral_features #(
    parameter DATA_WIDTH     = 32,
    parameter NUM_BANDS      = 8,
    parameter FEATURE_DECIM  = 512
) (
    input  wire clk,
    input  wire reset_n,
    input  wire valid_in,
    input  wire signed [DATA_WIDTH-1:0] sample_in,

    output reg  feature_valid,
    output reg  [15:0] band_energy [0:NUM_BANDS-1]
);

    // Goertzel coefficients for 48 kHz, target bins (Hz):
    // 125, 250, 500, 1000, 2000, 4000, 6000, 8000
    localparam [15:0] COEFF [0:NUM_BANDS-1] = '{
        16'h7FEB, 16'h7FAD, 16'h7F16, 16'h7D8A,
        16'h7642, 16'h5A82, 16'h2C8C, 16'h0000
    };

    reg [15:0] decim_cnt;
    reg [2:0]  band_idx;
    reg [2:0]  sample_in_frame;
    reg signed [47:0] q0 [0:NUM_BANDS-1];
    reg signed [47:0] q1 [0:NUM_BANDS-1];
    reg running;

    integer i;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            decim_cnt     <= 0;
            band_idx      <= 0;
            sample_in_frame <= 0;
            feature_valid <= 0;
            running       <= 0;
            for (i = 0; i < NUM_BANDS; i = i + 1) begin
                q0[i] <= 0;
                q1[i] <= 0;
                band_energy[i] <= 0;
            end
        end else begin
            feature_valid <= 0;

            if (valid_in) begin
                if (!running) begin
                    running <= 1;
                    decim_cnt <= 0;
                    for (i = 0; i < NUM_BANDS; i = i + 1) begin
                        q0[i] <= 0;
                        q1[i] <= 0;
                    end
                end

                // Update all Goertzel states in parallel (one sample)
                for (i = 0; i < NUM_BANDS; i = i + 1) begin
                    q0[i] <= ($signed(sample_in) * 48'sd256) +
                             ($signed(COEFF[i]) * q1[i] >> 8) - q0[i];
                    q1[i] <= q0[i];
                end

                decim_cnt <= decim_cnt + 1;

                if (decim_cnt == FEATURE_DECIM - 1) begin
                    running <= 0;
                    for (i = 0; i < NUM_BANDS; i = i + 1)
                        band_energy[i] <= (q0[i] * q0[i] + q1[i] * q1[i]) >> 24;
                    feature_valid <= 1;
                end
            end
        end
    end

endmodule
