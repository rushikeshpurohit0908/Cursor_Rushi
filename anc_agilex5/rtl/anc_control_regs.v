// anc_control_regs.v
// AXI4-Lite control/status register block for HPS access via LWH2F bridge.

`timescale 1ns / 1ps

module anc_control_regs (
    input  wire clk,
    input  wire reset_n,

    // AXI4-Lite slave (simplified — single-beat transactions)
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

    // Fabric-facing control outputs
    output reg         anc_enable,
    output reg         anc_bypass,
    output reg         reset_adapt,
    output reg  [15:0] mu,
    output reg  [15:0] output_gain,
    output reg  [1:0]  ai_override_class,
    output reg         ai_override_en,

    // Coefficient/indirect access
    output reg         coeff_wr_en,
    output reg  [7:0]  coeff_wr_addr,
    output reg  [31:0] coeff_wr_data,
    output reg         sec_wr_en,
    output reg  [6:0]  sec_wr_addr,
    output reg  [31:0] sec_wr_data,

    // Status inputs
    input  wire        status_running,
    input  wire        status_clip,
    input  wire [1:0]  status_ai_class,
    input  wire [31:0] status_sample_count
);

    localparam REG_CONTROL          = 8'h00;
    localparam REG_STATUS           = 8'h04;
    localparam REG_MU               = 8'h08;
    localparam REG_SECONDARY_WR     = 8'h0C;
    localparam REG_ADAPTIVE_WR      = 8'h10;
    localparam REG_SAMPLE_COUNT     = 8'h14;
    localparam REG_AI_OVERRIDE      = 8'h18;
    localparam REG_OUTPUT_GAIN      = 8'h1C;

    reg [7:0] wr_addr_latch;
    reg [7:0] rd_addr_latch;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            awready         <= 1;
            wready          <= 1;
            arready         <= 1;
            rvalid          <= 0;
            rdata           <= 0;
            anc_enable      <= 0;
            anc_bypass      <= 1;  // safe default: bypass
            reset_adapt     <= 0;
            mu              <= 16'h4000;
            output_gain     <= 16'h7FFF;
            ai_override_class <= 0;
            ai_override_en  <= 0;
            coeff_wr_en     <= 0;
            coeff_wr_addr   <= 0;
            coeff_wr_data   <= 0;
            sec_wr_en       <= 0;
            sec_wr_addr     <= 0;
            sec_wr_data     <= 0;
        end else begin
            coeff_wr_en <= 0;
            sec_wr_en   <= 0;
            reset_adapt <= 0;

            // Write address channel
            if (awvalid && awready) begin
                wr_addr_latch <= awaddr;
                awready       <= 0;
            end else if (wvalid && wready) begin
                awready <= 1;
            end

            // Write data channel
            if (wvalid && wready && !awready) begin
                wready <= 0;
                case (wr_addr_latch)
                    REG_CONTROL: begin
                        anc_enable  <= wdata[0];
                        anc_bypass  <= wdata[1];
                        if (wdata[2]) reset_adapt <= 1;
                    end
                    REG_MU:              mu <= wdata[15:0];
                    REG_OUTPUT_GAIN:     output_gain <= wdata[15:0];
                    REG_AI_OVERRIDE: begin
                        ai_override_en    <= wdata[31];
                        ai_override_class <= wdata[1:0];
                    end
                    REG_SECONDARY_WR: begin
                        sec_wr_en   <= 1;
                        sec_wr_addr <= wdata[6:0];
                        sec_wr_data <= wdata;
                    end
                    REG_ADAPTIVE_WR: begin
                        coeff_wr_en   <= 1;
                        coeff_wr_addr <= wdata[7:0];
                        coeff_wr_data <= wdata;
                    end
                    default: ;
                endcase
                wready <= 1;
            end

            // Read address channel
            if (arvalid && arready) begin
                rd_addr_latch <= araddr;
                arready       <= 0;
                rvalid        <= 1;
                case (araddr)
                    REG_STATUS: rdata <= {24'b0, status_ai_class, 2'b0,
                                          status_clip, status_running};
                    REG_SAMPLE_COUNT: rdata <= status_sample_count;
                    REG_MU:           rdata <= {16'b0, mu};
                    REG_OUTPUT_GAIN:  rdata <= {16'b0, output_gain};
                    default:          rdata <= 32'h0;
                endcase
            end else if (rvalid && rready) begin
                rvalid  <= 0;
                arready <= 1;
            end
        end
    end

endmodule
