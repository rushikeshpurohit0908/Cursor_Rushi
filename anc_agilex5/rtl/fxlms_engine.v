// fxlms_engine.v
// Filtered-x LMS adaptive ANC engine.
//
// Produces anti-noise y(n) from reference x(n) and updates adaptive weights w
// using error signal e(n) and filtered reference x̂(n) from secondary-path model.

`timescale 1ns / 1ps

module fxlms_engine #(
    parameter FILTER_TAPS   = 256,
    parameter SECONDARY_TAPS = 128,
    parameter DATA_WIDTH    = 32,
    parameter COEFF_WIDTH   = 32,
    parameter MU_WIDTH      = 16
) (
    input  wire clk,
    input  wire reset_n,

    // Control
    input  wire enable,
    input  wire bypass,
    input  wire reset_adapt,
    input  wire freeze_adapt,
    input  wire [MU_WIDTH-1:0] mu,           // Q0.16 step size
    input  wire [MU_WIDTH-1:0] mu_scale,     // AI-driven scale factor Q0.16

    // Audio inputs (Q1.31 fixed-point)
    input  wire valid_in,
    input  wire signed [DATA_WIDTH-1:0] ref_sample,    // x(n) reference mic
    input  wire signed [DATA_WIDTH-1:0] error_sample,  // e(n) error mic

    // Anti-noise output
    output reg  valid_out,
    output reg  signed [DATA_WIDTH-1:0] anti_noise,

    // Status
    output reg  clip_flag,
    output reg  [31:0] sample_count,

    // Coefficient BRAM access (for HPS preload / debug readback)
    input  wire coeff_wr_en,
    input  wire [$clog2(FILTER_TAPS)-1:0] coeff_wr_addr,
    input  wire signed [COEFF_WIDTH-1:0] coeff_wr_data,
    input  wire [$clog2(FILTER_TAPS)-1:0] coeff_rd_addr,
    output wire signed [COEFF_WIDTH-1:0] coeff_rd_data,

    // Secondary-path coefficient access
    input  wire sec_wr_en,
    input  wire [$clog2(SECONDARY_TAPS)-1:0] sec_wr_addr,
    input  wire signed [COEFF_WIDTH-1:0] sec_wr_data
);

    // Adaptive filter delay line and coefficients
    reg signed [DATA_WIDTH-1:0] x_delay [0:FILTER_TAPS-1];
    reg signed [COEFF_WIDTH-1:0] w_coeffs [0:FILTER_TAPS-1];

    // Filtered-x delay line (secondary-path filtered reference)
    reg signed [DATA_WIDTH-1:0] xf_delay [0:FILTER_TAPS-1];

    // Secondary-path model instance
    wire sec_valid;
    wire signed [DATA_WIDTH-1:0] x_filtered;

    secondary_path_fir #(
        .FILTER_TAPS(SECONDARY_TAPS),
        .DATA_WIDTH(DATA_WIDTH),
        .COEFF_WIDTH(COEFF_WIDTH)
    ) u_secondary (
        .clk(clk),
        .reset_n(reset_n),
        .valid_in(valid_in),
        .x_in(ref_sample),
        .valid_out(sec_valid),
        .x_filtered(x_filtered),
        .coeff_wr_en(sec_wr_en),
        .coeff_wr_addr(sec_wr_addr),
        .coeff_wr_data(sec_wr_data),
        .coeff_rd_addr(5'd0),
        .coeff_rd_data()
    );

    assign coeff_rd_data = w_coeffs[coeff_rd_addr];

    // State machine for MAC + LMS update (one tap per cycle)
    localparam S_IDLE     = 2'd0;
    localparam S_FILTER   = 2'd1;
    localparam S_UPDATE   = 2'd2;
    localparam S_OUTPUT   = 2'd3;

    reg [1:0] state;
    reg [$clog2(FILTER_TAPS)-1:0] tap_idx;
    reg signed [DATA_WIDTH+COEFF_WIDTH+8:0] filter_accum;
    reg signed [DATA_WIDTH-1:0] latched_error;
    reg signed [DATA_WIDTH-1:0] latched_xf;
    reg signed [DATA_WIDTH-1:0] output_reg;

    wire signed [MU_WIDTH+DATA_WIDTH+COEFF_WIDTH:0] update_term;
    wire [MU_WIDTH-1:0] effective_mu;

    assign effective_mu = (mu * mu_scale) >> 16;
    assign update_term  = $signed({latched_error[DATA_WIDTH-1], latched_error}) *
                          $signed({xf_delay[tap_idx][DATA_WIDTH-1], xf_delay[tap_idx]}) *
                          $signed({1'b0, effective_mu});

    integer i;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state        <= S_IDLE;
            tap_idx      <= 0;
            filter_accum <= 0;
            valid_out    <= 0;
            anti_noise   <= 0;
            clip_flag    <= 0;
            sample_count <= 0;
            latched_error <= 0;
            latched_xf    <= 0;
            output_reg    <= 0;
            for (i = 0; i < FILTER_TAPS; i = i + 1) begin
                x_delay[i]  <= 0;
                xf_delay[i] <= 0;
                w_coeffs[i] <= 0;
            end
        end else begin
            valid_out <= 0;

            if (coeff_wr_en)
                w_coeffs[coeff_wr_addr] <= coeff_wr_data;

            if (reset_adapt) begin
                for (i = 0; i < FILTER_TAPS; i = i + 1)
                    w_coeffs[i] <= 0;
            end

            case (state)
                S_IDLE: begin
                    if (valid_in && enable) begin
                        // Shift reference delay line
                        for (i = FILTER_TAPS-1; i > 0; i = i - 1)
                            x_delay[i] <= x_delay[i-1];
                        x_delay[0] <= ref_sample;

                        latched_error <= error_sample;
                        sample_count <= sample_count + 1;

                        // Check clipping
                        if (ref_sample == {1'b0, {DATA_WIDTH-1{1'b1}}} ||
                            ref_sample == {1'b1, {DATA_WIDTH-1{1'b0}}})
                            clip_flag <= 1;

                        state        <= S_FILTER;
                        tap_idx      <= 0;
                        filter_accum <= x_delay[0] * w_coeffs[0];
                    end else if (valid_in && bypass) begin
                        anti_noise  <= ref_sample;  // passthrough for debug
                        valid_out   <= 1;
                        sample_count <= sample_count + 1;
                    end
                end

                S_FILTER: begin
                    if (tap_idx == FILTER_TAPS - 2) begin
                        output_reg <= filter_accum[DATA_WIDTH+COEFF_WIDTH-1:COEFF_WIDTH]
                                    + (x_delay[FILTER_TAPS-1] * w_coeffs[FILTER_TAPS-1])
                                      [DATA_WIDTH+COEFF_WIDTH-1:COEFF_WIDTH];
                        state   <= S_UPDATE;
                        tap_idx <= 0;
                    end else begin
                        tap_idx <= tap_idx + 1;
                        filter_accum <= filter_accum +
                            (x_delay[tap_idx+1] * w_coeffs[tap_idx+1]);
                    end
                end

                S_UPDATE: begin
                    if (sec_valid) begin
                        // Shift filtered-x delay line when secondary path output ready
                        for (i = FILTER_TAPS-1; i > 0; i = i - 1)
                            xf_delay[i] <= xf_delay[i-1];
                        xf_delay[0] <= x_filtered;
                    end

                    if (!freeze_adapt) begin
                        w_coeffs[tap_idx] <= w_coeffs[tap_idx] +
                            update_term[MU_WIDTH+DATA_WIDTH+COEFF_WIDTH:COEFF_WIDTH+16];
                    end

                    if (tap_idx == FILTER_TAPS - 1)
                        state <= S_OUTPUT;
                    else
                        tap_idx <= tap_idx + 1;
                end

                S_OUTPUT: begin
                    anti_noise <= -output_reg;  // invert for cancellation
                    valid_out  <= 1;
                    state      <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
