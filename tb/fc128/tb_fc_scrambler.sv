`timescale 1ns/1ps
// Scrambler round-trip and the all-zero vector from the all-ones seed.
module tb_fc_scrambler;
  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;

  logic        step = 0;
  logic        descramble = 0;
  logic        en = 1;
  logic [63:0] din = 0;
  logic [63:0] dout;

  fc_scrambler dut (
    .clk(clk), .rst_n(rst_n), .en(en), .descramble(descramble),
    .step(step), .din(din), .dout(dout)
  );

  integer errors, i;
  logic [63:0] plain [0:7];
  logic [63:0] coded [0:7];

  task automatic hold_reset;
    begin
      @(negedge clk);
      rst_n = 1'b0;
      step = 1'b0;
      @(negedge clk);
      rst_n = 1'b1;
      @(negedge clk);
    end
  endtask

  initial begin
    errors = 0;
    hold_reset();
    din = 64'h0;
    @(negedge clk);
    if (dout !== 64'h03FF_FF80_0000_0000) begin
      $display("FAIL zero vector got %h", dout);
      errors = errors + 1;
    end

    hold_reset();
    descramble = 1'b0;
    for (i = 0; i < 8; i = i + 1) begin
      @(negedge clk);
      plain[i] = {32'hA5A5_0000 + i, 32'h0123_4567 + (i << 8)};
      din  = plain[i];
      step = 1'b1;
      #1;
      coded[i] = dout;
      @(posedge clk);
    end
    step = 1'b0;

    hold_reset();
    descramble = 1'b1;
    for (i = 0; i < 8; i = i + 1) begin
      @(negedge clk);
      din  = coded[i];
      step = 1'b1;
      #1;
      if (dout !== plain[i]) begin
        $display("FAIL round-trip %0d got %h exp %h", i, dout, plain[i]);
        errors = errors + 1;
      end
      @(posedge clk);
    end
    step = 1'b0;

    if (errors == 0)
      $display("PASS tb_fc_scrambler");
    else
      $display("FAIL tb_fc_scrambler errors=%0d", errors);
    $finish;
  end
endmodule
