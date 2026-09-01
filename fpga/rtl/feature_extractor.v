// Hardware-friendly block feature extractor (512-sample blocks, no FFT)
module feature_extractor (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         sample_en,
    input  wire signed [`ANC_DATA_W-1:0] sample_in,
    output reg                          feat_valid,
    output reg  signed [`ANC_DATA_W-1:0] feat [0:`ANC_NUM_FEAT-1]
);
    localparam BLOCK = `ANC_BLOCK_SIZE;
    localparam CNT_W = 10;

    reg [CNT_W-1:0] count;
    reg signed [`ANC_ACC_W-1:0] sum_sq;
    reg [CNT_W-1:0] zc_count;
    reg prev_sign;
    reg signed [`ANC_DATA_W-1:0] peak;
    reg signed [`ANC_ACC_W-1:0] low_e, mid_e, high_e;
    reg signed [`ANC_DATA_W-1:0] lp_y, bp_y;

    wire sign_bit = sample_in[`ANC_DATA_W-1];
    wire signed [`ANC_DATA_W-1:0] abs_x = sample_in[`ANC_DATA_W-1] ? -sample_in : sample_in;

    wire signed [`ANC_DATA_W-1:0] sq;
    anc_q15_mul u_sq (.a(sample_in), .b(sample_in), .y(sq));

    wire signed [`ANC_DATA_W-1:0] mu_lp = 16'sd2621;
    wire signed [`ANC_DATA_W-1:0] mu_bp = 16'sd4915;
    wire signed [`ANC_DATA_W-1:0] lp_diff = sample_in - lp_y;
    wire signed [`ANC_DATA_W-1:0] lp_next = lp_y + ((mu_lp * lp_diff) >>> `ANC_FRAC_BITS);
    wire signed [`ANC_DATA_W-1:0] hp = sample_in - lp_next;
    wire signed [`ANC_DATA_W-1:0] bp_diff = hp - bp_y;
    wire signed [`ANC_DATA_W-1:0] bp_next = bp_y + ((mu_bp * bp_diff) >>> `ANC_FRAC_BITS);

    wire signed [`ANC_DATA_W-1:0] low_sq, mid_sq, high_sq;
    anc_q15_mul u_lsq (.a(lp_next),  .b(lp_next),  .y(low_sq));
    anc_q15_mul u_msq (.a(bp_next),  .b(bp_next),  .y(mid_sq));
    anc_q15_mul u_hsq (.a(hp),       .b(hp),       .y(high_sq));

    function automatic integer fp_isqrt;
        input integer val;
        integer res, bit, trial;
        begin
            if (val <= 0) fp_isqrt = 0;
            else begin
                res = 0; bit = 1 << 14;
                while (bit > val) bit = bit >>> 2;
                while (bit != 0) begin
                    trial = res + bit;
                    if (val >= trial) begin
                        val = val - trial;
                        res = (res >>> 1) + bit;
                    end else begin
                        res = res >>> 1;
                    end
                    bit = bit >>> 2;
                end
                fp_isqrt = res;
            end
        end
    endfunction

    reg [2:0] fstate;
    localparam FS_ACC=0, FS_CALC=1;

    integer rms_i, total_i;
    reg signed [`ANC_ACC_W-1:0] lat_sum, lat_low, lat_mid, lat_high;
    reg [CNT_W-1:0] lat_zc;
    reg signed [`ANC_DATA_W-1:0] lat_peak;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            count <= 0;
            sum_sq <= 0;
            zc_count <= 0;
            prev_sign <= 0;
            peak <= 0;
            low_e <= 0; mid_e <= 0; high_e <= 0;
            lp_y <= 0; bp_y <= 0;
            feat_valid <= 0;
            fstate <= FS_ACC;
        end else begin
            feat_valid <= 0;
            if (sample_en && fstate == FS_ACC) begin
                sum_sq <= sum_sq + sq;
                low_e <= low_e + low_sq;
                mid_e <= mid_e + mid_sq;
                high_e <= high_e + high_sq;
                lp_y <= lp_next;
                bp_y <= bp_next;
                if (count > 0 && sign_bit != prev_sign)
                    zc_count <= zc_count + 1;
                prev_sign <= sign_bit;
                if (abs_x > peak)
                    peak <= abs_x;
                if (count == BLOCK-1) begin
                    lat_sum <= sum_sq + sq;
                    lat_low <= low_e + low_sq;
                    lat_mid <= mid_e + mid_sq;
                    lat_high <= high_e + high_sq;
                    lat_zc <= zc_count + ((count > 0 && sign_bit != prev_sign) ? 1 : 0);
                    lat_peak <= (abs_x > peak) ? abs_x : peak;
                    fstate <= FS_CALC;
                end else begin
                    count <= count + 1;
                end
            end else if (fstate == FS_CALC) begin
                rms_i = fp_isqrt(lat_sum / BLOCK);
                total_i = lat_low + lat_mid + lat_high + 1;
                feat[0] <= rms_i;
                feat[1] <= (lat_zc <<< `ANC_FRAC_BITS) / BLOCK;
                feat[4] <= (lat_low  <<< `ANC_FRAC_BITS) / total_i;
                feat[5] <= (lat_mid  <<< `ANC_FRAC_BITS) / total_i;
                feat[6] <= (lat_high <<< `ANC_FRAC_BITS) / total_i;
                feat[2] <= ((lat_low >>> 2) + (lat_mid >>> 1) + lat_high) / (total_i >>> 1);
                feat[3] <= (lat_low + lat_mid + lat_high) / (3 * BLOCK);
                feat[7] <= (lat_peak <<< `ANC_FRAC_BITS) / (rms_i + 1);
                count <= 0;
                sum_sq <= 0;
                zc_count <= 0;
                peak <= 0;
                low_e <= 0; mid_e <= 0; high_e <= 0;
                lp_y <= 0; bp_y <= 0;
                fstate <= FS_ACC;
                feat_valid <= 1'b1;
            end
        end
    end
endmodule
