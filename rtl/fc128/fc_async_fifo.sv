// First-word fall-through asynchronous FIFO.
// Full/empty use Gray pointers so a delayed pointer never overruns the RAM.
module fc_async_fifo #(
  parameter int WIDTH = 66,
  parameter int DEPTH = 16
) (
  input  logic             wr_clk,
  input  logic             wr_rst_n,
  input  logic             wr_push,
  input  logic [WIDTH-1:0] wr_data,
  output logic             wr_full,

  input  logic             rd_clk,
  input  logic             rd_rst_n,
  input  logic             rd_pop,
  output logic [WIDTH-1:0] rd_data,
  output logic             rd_empty
);
  localparam int AW = $clog2(DEPTH);

  (* ramstyle = "MLAB" *) logic [WIDTH-1:0] mem [0:DEPTH-1];

  logic [AW:0] wr_bin, wr_gray;
  logic [AW:0] rd_bin, rd_gray;
  logic [AW:0] wr_gray_s1, wr_gray_s2;
  logic [AW:0] rd_gray_s1, rd_gray_s2;

  function automatic [AW:0] bin2gray(input [AW:0] b);
    bin2gray = (b >> 1) ^ b;
  endfunction

  assign wr_full  = (bin2gray(wr_bin + {{AW{1'b0}}, 1'b1}) ==
                     {~rd_gray_s2[AW:AW-1], rd_gray_s2[AW-2:0]});
  assign rd_empty = (rd_gray == wr_gray_s2);
  assign rd_data  = mem[rd_bin[AW-1:0]];

  always_ff @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      wr_bin     <= '0;
      wr_gray    <= '0;
      rd_gray_s1 <= '0;
      rd_gray_s2 <= '0;
    end else begin
      rd_gray_s1 <= rd_gray;
      rd_gray_s2 <= rd_gray_s1;
      if (wr_push && !wr_full) begin
        mem[wr_bin[AW-1:0]] <= wr_data;
        wr_bin  <= wr_bin + {{AW{1'b0}}, 1'b1};
        wr_gray <= bin2gray(wr_bin + {{AW{1'b0}}, 1'b1});
      end
    end
  end

  always_ff @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      rd_bin     <= '0;
      rd_gray    <= '0;
      wr_gray_s1 <= '0;
      wr_gray_s2 <= '0;
    end else begin
      wr_gray_s1 <= wr_gray;
      wr_gray_s2 <= wr_gray_s1;
      if (rd_pop && !rd_empty) begin
        rd_bin  <= rd_bin + {{AW{1'b0}}, 1'b1};
        rd_gray <= bin2gray(rd_bin + {{AW{1'b0}}, 1'b1});
      end
    end
  end
endmodule
