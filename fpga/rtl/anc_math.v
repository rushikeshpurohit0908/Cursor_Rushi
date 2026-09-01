// Signed saturation to Q1.15
module anc_saturate #(
    parameter IN_W = 32,
    parameter OUT_W = 16
) (
    input  wire signed [IN_W-1:0] value_in,
    output wire signed [OUT_W-1:0] value_out
);
    localparam signed MAX_V = (1 <<< (OUT_W-1)) - 1;
    localparam signed MIN_V = -(1 <<< (OUT_W-1));

    reg signed [IN_W-1:0] sat;
    always @* begin
        if (value_in > MAX_V)
            sat = MAX_V;
        else if (value_in < MIN_V)
            sat = MIN_V;
        else
            sat = value_in;
    end
    assign value_out = sat[OUT_W-1:0];
endmodule

// Q1.15 multiply: result is Q1.15
module anc_q15_mul (
    input  wire signed [`ANC_DATA_W-1:0] a,
    input  wire signed [`ANC_DATA_W-1:0] b,
    output wire signed [`ANC_DATA_W-1:0] y
);
    wire signed [31:0] prod;
    assign prod = a * b;
    assign y = prod >>> `ANC_FRAC_BITS;
endmodule

// tanh LUT, 256 entries over [-4, +4]
module anc_tanh_lut (
    input  wire signed [`ANC_DATA_W-1:0] x,
    output reg  signed [`ANC_DATA_W-1:0] y
);
    reg signed [`ANC_DATA_W-1:0] lut [0:255];
    integer i;
    real xv, tv;

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            xv = (i / 32.0) - 4.0;
            if (xv > 3.9) tv = 1.0;
            else if (xv < -3.9) tv = -1.0;
            else tv = ( $exp(2.0*xv) - 1.0 ) / ( $exp(2.0*xv) + 1.0 );
            if (tv > 0.9999) lut[i] = 16'sd32767;
            else if (tv < -0.9999) lut[i] = -16'sd32768;
            else lut[i] = $rtoi(tv * 32768.0);
        end
    end

    wire signed [15:0] idx_s;
    assign idx_s = (x >>> 9) + 16'sd128;
    always @* begin
        if (idx_s < 0)
            y = lut[0];
        else if (idx_s > 255)
            y = lut[255];
        else
            y = lut[idx_s[7:0]];
    end
endmodule

// sigmoid LUT
module anc_sigmoid_lut (
    input  wire signed [`ANC_DATA_W-1:0] x,
    output reg  signed [`ANC_DATA_W-1:0] y
);
    reg signed [`ANC_DATA_W-1:0] lut [0:255];
    integer i;
    real xv, sv;

    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            xv = (i / 32.0) - 4.0;
            if (xv > 8.0) sv = 1.0;
            else if (xv < -8.0) sv = 0.0;
            else sv = 1.0 / (1.0 + $exp(-xv));
            lut[i] = $rtoi(sv * 32768.0);
        end
    end

    wire signed [15:0] idx_s;
    assign idx_s = (x >>> 9) + 16'sd128;
    always @* begin
        if (idx_s < 0)
            y = lut[0];
        else if (idx_s > 255)
            y = lut[255];
        else
            y = lut[idx_s[7:0]];
    end
endmodule
