// Fixed-point 8->16->2 MLP controller with BRAM weight init from .mem files
module mlp_controller (
    input  wire                         clk,
    input  wire                         rst_n,
    input  wire                         start,
    input  wire signed [`ANC_DATA_W-1:0] features [0:`ANC_NUM_FEAT-1],
    output reg                          done,
    output reg  signed [`ANC_DATA_W-1:0] mu_q15,
    output reg  signed [`ANC_DATA_W-1:0] gain_q15
);
    localparam FEAT = `ANC_NUM_FEAT;
    localparam HID  = `ANC_HIDDEN;
    localparam OUT  = `ANC_MLP_OUT;

    reg signed [`ANC_DATA_W-1:0] w1 [0:FEAT*HID-1];
    reg signed [`ANC_DATA_W-1:0] b1 [0:HID-1];
    reg signed [`ANC_DATA_W-1:0] w2 [0:HID*OUT-1];
    reg signed [`ANC_DATA_W-1:0] b2 [0:OUT-1];

    initial begin
        if ($test$plusargs("fpga_weights")) begin
            $readmemh("mem/w1.mem", w1);
            $readmemh("mem/b1.mem", b1);
            $readmemh("mem/w2.mem", w2);
            $readmemh("mem/b2.mem", b2);
        end else begin
            $readmemh("mem/w1.mem", w1);
            $readmemh("mem/b1.mem", b1);
            $readmemh("mem/w2.mem", w2);
            $readmemh("mem/b2.mem", b2);
        end
    end

    reg [2:0] state;
    localparam ST_IDLE=0, ST_H1=1, ST_HACT=2, ST_O1=3, ST_OACT=4, ST_DONE=5;

    reg [4:0] h_idx, o_idx, f_idx;
    reg signed [`ANC_ACC_W-1:0] acc;
    reg signed [`ANC_DATA_W-1:0] hidden [0:HID-1];
    reg signed [`ANC_DATA_W-1:0] out_raw [0:OUT-1];

    wire signed [`ANC_DATA_W-1:0] tanh_y, sig_y;
    reg signed [`ANC_DATA_W-1:0] act_in;

    anc_tanh_lut    u_tanh (.x(act_in), .y(tanh_y));
    anc_sigmoid_lut u_sig  (.x(act_in), .y(sig_y));

    wire signed [`ANC_DATA_W-1:0] mu_span, gain_span;
    wire signed [31:0] mu_full, gain_full;
    wire signed [`ANC_DATA_W-1:0] mu_sig, gain_sig;

    assign mu_sig = out_raw[0];
    assign gain_sig = out_raw[1];
    assign mu_full = `ANC_MU_MIN_Q15 + ((`ANC_MU_SPAN_Q15 * mu_sig) >>> `ANC_FRAC_BITS);
    assign gain_full = `ANC_GAIN_MIN_Q15 + ((`ANC_GAIN_SPAN_Q15 * gain_sig) >>> `ANC_FRAC_BITS);

    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;
            done <= 0;
            h_idx <= 0;
            o_idx <= 0;
            f_idx <= 0;
            acc <= 0;
            mu_q15 <= `ANC_MU_MIN_Q15;
            gain_q15 <= `ANC_GAIN_MIN_Q15;
        end else begin
            done <= 0;
            case (state)
                ST_IDLE: begin
                    if (start) begin
                        h_idx <= 0;
                        f_idx <= 0;
                        acc <= b1[0] <<< `ANC_FRAC_BITS;
                        state <= ST_H1;
                    end
                end
                ST_H1: begin
                    acc <= acc + ($signed(features[f_idx]) * $signed(w1[h_idx*FEAT + f_idx]));
                    if (f_idx == FEAT-1) begin
                        act_in <= (acc + ($signed(features[f_idx]) * $signed(w1[h_idx*FEAT + f_idx]))) >>> `ANC_FRAC_BITS;
                        state <= ST_HACT;
                        f_idx <= 0;
                    end else begin
                        f_idx <= f_idx + 1;
                    end
                end
                ST_HACT: begin
                    hidden[h_idx] <= tanh_y;
                    if (h_idx == HID-1) begin
                        o_idx <= 0;
                        h_idx <= 0;
                        f_idx <= 0;
                        acc <= b2[0] <<< `ANC_FRAC_BITS;
                        state <= ST_O1;
                    end else begin
                        h_idx <= h_idx + 1;
                        acc <= b1[h_idx+1] <<< `ANC_FRAC_BITS;
                        state <= ST_H1;
                    end
                end
                ST_O1: begin
                    acc <= acc + ($signed(hidden[h_idx]) * $signed(w2[o_idx*HID + h_idx]));
                    if (h_idx == HID-1) begin
                        act_in <= (acc + ($signed(hidden[h_idx]) * $signed(w2[o_idx*HID + h_idx]))) >>> `ANC_FRAC_BITS;
                        state <= ST_OACT;
                        h_idx <= 0;
                    end else begin
                        h_idx <= h_idx + 1;
                    end
                end
                ST_OACT: begin
                    out_raw[o_idx] <= sig_y;
                    if (o_idx == OUT-1) begin
                        mu_q15 <= mu_full[`ANC_DATA_W-1:0];
                        gain_q15 <= gain_full[`ANC_DATA_W-1:0];
                        state <= ST_DONE;
                    end else begin
                        o_idx <= o_idx + 1;
                        h_idx <= 0;
                        acc <= b2[o_idx+1] <<< `ANC_FRAC_BITS;
                        state <= ST_O1;
                    end
                end
                ST_DONE: begin
                    done <= 1'b1;
                    state <= ST_IDLE;
                end
            endcase
        end
    end
endmodule
