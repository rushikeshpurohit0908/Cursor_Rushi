// anc_top.v
// Top-level ANC system integrating audio I/O, FxLMS engine, AI classifier,
// and HPS-facing control registers for Agilex 5 SoC FPGA fabric.

`timescale 1ns / 1ps

module anc_top #(
    parameter FILTER_TAPS    = 256,
    parameter SECONDARY_TAPS = 128,
    parameter DATA_WIDTH     = 24,
    parameter INTERNAL_WIDTH = 32,
    parameter TDM_SLOTS      = 2
) (
    // System clock / reset (100 MHz domain)
    input  wire sys_clk,
    input  wire reset_n,

    // I2S clock domain (from audio_clock_gen, also driven to pins)
    input  wire bclk,
    input  wire lrck,
    input  wire i2s_adc_data,
    output wire i2s_dac_data,

    // Master clocks driven to external codec
    output wire mclk,

    // AXI4-Lite slave (connect to LWH2F bridge in Platform Designer)
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

    // Debug / status LEDs
    output wire anc_active_led,
    output wire clip_led
);

    // --- Audio clock generation ---
    wire sample_tick;

    audio_clock_gen u_clocks (
        .sys_clk(sys_clk),
        .reset_n(reset_n),
        .mclk(mclk),
        .bclk(),       // bclk driven externally from same gen in full integration
        .lrck(),
        .sample_tick(sample_tick)
    );

    // --- I2S RX (reference + error mics) ---
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

    // Sign-extend 24-bit samples to internal 32-bit Q1.31
    wire signed [INTERNAL_WIDTH-1:0] ref_sample  = {{8{rx_slot[0][DATA_WIDTH-1]}}, rx_slot[0]};
    wire signed [INTERNAL_WIDTH-1:0] error_sample = {{8{rx_slot[1][DATA_WIDTH-1]}}, rx_slot[1]};

    // --- CDC: I2S domain → sys_clk domain ---
    wire fifo_wr_en = i2s_rx_valid;
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
        .wr_en(fifo_wr_en),
        .wr_data({ref_sample, error_sample}),
        .wr_full(),
        .rd_en(fifo_rd_en),
        .rd_data(fifo_rd_data),
        .rd_empty(fifo_empty)
    );

    wire signed [INTERNAL_WIDTH-1:0] sys_ref_sample   = fifo_rd_data[INTERNAL_WIDTH*2-1:INTERNAL_WIDTH];
    wire signed [INTERNAL_WIDTH-1:0] sys_error_sample = fifo_rd_data[INTERNAL_WIDTH-1:0];
    wire sys_valid;

    reg rd_pending;
    always @(posedge sys_clk or negedge reset_n) begin
        if (!reset_n)
            rd_pending <= 0;
        else if (!fifo_empty && !rd_pending) begin
            rd_pending <= 1;
        end else if (rd_pending) begin
            rd_pending <= 0;
        end
    end

    assign fifo_rd_en = !fifo_empty && !rd_pending;
    assign sys_valid  = rd_pending;

    // --- Control registers ---
    wire anc_enable, anc_bypass, reset_adapt;
    wire [15:0] mu, output_gain;
    wire [1:0] ai_override_class;
    wire ai_override_en;
    wire coeff_wr_en, sec_wr_en;
    wire [7:0] coeff_wr_addr;
    wire [31:0] coeff_wr_data;
    wire [6:0] sec_wr_addr;
    wire [31:0] sec_wr_data;

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
        .mu(mu),
        .output_gain(output_gain),
        .ai_override_class(ai_override_class),
        .ai_override_en(ai_override_en),
        .coeff_wr_en(coeff_wr_en),
        .coeff_wr_addr(coeff_wr_addr),
        .coeff_wr_data(coeff_wr_data),
        .sec_wr_en(sec_wr_en),
        .sec_wr_addr(sec_wr_addr),
        .sec_wr_data(sec_wr_data),
        .status_running(status_running),
        .status_clip(status_clip),
        .status_ai_class(status_ai_class),
        .status_sample_count(status_sample_count)
    );

    // --- AI noise classifier ---
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

    // --- FxLMS ANC engine ---
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
        .mu(mu),
        .mu_scale(mu_scale),
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
        .coeff_rd_addr(8'd0),
        .coeff_rd_data(),
        .sec_wr_en(sec_wr_en),
        .sec_wr_addr(sec_wr_addr),
        .sec_wr_data(sec_wr_data)
    );

    assign status_running  = anc_enable && !anc_bypass;
    assign status_ai_class = noise_class;

    // --- Output gain + clip to 24-bit ---
    wire signed [INTERNAL_WIDTH-1:0] gained = (anti_noise * $signed({1'b0, output_gain})) >>> 15;
    wire signed [DATA_WIDTH-1:0] dac_left = gained[INTERNAL_WIDTH-1:INTERNAL_WIDTH-DATA_WIDTH];

    // --- CDC: sys_clk → I2S TX domain ---
    wire tx_fifo_wr = anc_valid_out;
    wire tx_fifo_rd;
    wire tx_fifo_empty;
    wire [DATA_WIDTH-1:0] tx_fifo_data;

    audio_sync_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .DEPTH(16)
    ) u_tx_cdc (
        .wr_clk(sys_clk),
        .rd_clk(bclk),
        .reset_n(reset_n),
        .wr_en(tx_fifo_wr),
        .wr_data(dac_left[DATA_WIDTH-1:0]),
        .wr_full(),
        .rd_en(tx_fifo_rd),
        .rd_data(tx_fifo_data),
        .rd_empty(tx_fifo_empty)
    );

    wire tx_valid;
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
    assign tx_valid   = tx_rd_pending;

    wire signed [DATA_WIDTH-1:0] tx_slot [0:TDM_SLOTS-1];
    assign tx_slot[0] = tx_fifo_data;
    assign tx_slot[1] = rx_slot[1];  // monitor mix: pass error mic to right channel

    i2s_tx #(
        .DATA_WIDTH(DATA_WIDTH),
        .TDM_SLOTS(TDM_SLOTS)
    ) u_i2s_tx (
        .bclk(bclk),
        .lrck(lrck),
        .reset_n(reset_n),
        .sample_valid(tx_valid),
        .slot_data(tx_slot),
        .sdout(i2s_dac_data)
    );

    assign anc_active_led = status_running;
    assign clip_led       = status_clip;

endmodule
