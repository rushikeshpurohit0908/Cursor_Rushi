// audio_sync_fifo.v
// Dual-clock FIFO for crossing I2S (bclk) domain to DSP (sys_clk) domain.

`timescale 1ns / 1ps

module audio_sync_fifo #(
    parameter DATA_WIDTH = 32,
    parameter DEPTH      = 16
) (
    input  wire wr_clk,
    input  wire rd_clk,
    input  wire reset_n,

    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    output wire                  wr_full,

    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] rd_data,
    output wire                  rd_empty
);

    localparam ADDR_W = $clog2(DEPTH);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_W:0] wr_ptr, rd_ptr;

    assign wr_full  = (wr_ptr[ADDR_W] != rd_ptr[ADDR_W]) &&
                      (wr_ptr[ADDR_W-1:0] == rd_ptr[ADDR_W-1:0]);
    assign rd_empty = (wr_ptr == rd_ptr);
    assign rd_data  = mem[rd_ptr[ADDR_W-1:0]];

    always @(posedge wr_clk or negedge reset_n) begin
        if (!reset_n)
            wr_ptr <= 0;
        else if (wr_en && !wr_full) begin
            mem[wr_ptr[ADDR_W-1:0]] <= wr_data;
            wr_ptr <= wr_ptr + 1;
        end
    end

    always @(posedge rd_clk or negedge reset_n) begin
        if (!reset_n)
            rd_ptr <= 0;
        else if (rd_en && !rd_empty)
            rd_ptr <= rd_ptr + 1;
    end

endmodule
