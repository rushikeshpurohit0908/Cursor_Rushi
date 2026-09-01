// anc_board.v
// Pin-level FPGA top for the Agilex 5 E-Series 065B (or custom carrier).
// Instantiates anc_top + I2C codec bring-up. AXI ports export to Platform
// Designer / HPS LWH2F.

`timescale 1ns / 1ps

module anc_board #(
    parameter CODEC_SEL = 0  // 0=SSM2518, 1=WM8960, 2=Pmod I2S2 (no I2C)
) (
    input  wire sys_clk,
    input  wire reset_n,

    // I2S to audio codec / Pmod I2S2
    output wire mclk,
    output wire bclk,
    output wire lrck,
    input  wire i2s_adc_data,
    output wire i2s_dac_data,

    // I2C to SSM2518 / WM8960 (unused for Pmod I2S2)
    inout  wire i2c_scl,
    inout  wire i2c_sda,

    // AXI4-Lite from HPS LWH2F
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

    output wire anc_active_led,
    output wire clip_led,
    output wire codec_ready_led
);

    wire codec_init_pulse;
    wire i2c_user_start;
    wire [6:0] i2c_user_addr;
    wire [7:0] i2c_user_reg;
    wire [7:0] i2c_user_data;

    wire i2c_start_seq, i2c_done, i2c_busy_m, i2c_ack_err;
    wire [6:0] i2c_addr_seq;
    wire [7:0] i2c_reg_seq, i2c_data_seq;
    wire codec_ready, codec_busy;

    wire use_user = i2c_user_start;
    wire i2c_start = i2c_start_seq | i2c_user_start;
    wire [6:0] i2c_addr = use_user ? i2c_user_addr : i2c_addr_seq;
    wire [7:0] i2c_reg  = use_user ? i2c_user_reg  : i2c_reg_seq;
    wire [7:0] i2c_dat  = use_user ? i2c_user_data : i2c_data_seq;

    i2c_master u_i2c (
        .clk(sys_clk),
        .reset_n(reset_n),
        .start(i2c_start),
        .slave_addr(i2c_addr),
        .reg_addr(i2c_reg),
        .wr_data(i2c_dat[7:0]),
        .busy(i2c_busy_m),
        .done(i2c_done),
        .ack_error(i2c_ack_err),
        .scl(i2c_scl),
        .sda(i2c_sda)
    );

    codec_init #(.CODEC_SEL(CODEC_SEL)) u_codec (
        .clk(sys_clk),
        .reset_n(reset_n),
        .start_init(codec_init_pulse),
        .i2c_start(i2c_start_seq),
        .i2c_addr(i2c_addr_seq),
        .i2c_reg(i2c_reg_seq),
        .i2c_data(i2c_data_seq),
        .i2c_busy(i2c_busy_m),
        .i2c_done(i2c_done),
        .ready(codec_ready),
        .busy(codec_busy)
    );

    anc_top #(
        .GENERATE_CLOCKS(1)
    ) u_anc (
        .sys_clk(sys_clk),
        .reset_n(reset_n),
        .bclk_in(1'b0),
        .lrck_in(1'b0),
        .i2s_adc_data(i2s_adc_data),
        .i2s_dac_data(i2s_dac_data),
        .mclk(mclk),
        .bclk_out(bclk),
        .lrck_out(lrck),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),
        .s_axi_rdata(s_axi_rdata),
        .codec_init_pulse(codec_init_pulse),
        .i2c_user_start(i2c_user_start),
        .i2c_user_addr(i2c_user_addr),
        .i2c_user_reg(i2c_user_reg),
        .i2c_user_data(i2c_user_data),
        .codec_ready(codec_ready),
        .i2c_busy(i2c_busy_m | codec_busy),
        .anc_active_led(anc_active_led),
        .clip_led(clip_led)
    );

    assign codec_ready_led = codec_ready;

endmodule
