`timescale 1ns/1ps
// Encode the published vector, correct two symbol errors, and reject 9 errors.
module tb_fc_rs_fec;
  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;

  logic       start, encode, busy, done, fail;
  logic [7:0] k_len;
  logic [3:0] nerr;
  logic [7:0] mem_addr, mem_wdata, mem_rdata;
  logic       mem_we;
  logic [7:0] mem [0:255];

  integer mi;
  initial for (mi = 0; mi < 256; mi = mi + 1) mem[mi] = 8'h00;

  assign mem_rdata = mem[mem_addr];
  always @(posedge clk) if (mem_we) mem[mem_addr] <= mem_wdata;

  fc_rs_fec dut (
    .clk(clk), .rst_n(rst_n), .start(start), .encode(encode), .k_len(k_len),
    .busy(busy), .done(done), .fail(fail), .nerr(nerr),
    .mem_addr(mem_addr), .mem_we(mem_we), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata)
  );

  reg [7:0] MSG [0:7];
  reg [7:0] CW [0:23];
  initial begin
    MSG[0]=8'h11; MSG[1]=8'h22; MSG[2]=8'h33; MSG[3]=8'h44;
    MSG[4]=8'h55; MSG[5]=8'h66; MSG[6]=8'h77; MSG[7]=8'h88;
    CW[0]=8'h11; CW[1]=8'h22; CW[2]=8'h33; CW[3]=8'h44;
    CW[4]=8'h55; CW[5]=8'h66; CW[6]=8'h77; CW[7]=8'h88;
    CW[8]=8'h41; CW[9]=8'h32; CW[10]=8'h18; CW[11]=8'h79;
    CW[12]=8'hD8; CW[13]=8'hEE; CW[14]=8'hDD; CW[15]=8'h91;
    CW[16]=8'h4E; CW[17]=8'h3A; CW[18]=8'hAA; CW[19]=8'h7F;
    CW[20]=8'hA1; CW[21]=8'hC6; CW[22]=8'hC7; CW[23]=8'h79;
  end

  integer errors, i, guard;

  task automatic run;
    input enc;
    input [7:0] k;
    begin
      @(posedge clk);
      encode <= enc;
      k_len  <= k;
      start  <= 1'b1;
      @(posedge clk);
      start  <= 1'b0;
      guard = 0;
      while (!done && guard < 20000) begin
        @(posedge clk);
        guard = guard + 1;
      end
      if (!done) begin
        $display("FAIL fec timeout enc=%0d", enc);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    errors = 0;
    start = 0;
    encode = 0;
    k_len = 0;
    repeat (4) @(posedge clk);
    rst_n = 1;
    @(posedge clk);

    for (i = 0; i < 8; i = i + 1) mem[i] = MSG[i];
    run(1'b1, 8'd8);
    for (i = 0; i < 24; i = i + 1) begin
      if (mem[i] !== CW[i]) begin
        $display("FAIL encode [%0d] got %h exp %h", i, mem[i], CW[i]);
        errors = errors + 1;
      end
    end

    for (i = 0; i < 24; i = i + 1) mem[i] = CW[i];
    mem[2]  = 8'h3C;
    mem[10] = 8'hBD;
    run(1'b0, 8'd8);
    if (fail || nerr != 4'd2) begin
      $display("FAIL decode status fail=%0d nerr=%0d", fail, nerr);
      errors = errors + 1;
    end
    for (i = 0; i < 24; i = i + 1) begin
      if (mem[i] !== CW[i]) begin
        $display("FAIL correct [%0d] got %h exp %h", i, mem[i], CW[i]);
        errors = errors + 1;
      end
    end

    for (i = 0; i < 24; i = i + 1) mem[i] = CW[i];
    for (i = 0; i < 9; i = i + 1) mem[i] = mem[i] ^ 8'hFF;
    run(1'b0, 8'd8);
    if (!fail) begin
      $display("FAIL 9-error case was accepted");
      errors = errors + 1;
    end

    if (errors == 0)
      $display("PASS tb_fc_rs_fec");
    else
      $display("FAIL tb_fc_rs_fec errors=%0d", errors);
    $finish;
  end
endmodule
