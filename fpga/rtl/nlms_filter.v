// Fixed-point NLMS adaptive filter — processes one sample over multiple cycles
module nlms_filter (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         sample_en,
    input  wire signed [`ANC_DATA_W-1:0] reference_in,
    input  wire signed [`ANC_DATA_W-1:0] primary_in,
    input  wire signed [`ANC_DATA_W-1:0] mu_q15,
    output wire                         busy,
    output reg                          valid_out,
    output reg  signed [`ANC_DATA_W-1:0] error_out,
    output reg  signed [`ANC_DATA_W-1:0] noise_est_out
);
    localparam TAPS = `ANC_FILTER_TAPS;
    localparam IDX_W = 6;

    reg signed [`ANC_DATA_W-1:0] delay_line [0:TAPS-1];
    reg signed [`ANC_DATA_W-1:0] weights    [0:TAPS-1];

    reg [2:0] state;
    localparam S_IDLE=0, S_MAC_Y=1, S_UPDATE=2, S_DONE=3;

    reg [IDX_W-1:0] tap_idx;
    reg signed [`ANC_ACC_W-1:0] y_acc;
    reg signed [`ANC_ACC_W-1:0] norm_acc;
    reg signed [`ANC_DATA_W-1:0] e_q15;
    reg signed [`ANC_ACC_W-1:0] norm_lat;

    wire signed [`ANC_DATA_W-1:0] mac_n;
    anc_q15_mul u_mul_n (.a(delay_line[tap_idx]), .b(delay_line[tap_idx]), .y(mac_n));

    wire signed [31:0] prod;
    assign prod = $signed(mu_q15) * $signed(e_q15) * $signed(delay_line[tap_idx]);

    wire signed [63:0] norm_scaled;
    assign norm_scaled = {28'b0, norm_lat} << `ANC_FRAC_BITS;

    wire signed [31:0] delta_w;
    assign delta_w = (norm_scaled == 0) ? 32'sd0 : (prod / norm_scaled);

    wire signed [`ANC_DATA_W-1:0] sat_delta;
    anc_saturate #(.IN_W(32), .OUT_W(`ANC_DATA_W)) u_sat (.value_in(delta_w), .value_out(sat_delta));

    assign busy = (state != S_IDLE);

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            valid_out <= 1'b0;
            tap_idx <= 0;
            y_acc <= 0;
            norm_acc <= 0;
            norm_lat <= `ANC_NORM_EPS;
            e_q15 <= 0;
            error_out <= 0;
            noise_est_out <= 0;
            for (i = 0; i < TAPS; i = i + 1) begin
                delay_line[i] <= 0;
                weights[i] <= 0;
            end
        end else begin
            valid_out <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (sample_en) begin
                        for (i = TAPS-1; i > 0; i = i - 1)
                            delay_line[i] <= delay_line[i-1];
                        delay_line[0] <= reference_in;
                        tap_idx <= 0;
                        y_acc <= 0;
                        norm_acc <= 0;
                        state <= S_MAC_Y;
                    end
                end
                S_MAC_Y: begin
                    y_acc <= y_acc + ($signed(weights[tap_idx]) * $signed(delay_line[tap_idx]));
                    norm_acc <= norm_acc + ($signed(mac_n));
                    if (tap_idx == TAPS-1) begin
                        e_q15 <= primary_in - ((y_acc + ($signed(weights[tap_idx]) * $signed(delay_line[tap_idx]))) >>> `ANC_FRAC_BITS);
                        error_out <= primary_in - ((y_acc + ($signed(weights[tap_idx]) * $signed(delay_line[tap_idx]))) >>> `ANC_FRAC_BITS);
                        noise_est_out <= (y_acc + ($signed(weights[tap_idx]) * $signed(delay_line[tap_idx]))) >>> `ANC_FRAC_BITS;
                        norm_lat <= (((norm_acc + mac_n) < 1) ? 1 : (norm_acc + mac_n));
                        tap_idx <= 0;
                        state <= S_UPDATE;
                    end else begin
                        tap_idx <= tap_idx + 1;
                    end
                end
                S_UPDATE: begin
                    weights[tap_idx] <= weights[tap_idx] + sat_delta;
                    if (tap_idx == TAPS-1) begin
                        state <= S_DONE;
                    end else begin
                        tap_idx <= tap_idx + 1;
                    end
                end
                S_DONE: begin
                    valid_out <= 1'b1;
                    state <= S_IDLE;
                end
            endcase
        end
    end
endmodule
