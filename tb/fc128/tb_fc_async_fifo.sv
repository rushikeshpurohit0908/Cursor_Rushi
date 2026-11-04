`timescale 1ns/1ps
// Cross two clocks, stall on full, and check every word comes back in order.
module tb_fc_async_fifo;
  logic wr_clk = 0;
  logic rd_clk = 0;
  logic wr_rst_n = 0;
  logic rd_rst_n = 0;
  always #5 wr_clk = ~wr_clk;
  initial begin
    #1;
    forever #3 rd_clk = ~rd_clk;
  end

  logic        wr_push, wr_full, rd_pop, rd_empty;
  logic [15:0] wr_data, rd_data;

  fc_async_fifo #(.WIDTH(16), .DEPTH(16)) dut (
    .wr_clk(wr_clk), .wr_rst_n(wr_rst_n), .wr_push(wr_push),
    .wr_data(wr_data), .wr_full(wr_full),
    .rd_clk(rd_clk), .rd_rst_n(rd_rst_n), .rd_pop(rd_pop),
    .rd_data(rd_data), .rd_empty(rd_empty)
  );

  integer errors;
  integer sent;
  integer got;
  integer guard;

  initial begin
    errors = 0;
    sent = 0;
    wr_push = 0;
    wr_data = 0;
    repeat (4) @(posedge wr_clk);
    wr_rst_n = 1;
    @(posedge wr_clk);
    while (sent < 40) begin
      if (!wr_full) begin
        wr_push <= 1'b1;
        wr_data <= sent[15:0];
        sent    <= sent + 1;
      end else begin
        wr_push <= 1'b0;
      end
      @(posedge wr_clk);
    end
    wr_push <= 1'b0;
  end

  initial begin
    got = 0;
    rd_pop = 0;
    repeat (6) @(posedge rd_clk);
    rd_rst_n = 1;
    @(posedge rd_clk);
    guard = 0;
    while (got < 40 && guard < 5000) begin
      @(posedge rd_clk);
      guard = guard + 1;
      if (rd_pop && !rd_empty) begin
        if (rd_data !== got[15:0]) begin
          $display("FAIL fifo data %h exp %h at %0d", rd_data, got[15:0], got);
          errors = errors + 1;
        end
        got = got + 1;
      end
      // Pop on the following edge so rd_data is the word being accepted.
      if (!rd_empty && ((guard % 3) != 0))
        rd_pop <= 1'b1;
      else
        rd_pop <= 1'b0;
    end
    if (got != 40) begin
      $display("FAIL fifo got %0d words", got);
      errors = errors + 1;
    end
    if (errors == 0)
      $display("PASS tb_fc_async_fifo");
    else
      $display("FAIL tb_fc_async_fifo errors=%0d", errors);
    $finish;
  end
endmodule
