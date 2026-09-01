// Lightweight AI mu selector for FPGA — maps band-energy features to optimal NLMS step size.
// Full MLP alternative: see mlp_controller.v (8→16→2 neural network, ~16 DSP blocks).
module ai_mu_selector (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         feat_valid,
    input  wire signed [`ANC_DATA_W-1:0] feat [0:`ANC_NUM_FEAT-1],
    output reg                          mu_valid,
    output reg  signed [`ANC_DATA_W-1:0] mu_q15,
    output reg  signed [`ANC_DATA_W-1:0] gain_q15
);
    // Empirically tuned mu values (Q1.15) from grid search on demo noise profiles
    localparam signed [`ANC_DATA_W-1:0] MU_RUMBLE  = 16'sd33;    // 0.001 — engine rumble
    localparam signed [`ANC_DATA_W-1:0] MU_HUM     = 16'sd164;   // 0.005 — fan hum
    localparam signed [`ANC_DATA_W-1:0] MU_BROAD   = 16'sd655;   // 0.020 — broadband
    localparam signed [`ANC_DATA_W-1:0] MU_HISS    = 16'sd1638;  // 0.050 — high hiss
    localparam signed [`ANC_DATA_W-1:0] MU_DRILL   = 16'sd66;    // 0.002 — impulsive
    localparam signed [`ANC_DATA_W-1:0] GAIN_ONE   = 16'sd32767; // 1.0

    wire signed [`ANC_DATA_W-1:0] low  = feat[4];
    wire signed [`ANC_DATA_W-1:0] mid  = feat[5];
    wire signed [`ANC_DATA_W-1:0] high = feat[6];
    wire signed [`ANC_DATA_W-1:0] crest = feat[7];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mu_valid <= 0;
            mu_q15 <= MU_BROAD;
            gain_q15 <= GAIN_ONE;
        end else begin
            mu_valid <= 1'b0;
            if (feat_valid) begin
                gain_q15 <= GAIN_ONE;
                // AI decision tree on spectral band features
                if (crest > 16'sd28000 && low > mid)
                    mu_q15 <= MU_DRILL;
                else if (low > mid && low > high)
                    mu_q15 <= MU_RUMBLE;
                else if (mid >= low && mid >= high)
                    mu_q15 <= MU_HUM;
                else if (high > mid && high > low)
                    mu_q15 <= MU_HISS;
                else
                    mu_q15 <= MU_BROAD;
                mu_valid <= 1'b1;
            end
        end
    end
endmodule
