// anc_top.v
// Fabric integrator: clocks, I2S, CDC, FxLMS, AI, notch, AXI CSR.

`timescale 1ns / 1ps

module anc_top #(
    parameter FILTER_TAPS     = 256,
    parameter SECONDARY_TAPS  = 128,
    parameter DATA_WIDTH      = 24,
    parameter INTERNAL_WIDTH  = 32,
    parameter TDM_SLOTS       = 2,
    parameter GENERATE_CLOCKS = 1
) (
    input  wire sys_clk,
    input  wire reset_n,

    input  wire bclk_in,
    input  wire lrck_in,
    input  wire i2s_adc_data,
    output wire i2s_dac_data,
    output wire mclk,
    output wire bclk_out,
    output wire lrck_out,

    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [7:0]  s_axi_awaddr,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    input  wire [7:0]  s_axi_araddr,
    output wire        s_axi_rvalid,
    input  wire        s_axi_rready,
    output wire [31:0] s_axi_rdata,

    output wire        codec_init_pulse,
    output wire        i2c_user_start,
    output wire [6:0]  i2c_user_addr,
    output wire [7:0]  i2c_user_reg,
    output wire [7:0]  i2c_user_data,
    input  wire        codec_ready,
    input  wire        i2c_busy,

    output wire anc_active_led,
    output wire clip_led
);

    wire gen_mclk, gen_bclk, gen_lrck, sample_tick;

    audio_clock_gen u_clocks (
        .sys_clk(sys_clk),
        .reset_n(reset_n),
        .mclk(gen_mclk),
        .bclk(gen_bclk),
        .lrck(gen_lrck),
        .sample_tick(sample_tick)
    );

    wire bclk = GENERATE_CLOCKS ? gen_bclk : bclk_in;
    wire lrck = GENERATE_CLOCKS ? gen_lrck : lrck_in;

    assign mclk     = gen_mclk;
    assign bclk_out = gen_bclk;
    assign lrck_out = gen_lrck;

    wire                       i2s_rx_valid;
    wire signed [DATA_WIDTH-1:0] rx_slot [0:TDM_SLOTS-1];

    i2s_rx #(
        .DATA_WIDTH(DATA_WIDTH),
        .TDM_SLOTS(TDM_SLOTS)
    ) u_i2s_rx (
        .bclk(bclk),
        .lrck(lrck),
        .sdin(i2s_adc_data),
        .reset_n(reset_n),
        .sample_valid(i2s_rx_valid),
        .slot_data(rx_slot)
    );

    wire signed [INTERNAL_WIDTH-1:0] ref_sample =
        {{8{rx_slot[0][DATA_WIDTH-1]}}, rx_slot[0]};
    wire signed [INTERNAL_WIDTH-1:0] error_sample =
        {{8{rx_slot[1][DATA_WIDTH-1]}}, rx_slot[1]};

    wire fifo_rd_en;
    wire fifo_empty;
    wire [INTERNAL_WIDTH*2-1:0] fifo_rd_data;

    audio_sync_fifo #(
        .DATA_WIDTH(INTERNAL_WIDTH * 2),
        .DEPTH(16)
    ) u_audio_cdc (
        .wr_clk(bclk),
        .rd_clk(sys_clk),
        .reset_n(reset_n),
        .wr_en(i2s_rx_valid),
        .wr_data({ref_sample, error_sample}),
        .wr_full(),
        .rd_en(fifo_rd_en),
        .rd_data(fifo_rd_data),
        .rd_empty(fifo_empty)
    );

    wire signed [INTERNAL_WIDTH-1:0] sys_ref_sample   = fifo_rd_data[INTERNAL_WIDTH*2-1:INTERNAL_WIDTH];
    wire signed [INTERNAL_WIDTH-1:0] sys_error_sample = fifo_rd_data[INTERNAL_WIDTH-1:0];

    reg rd_pending;
    always @(posedge sys_clk or negedge reset_n) begin
        if (!reset_n)
            rd_pending <= 0;
        else if (!fifo_empty && !rd_pending)
            rd_pending <= 1;
        else if (rd_pending)
            rd_pending <= 0;
    end

    assign fifo_rd_en = !fifo_empty && !rd_pending;
    wire sys_valid = rd_pending;

    wire anc_enable, anc_bypass, reset_adapt, notch_en;
    wire [15:0] mu, output_gain, leak;
    wire [1:0] mode;
    wire [1:0] ai_override_class;
    wire ai_override_en;
    wire [15:0] notch_b0, notch_b1, notch_b2, notch_a1, notch_a2;
    wire coeff_wr_en, sec_wr_en, prim_wr_en;
    wire [7:0] coeff_wr_addr;
    wire [31:0] coeff_wr_data;
    wire [6:0] sec_wr_addr, prim_wr_addr;
    wire [31:0] sec_wr_data, prim_wr_data;
    wire status_running, status_clip;
    wire [1:0] status_ai_class;
    wire [31:0] status_sample_count;

    anc_control_regs u_regs (
        .clk(sys_clk),
        .reset_n(reset_n),
        .awvalid(s_axi_awvalid),
        .awready(s_axi_awready),
        .awaddr(s_axi_awaddr),
        .wvalid(s_axi_wvalid),
        .wready(s_axi_wready),
        .wdata(s_axi_wdata),
        .wstrb(s_axi_wstrb),
        .arvalid(s_axi_arvalid),
        .arready(s_axi_arready),
        .araddr(s_axi_araddr),
        .rvalid(s_axi_rvalid),
        .rready(s_axi_rready),
        .rdata(s_axi_rdata),
        .anc_enable(anc_enable),
        .anc_bypass(anc_bypass),
        .reset_adapt(reset_adapt),
        .codec_init_pulse(codec_init_pulse),
        .notch_en(notch_en),
        .mu(mu),
        .output_gain(output_gain),
        .leak(leak),
        .mode(mode),
        .ai_override_class(ai_override_class),
        .ai_override_en(ai_override_en),
        .notch_b0(notch_b0),
        .notch_b1(notch_b1),
        .notch_b2(notch_b2),
        .notch_a1(notch_a1),
        .notch_a2(notch_a2),
        .coeff_wr_en(coeff_wr_en),
        .coeff_wr_addr(coeff_wr_addr),
        .coeff_wr_data(coeff_wr_data),
        .sec_wr_en(sec_wr_en),
        .sec_wr_addr(sec_wr_addr),
        .sec_wr_data(sec_wr_data),
        .prim_wr_en(prim_wr_en),
        .prim_wr_addr(prim_wr_addr),
        .prim_wr_data(prim_wr_data),
        .i2c_user_start(i2c_user_start),
        .i2c_user_addr(i2c_user_addr),
        .i2c_user_reg(i2c_user_reg),
        .i2c_user_data(i2c_user_data),
        .status_running(status_running),
        .status_clip(status_clip),
        .status_ai_class(status_ai_class),
        .status_sample_count(status_sample_count),
        .status_codec_ready(codec_ready),
        .status_i2c_busy(i2c_busy)
    );

    wire feature_valid;
    wire [15:0] band_energy [0:7];
    wire [1:0] noise_class;
    wire [15:0] mu_scale;
    wire freeze_adapt;

    spectral_features u_features (
        .clk(sys_clk),
        .reset_n(reset_n),
        .valid_in(sys_valid),
        .sample_in(sys_ref_sample),
        .feature_valid(feature_valid),
        .band_energy(band_energy)
    );

    ai_noise_classifier u_ai (
        .clk(sys_clk),
        .reset_n(reset_n),
        .feature_valid(feature_valid),
        .band_energy(band_energy),
        .override_class(ai_override_class),
        .override_en(ai_override_en),
        .noise_class(noise_class),
        .mu_scale(mu_scale),
        .freeze_adapt(freeze_adapt),
        .classifier_done()
    );

    wire notch_valid;
    wire signed [INTERNAL_WIDTH-1:0] notch_out;
    wire tonal_notch = notch_en || (noise_class == 2'd0);

    notch_iir #(.DATA_WIDTH(INTERNAL_WIDTH)) u_notch (
        .clk(sys_clk),
        .reset_n(reset_n),
        .enable(tonal_notch),
        .valid_in(sys_valid),
        .x_in(sys_ref_sample),
        .b0(notch_b0),
        .b1(notch_b1),
        .b2(notch_b2),
        .a1(notch_a1),
        .a2(notch_a2),
        .valid_out(notch_valid),
        .y_out(notch_out)
    );

    wire anc_valid_out;
    wire signed [INTERNAL_WIDTH-1:0] anti_noise;

    fxlms_engine #(
        .FILTER_TAPS(FILTER_TAPS),
        .SECONDARY_TAPS(SECONDARY_TAPS),
        .DATA_WIDTH(INTERNAL_WIDTH),
        .COEFF_WIDTH(INTERNAL_WIDTH)
    ) u_fxlms (
        .clk(sys_clk),
        .reset_n(reset_n),
        .enable(anc_enable),
        .bypass(anc_bypass),
        .reset_adapt(reset_adapt),
        .freeze_adapt(freeze_adapt),
        .mode(mode),
        .mu(mu),
        .mu_scale(mu_scale),
        .leak(leak),
        .valid_in(sys_valid),
        .ref_sample(sys_ref_sample),
        .error_sample(sys_error_sample),
        .valid_out(anc_valid_out),
        .anti_noise(anti_noise),
        .clip_flag(status_clip),
        .sample_count(status_sample_count),
        .coeff_wr_en(coeff_wr_en),
        .coeff_wr_addr(coeff_wr_addr),
        .coeff_wr_data(coeff_wr_data),
        .coeff_rd_addr({8{1'b0}}),
        .coeff_rd_data(),
        .sec_wr_en(sec_wr_en),
        .sec_wr_addr(sec_wr_addr),
        .sec_wr_data(sec_wr_data),
        .prim_wr_en(prim_wr_en),
        .prim_wr_addr(prim_wr_addr),
        .prim_wr_data(prim_wr_data)
    );

    assign status_running  = anc_enable && !anc_bypass;
    assign status_ai_class = noise_class;

    wire signed [INTERNAL_WIDTH-1:0] mix = anti_noise + (tonal_notch ? (notch_out >>> 3) : 0);
    wire signed [INTERNAL_WIDTH-1:0] gained = (mix * $signed({1'b0, output_gain})) >>> 15;
    wire signed [DATA_WIDTH-1:0] dac_left = gained[INTERNAL_WIDTH-1:INTERNAL_WIDTH-DATA_WIDTH];

    wire tx_fifo_empty;
    wire [DATA_WIDTH-1:0] tx_fifo_data;
    wire tx_fifo_rd;

    audio_sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(16)
    ) u_tx_cdc (
        .wr_clk(sys_clk),
        .rd_clk(bclk),
        .reset_n(reset_n),
        .wr_en(anc_valid_out),
        .wr_data(dac_left[DATA_WIDTH-1:0]),
        .wr_full(),
        .rd_en(tx_fifo_rd),
        .rd_data(tx_fifo_data),
        .rd_empty(tx_fifo_empty)
    );

    reg tx_rd_pending;
    always @(posedge bclk or negedge reset_n) begin
        if (!reset_n)
            tx_rd_pending <= 0;
        else if (!tx_fifo_empty && !tx_rd_pending)
            tx_rd_pending <= 1;
        else if (tx_rd_pending)
            tx_rd_pending <= 0;
    end

    assign tx_fifo_rd = !tx_fifo_empty && !tx_rd_pending;

    wire signed [DATA_WIDTH-1:0] tx_slot [0:TDM_SLOTS-1];
    assign tx_slot[0] = tx_fifo_data;
    assign tx_slot[1] = rx_slot[1];

    i2s_tx #(
        .DATA_WIDTH(DATA_WIDTH),
        .TDM_SLOTS(TDM_SLOTS)
    ) u_i2s_tx (
        .bclk(bclk),
        .lrck(lrck),
        .reset_n(reset_n),
        .sample_valid(tx_rd_pending),
        .slot_data(tx_slot),
        .sdout(i2s_dac_data)
    );

    assign anc_active_led = status_running;
    assign clip_led       = status_clip;

endmodule
