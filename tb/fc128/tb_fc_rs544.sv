`timescale 1ns/1ps
// Golden encode, 15-symbol correction, a rejected 16-symbol word, and a
// full-length RS(544,514) word with errors at both ends.
module tb_fc_rs544;
  logic clk = 0;
  logic rst_n = 0;
  always #5 clk = ~clk;

  logic        start, encode, busy, done, fail;
  logic [9:0]  k_len;
  logic [4:0]  nerr;
  logic [9:0]  mem_addr, mem_wdata, mem_rdata;
  logic        mem_we;
  logic [9:0]  mem [0:543];
  logic [9:0]  shadow [0:543];

  integer mi;
  initial for (mi = 0; mi < 544; mi = mi + 1) mem[mi] = 10'h000;

  assign mem_rdata = mem[mem_addr];
  always @(posedge clk) if (mem_we) mem[mem_addr] <= mem_wdata;

  fc_rs544 dut (
    .clk(clk), .rst_n(rst_n), .start(start), .encode(encode), .k_len(k_len),
    .busy(busy), .done(done), .fail(fail), .nerr(nerr),
    .mem_addr(mem_addr), .mem_we(mem_we), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata)
  );

  reg [9:0] MSG [0:7];
  reg [9:0] CW  [0:37];
  initial begin
    MSG[0]=10'h011; MSG[1]=10'h022; MSG[2]=10'h033; MSG[3]=10'h044;
    MSG[4]=10'h155; MSG[5]=10'h266; MSG[6]=10'h077; MSG[7]=10'h088;
    CW[0]=10'h011; CW[1]=10'h022; CW[2]=10'h033; CW[3]=10'h044;
    CW[4]=10'h155; CW[5]=10'h266; CW[6]=10'h077; CW[7]=10'h088;
    CW[8]=10'h3F1; CW[9]=10'h143; CW[10]=10'h004; CW[11]=10'h138;
    CW[12]=10'h215; CW[13]=10'h304; CW[14]=10'h2D8; CW[15]=10'h259;
    CW[16]=10'h295; CW[17]=10'h116; CW[18]=10'h154; CW[19]=10'h33B;
    CW[20]=10'h3DD; CW[21]=10'h0FD; CW[22]=10'h2E5; CW[23]=10'h0E1;
    CW[24]=10'h2AB; CW[25]=10'h265; CW[26]=10'h3D3; CW[27]=10'h17D;
    CW[28]=10'h172; CW[29]=10'h298; CW[30]=10'h2BF; CW[31]=10'h12D;
    CW[32]=10'h126; CW[33]=10'h2EB; CW[34]=10'h2E5; CW[35]=10'h1B8;
    CW[36]=10'h134; CW[37]=10'h2E2;
  end

  integer errors, i, guard;

  task automatic run;
    input        enc;
    input [9:0]  k;
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
        $display("FAIL rs544 timeout enc=%0d k=%0d", enc, k);
        errors = errors + 1;
      end
    end
  endtask

  task automatic expect_word;
    input integer n;
    input integer tag;
    begin
      for (i = 0; i < n; i = i + 1) begin
        if (mem[i] !== shadow[i]) begin
          $display("FAIL word %0d [%0d] got %h exp %h", tag, i, mem[i], shadow[i]);
          errors = errors + 1;
        end
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
    run(1'b1, 10'd8);
    for (i = 0; i < 38; i = i + 1) begin
      if (mem[i] !== CW[i]) begin
        $display("FAIL encode [%0d] got %h exp %h", i, mem[i], CW[i]);
        errors = errors + 1;
      end
    end

    for (i = 0; i < 38; i = i + 1) mem[i] = CW[i];
    run(1'b0, 10'd8);
    if (fail || nerr != 5'd0) begin
      $display("FAIL clean decode fail=%0d nerr=%0d", fail, nerr);
      errors = errors + 1;
    end

    for (i = 0; i < 38; i = i + 1) begin
      mem[i] = CW[i];
      shadow[i] = CW[i];
    end
    for (i = 0; i < 15; i = i + 1) mem[i] = mem[i] ^ 10'h155;
    run(1'b0, 10'd8);
    if (fail || nerr != 5'd15) begin
      $display("FAIL 15-error status fail=%0d nerr=%0d", fail, nerr);
      errors = errors + 1;
    end
    expect_word(38, 15);

    for (i = 0; i < 38; i = i + 1) mem[i] = CW[i];
    for (i = 0; i < 16; i = i + 1) mem[i] = mem[i] ^ 10'h3FF;
    run(1'b0, 10'd8);
    if (!fail) begin
      $display("FAIL 16-error case was accepted nerr=%0d", nerr);
      errors = errors + 1;
    end

    for (i = 0; i < 514; i = i + 1) mem[i] = i[9:0];
    run(1'b1, 10'd514);
    if (fail) begin
      $display("FAIL full encode status");
      errors = errors + 1;
    end
    for (i = 0; i < 544; i = i + 1) shadow[i] = mem[i];
    mem[0]   = mem[0] ^ 10'h2A5;
    mem[513] = mem[513] ^ 10'h2A5;
    mem[543] = mem[543] ^ 10'h2A5;
    run(1'b0, 10'd514);
    if (fail || nerr != 5'd3) begin
      $display("FAIL full decode fail=%0d nerr=%0d", fail, nerr);
      errors = errors + 1;
    end
    expect_word(544, 514);

    if (errors == 0)
      $display("PASS tb_fc_rs544");
    else
      $display("FAIL tb_fc_rs544 errors=%0d", errors);
    $finish;
  end
endmodule
