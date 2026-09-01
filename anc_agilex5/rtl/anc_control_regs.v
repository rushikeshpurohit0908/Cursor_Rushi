// anc_control_regs.v
// AXI4-Lite CSR for HPS access via LWH2F. See rtl/anc_pkg.vh for the map.

`timescale 1ns / 1ps
`include "anc_pkg.vh"

module anc_control_regs (
    input  wire clk,
    input  wire reset_n,

    input  wire        awvalid,
    output reg         awready,
    input  wire [7:0]  awaddr,
    input  wire        wvalid,
    output reg         wready,
    input  wire [31:0] wdata,
    input  wire [3:0]  wstrb,

    input  wire        arvalid,
    output reg         arready,
    input  wire [7:0]  araddr,
    output reg         rvalid,
    input  wire        rready,
    output reg  [31:0] rdata,

    output reg         anc_enable,
    output reg         anc_bypass,
    output reg         reset_adapt,
    output reg         codec_init_pulse,
    output reg         notch_en,
    output reg  [15:0] mu,
    output reg  [15:0] output_gain,
    output reg  [15:0] leak,
    output reg  [1:0]  mode,
    output reg  [1:0]  ai_override_class,
    output reg         ai_override_en,
    output reg  [15:0] notch_b0,
    output reg  [15:0] notch_b1,
    output reg  [15:0] notch_b2,
    output reg  [15:0] notch_a1,
    output reg  [15:0] notch_a2,

    output reg         coeff_wr_en,
    output reg  [7:0]  coeff_wr_addr,
    output reg  [31:0] coeff_wr_data,
    output reg         sec_wr_en,
    output reg  [6:0]  sec_wr_addr,
    output reg  [31:0] sec_wr_data,
    output reg         prim_wr_en,
    output reg  [6:0]  prim_wr_addr,
    output reg  [31:0] prim_wr_data,

    output reg         i2c_user_start,
    output reg  [6:0]  i2c_user_addr,
    output reg  [7:0]  i2c_user_reg,
    output reg  [7:0]  i2c_user_data,

    input  wire        status_running,
    input  wire        status_clip,
    input  wire [1:0]  status_ai_class,
    input  wire [31:0] status_sample_count,
    input  wire        status_codec_ready,
    input  wire        status_i2c_busy
);

    reg [7:0]  wr_addr_latch;
    reg [7:0]  mem_addr;
    reg [1:0]  mem_sel;
    reg [31:0] i2c_pack;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            awready           <= 1;
            wready            <= 1;
            arready           <= 1;
            rvalid            <= 0;
            rdata             <= 0;
            anc_enable        <= 0;
            anc_bypass        <= 1;
            reset_adapt       <= 0;
            codec_init_pulse  <= 0;
            notch_en          <= 0;
            mu                <= 16'h4000;
            output_gain       <= 16'h7FFF;
            leak              <= 16'h0008;
            mode              <= 2'd0;
            ai_override_class <= 0;
            ai_override_en    <= 0;
            // Default 500 Hz notch @ 48 kHz (Q1.15)
            notch_b0          <= 16'h7EB8;
            notch_b1          <= 16'h8300;
            notch_b2          <= 16'h7EB8;
            notch_a1          <= 16'h8300;
            notch_a2          <= 16'h7D70;
            coeff_wr_en       <= 0;
            coeff_wr_addr     <= 0;
            coeff_wr_data     <= 0;
            sec_wr_en         <= 0;
            sec_wr_addr       <= 0;
            sec_wr_data       <= 0;
            prim_wr_en        <= 0;
            prim_wr_addr      <= 0;
            prim_wr_data      <= 0;
            i2c_user_start    <= 0;
            i2c_user_addr     <= 7'h34;
            i2c_user_reg      <= 0;
            i2c_user_data     <= 0;
            mem_addr          <= 0;
            mem_sel           <= 0;
            i2c_pack          <= 0;
        end else begin
            coeff_wr_en      <= 0;
            sec_wr_en        <= 0;
            prim_wr_en       <= 0;
            reset_adapt      <= 0;
            codec_init_pulse <= 0;
            i2c_user_start   <= 0;

            if (awvalid && awready) begin
                wr_addr_latch <= awaddr;
                awready       <= 0;
            end else if (wvalid && wready) begin
                awready <= 1;
            end

            if (wvalid && wready && !awready) begin
                case (wr_addr_latch)
                    `ANC_REG_CONTROL: begin
                        anc_enable <= wdata[0];
                        anc_bypass <= wdata[1];
                        if (wdata[2]) reset_adapt      <= 1;
                        if (wdata[3]) codec_init_pulse <= 1;
                        notch_en <= wdata[4];
                    end
                    `ANC_REG_MU:          mu          <= wdata[15:0];
                    `ANC_REG_OUTPUT_GAIN: output_gain <= wdata[15:0];
                    `ANC_REG_LEAK:        leak        <= wdata[15:0];
                    `ANC_REG_MODE:        mode        <= wdata[1:0];
                    `ANC_REG_AI_OVERRIDE: begin
                        ai_override_en    <= wdata[31];
                        ai_override_class <= wdata[1:0];
                    end
                    `ANC_REG_MEM_ADDR: mem_addr <= wdata[7:0];
                    `ANC_REG_MEM_SEL:  mem_sel  <= wdata[1:0];
                    `ANC_REG_MEM_DATA: begin
                        case (mem_sel)
                            2'd0: begin
                                sec_wr_en   <= 1;
                                sec_wr_addr <= mem_addr[6:0];
                                sec_wr_data <= wdata;
                            end
                            2'd1: begin
                                coeff_wr_en   <= 1;
                                coeff_wr_addr <= mem_addr;
                                coeff_wr_data <= wdata;
                            end
                            2'd2: begin
                                prim_wr_en   <= 1;
                                prim_wr_addr <= mem_addr[6:0];
                                prim_wr_data <= wdata;
                            end
                            default: ;
                        endcase
                    end
                    `ANC_REG_I2C_CTRL: begin
                        i2c_user_addr <= wdata[6:0];
                        i2c_pack      <= wdata;
                    end
                    `ANC_REG_I2C_DATA: begin
                        i2c_user_reg   <= wdata[15:8];
                        i2c_user_data  <= wdata[7:0];
                        i2c_user_start <= 1;
                    end
                    `ANC_REG_NOTCH_FREQ: begin
                        notch_b0 <= wdata[15:0];
                        notch_b1 <= wdata[31:16];
                    end
                    default: ;
                endcase
                wready <= 1;
            end

            if (arvalid && arready) begin
                arready <= 0;
                rvalid  <= 1;
                case (araddr)
                    `ANC_REG_STATUS:
                        rdata <= {16'b0, 6'b0, status_i2c_busy, status_codec_ready,
                                  2'b0, status_ai_class, 2'b0, status_clip, status_running};
                    `ANC_REG_SAMPLE_COUNT: rdata <= status_sample_count;
                    `ANC_REG_MU:           rdata <= {16'b0, mu};
                    `ANC_REG_OUTPUT_GAIN:  rdata <= {16'b0, output_gain};
                    `ANC_REG_LEAK:         rdata <= {16'b0, leak};
                    `ANC_REG_MODE:         rdata <= {30'b0, mode};
                    `ANC_REG_VERSION:      rdata <= `ANC_VERSION;
                    `ANC_REG_CONTROL:
                        rdata <= {27'b0, notch_en, 1'b0, 1'b0, anc_bypass, anc_enable};
                    default: rdata <= 32'h0;
                endcase
            end else if (rvalid && rready) begin
                rvalid  <= 0;
                arready <= 1;
            end
        end
    end

endmodule
