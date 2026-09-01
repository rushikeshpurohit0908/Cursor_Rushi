// fxlms_engine.v
// Filtered-x LMS adaptive ANC engine with hybrid, feedforward-frozen,
// and feedforward-virtual-error operating modes.
//
// Modes (mode[1:0]):
//   0 HYBRID      — error mic e(n); classic FxLMS
//   1 FF_FROZEN   — no error mic; y = w^T x; adaptation frozen (use loaded w)
//   2 FF_VIRTUAL  — no error mic; ê = P̂*x + Ŝ*y (internal model / virtual mic)
//   3 CALIB       — pass reference through; freeze adaptation (tone playback)

`timescale 1ns / 1ps

module fxlms_engine #(
    parameter FILTER_TAPS    = 256,
    parameter SECONDARY_TAPS = 128,
    parameter DATA_WIDTH     = 32,
    parameter COEFF_WIDTH    = 32,
    parameter MU_WIDTH       = 16
) (
    input  wire clk,
    input  wire reset_n,

    input  wire enable,
    input  wire bypass,
    input  wire reset_adapt,
    input  wire freeze_adapt,
    input  wire [1:0] mode,
    input  wire [MU_WIDTH-1:0] mu,
    input  wire [MU_WIDTH-1:0] mu_scale,
    input  wire [MU_WIDTH-1:0] leak,

    input  wire valid_in,
    input  wire signed [DATA_WIDTH-1:0] ref_sample,
    input  wire signed [DATA_WIDTH-1:0] error_sample,

    output reg  valid_out,
    output reg  signed [DATA_WIDTH-1:0] anti_noise,

    output reg  clip_flag,
    output reg  [31:0] sample_count,

    input  wire coeff_wr_en,
    input  wire [$clog2(FILTER_TAPS)-1:0] coeff_wr_addr,
    input  wire signed [COEFF_WIDTH-1:0] coeff_wr_data,
    input  wire [$clog2(FILTER_TAPS)-1:0] coeff_rd_addr,
    output wire signed [COEFF_WIDTH-1:0] coeff_rd_data,

    input  wire sec_wr_en,
    input  wire [$clog2(SECONDARY_TAPS)-1:0] sec_wr_addr,
    input  wire signed [COEFF_WIDTH-1:0] sec_wr_data,

    input  wire prim_wr_en,
    input  wire [$clog2(SECONDARY_TAPS)-1:0] prim_wr_addr,
    input  wire signed [COEFF_WIDTH-1:0] prim_wr_data
);

    localparam MODE_HYBRID     = 2'd0;
    localparam MODE_FF_FROZEN  = 2'd1;
    localparam MODE_FF_VIRTUAL = 2'd2;
    localparam MODE_CALIB      = 2'd3;

    localparam S_IDLE   = 3'd0;
    localparam S_FILTER = 3'd1;
    localparam S_WAITSP = 3'd2;
    localparam S_UPDATE = 3'd3;
    localparam S_OUTPUT = 3'd4;

    reg signed [DATA_WIDTH-1:0] x_delay  [0:FILTER_TAPS-1];
    reg signed [COEFF_WIDTH-1:0] w_coeffs [0:FILTER_TAPS-1];
    reg signed [DATA_WIDTH-1:0] xf_delay [0:FILTER_TAPS-1];

    wire sec_valid;
    wire signed [DATA_WIDTH-1:0] x_filtered;
    wire prim_valid;
    wire signed [DATA_WIDTH-1:0] x_primary;
    wire y_sec_valid;
    wire signed [DATA_WIDTH-1:0] y_through_s;

    reg signed [DATA_WIDTH-1:0] y_for_s;
    reg y_valid_for_s;

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
        .coeff_rd_addr({$clog2(SECONDARY_TAPS){1'b0}}),
        .coeff_rd_data()
    );

    secondary_path_fir #(
        .FILTER_TAPS(SECONDARY_TAPS),
        .DATA_WIDTH(DATA_WIDTH),
        .COEFF_WIDTH(COEFF_WIDTH)
    ) u_primary (
        .clk(clk),
        .reset_n(reset_n),
        .valid_in(valid_in),
        .x_in(ref_sample),
        .valid_out(prim_valid),
        .x_filtered(x_primary),
        .coeff_wr_en(prim_wr_en),
        .coeff_wr_addr(prim_wr_addr),
        .coeff_wr_data(prim_wr_data),
        .coeff_rd_addr({$clog2(SECONDARY_TAPS){1'b0}}),
        .coeff_rd_data()
    );

    secondary_path_fir #(
        .FILTER_TAPS(SECONDARY_TAPS),
        .DATA_WIDTH(DATA_WIDTH),
        .COEFF_WIDTH(COEFF_WIDTH)
    ) u_y_secondary (
        .clk(clk),
        .reset_n(reset_n),
        .valid_in(y_valid_for_s),
        .x_in(y_for_s),
        .valid_out(y_sec_valid),
        .x_filtered(y_through_s),
        .coeff_wr_en(sec_wr_en),
        .coeff_wr_addr(sec_wr_addr),
        .coeff_wr_data(sec_wr_data),
        .coeff_rd_addr({$clog2(SECONDARY_TAPS){1'b0}}),
        .coeff_rd_data()
    );

    assign coeff_rd_data = w_coeffs[coeff_rd_addr];

    reg [2:0] state;
    reg [$clog2(FILTER_TAPS)-1:0] tap_idx;
    reg signed [DATA_WIDTH+COEFF_WIDTH+8:0] filter_accum;
    reg signed [DATA_WIDTH-1:0] latched_error;
    reg signed [DATA_WIDTH-1:0] output_reg;
    reg signed [DATA_WIDTH-1:0] latched_primary;
    reg signed [DATA_WIDTH-1:0] latched_ysec;
    reg got_sec;
    reg got_prim;
    reg got_ysec;

    wire [MU_WIDTH-1:0] effective_mu = (mu * mu_scale) >> 16;

    wire signed [MU_WIDTH+DATA_WIDTH+COEFF_WIDTH:0] update_term =
        $signed({latched_error[DATA_WIDTH-1], latched_error}) *
        $signed({xf_delay[tap_idx][DATA_WIDTH-1], xf_delay[tap_idx]}) *
        $signed({1'b0, effective_mu});

    // leaky: w <- w - λ*w  (λ is Q0.16)
    wire signed [COEFF_WIDTH+16:0] leak_term =
        $signed(w_coeffs[tap_idx]) * $signed({1'b0, leak});

    wire freeze_now = freeze_adapt || (mode == MODE_FF_FROZEN) || (mode == MODE_CALIB);

    integer i;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state         <= S_IDLE;
            tap_idx       <= 0;
            filter_accum  <= 0;
            valid_out     <= 0;
            anti_noise    <= 0;
            clip_flag     <= 0;
            sample_count  <= 0;
            latched_error <= 0;
            output_reg    <= 0;
            latched_primary <= 0;
            latched_ysec  <= 0;
            got_sec       <= 0;
            got_prim      <= 0;
            got_ysec      <= 0;
            y_for_s       <= 0;
            y_valid_for_s <= 0;
            for (i = 0; i < FILTER_TAPS; i = i + 1) begin
                x_delay[i]  <= 0;
                xf_delay[i] <= 0;
                w_coeffs[i] <= 0;
            end
        end else begin
            valid_out     <= 0;
            y_valid_for_s <= 0;

            if (coeff_wr_en)
                w_coeffs[coeff_wr_addr] <= coeff_wr_data;

            if (reset_adapt) begin
                for (i = 0; i < FILTER_TAPS; i = i + 1)
                    w_coeffs[i] <= 0;
            end

            if (sec_valid) begin
                got_sec <= 1;
                for (i = FILTER_TAPS-1; i > 0; i = i - 1)
                    xf_delay[i] <= xf_delay[i-1];
                xf_delay[0] <= x_filtered;
            end
            if (prim_valid) begin
                got_prim        <= 1;
                latched_primary <= x_primary;
            end
            if (y_sec_valid) begin
                got_ysec     <= 1;
                latched_ysec <= y_through_s;
            end

            case (state)
                S_IDLE: begin
                    got_sec  <= sec_valid;
                    got_prim <= prim_valid;
                    got_ysec <= y_sec_valid;
                    if (valid_in && enable) begin
                        for (i = FILTER_TAPS-1; i > 0; i = i - 1)
                            x_delay[i] <= x_delay[i-1];
                        x_delay[0] <= ref_sample;

                        if (mode == MODE_HYBRID)
                            latched_error <= error_sample;

                        sample_count <= sample_count + 1;

                        if (ref_sample == {1'b0, {DATA_WIDTH-1{1'b1}}} ||
                            ref_sample == {1'b1, {DATA_WIDTH-1{1'b0}}})
                            clip_flag <= 1;

                        if (mode == MODE_CALIB) begin
                            anti_noise <= ref_sample;
                            valid_out  <= 1;
                        end else begin
                            state        <= S_FILTER;
                            tap_idx      <= 0;
                            filter_accum <= x_delay[0] * w_coeffs[0];
                        end
                    end else if (valid_in && bypass) begin
                        anti_noise   <= ref_sample;
                        valid_out    <= 1;
                        sample_count <= sample_count + 1;
                    end
                end

                S_FILTER: begin
                    if (tap_idx == FILTER_TAPS - 2) begin
                        output_reg <= filter_accum[DATA_WIDTH+COEFF_WIDTH-1:COEFF_WIDTH]
                                    + ((x_delay[FILTER_TAPS-1] * w_coeffs[FILTER_TAPS-1])
                                       >> COEFF_WIDTH);
                        y_for_s       <= -(filter_accum[DATA_WIDTH+COEFF_WIDTH-1:COEFF_WIDTH]);
                        y_valid_for_s <= (mode == MODE_FF_VIRTUAL);
                        state         <= S_WAITSP;
                        tap_idx       <= 0;
                    end else begin
                        tap_idx <= tap_idx + 1;
                        filter_accum <= filter_accum +
                            (x_delay[tap_idx+1] * w_coeffs[tap_idx+1]);
                    end
                end

                S_WAITSP: begin
                    if (mode != MODE_FF_VIRTUAL || (got_prim && got_ysec)) begin
                        if (mode == MODE_FF_VIRTUAL)
                            latched_error <= latched_primary + latched_ysec;
                        state <= S_UPDATE;
                    end
                end

                S_UPDATE: begin
                    if (!freeze_now) begin
                        w_coeffs[tap_idx] <= w_coeffs[tap_idx]
                            - leak_term[COEFF_WIDTH+15:16]
                            + update_term[MU_WIDTH+DATA_WIDTH+COEFF_WIDTH:COEFF_WIDTH+16];
                    end
                    if (tap_idx == FILTER_TAPS - 1)
                        state <= S_OUTPUT;
                    else
                        tap_idx <= tap_idx + 1;
                end

                S_OUTPUT: begin
                    anti_noise <= -output_reg;
                    valid_out  <= 1;
                    state      <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
