// Stream four 66-bit blocks through one 257-bit word and back.
// Disabled, both sides are wires. Enabled, the rate matches the block
// stream: a group is accepted while the previous group is leaving.
//
// fc_xcode_tx sits on the client side of the system gearbox. fc_xcode_rx
// sits on the merged, descrambled system stream. The scrambler stays on
// the packed beats, and block lock stays on the recovered sync headers.

module fc_xcode_tx (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        en,
  input  logic        in_valid,
  output logic        in_ready,
  input  logic [1:0]  in_sync,
  input  logic [63:0] in_data,
  output logic        out_valid,
  input  logic        out_ready,
  output logic [1:0]  out_sync,
  output logic [63:0] out_data
);
  `include "fc128_defs.vh"
  `include "fc_xcode.vh"

  logic [1:0]  isync [0:2];
  logic [63:0] idata [0:2];
  logic [2:0]  icnt;
  logic [1:0]  osync [0:3];
  logic [63:0] odata [0:3];
  logic [2:0]  ocnt;
  logic [1:0]  oidx;
  logic [263:0] xpack;

  wire ready_x = (icnt < 3'd3) ||
                 (ocnt == 3'd0) ||
                 ((ocnt == 3'd1) && out_ready);
  wire take = en && rst_n && in_valid && ready_x;

  assign in_ready  = en ? ready_x : out_ready;
  assign out_valid = en ? (ocnt != 3'd0) : in_valid;
  assign out_sync  = en ? osync[oidx] : in_sync;
  assign out_data  = en ? odata[oidx] : in_data;

  always_ff @(posedge clk or negedge rst_n) begin
    reg [2:0]  icnt_n;
    reg [2:0]  ocnt_n;
    reg [1:0]  oidx_n;
    reg [1:0]  s0, s1, s2, s3;
    reg [63:0] d0, d1, d2, d3;
    if (!rst_n || !en) begin
      xpack   = 264'h0;
      icnt     <= 3'd0;
      ocnt     <= 3'd0;
      oidx     <= 2'd0;
      isync[0] <= 2'b00;
      isync[1] <= 2'b00;
      isync[2] <= 2'b00;
      idata[0] <= 64'h0;
      idata[1] <= 64'h0;
      idata[2] <= 64'h0;
      osync[0] <= 2'b00;
      osync[1] <= 2'b00;
      osync[2] <= 2'b00;
      osync[3] <= 2'b00;
      odata[0] <= 64'h0;
      odata[1] <= 64'h0;
      odata[2] <= 64'h0;
      odata[3] <= 64'h0;
    end else begin
      icnt_n = icnt;
      ocnt_n = ocnt;
      oidx_n = oidx;
      if ((ocnt != 3'd0) && out_ready) begin
        ocnt_n = ocnt - 3'd1;
        oidx_n = oidx + 2'd1;
      end
      if (take)
        icnt_n = icnt + 3'd1;

      s0 = isync[0];
      d0 = idata[0];
      s1 = isync[1];
      d1 = idata[1];
      s2 = isync[2];
      d2 = idata[2];
      s3 = in_sync;
      d3 = in_data;

      if (take && (icnt < 3'd3)) begin
        xpack      = xpack;
        isync[icnt] <= in_sync;
        idata[icnt] <= in_data;
        icnt        <= icnt_n;
        ocnt        <= ocnt_n;
        oidx        <= oidx_n;
      end else if (take && (ocnt_n == 3'd0)) begin
        xpack = fc_xcode_pack(fc_xcode_enc(s0, d0, s1, d1, s2, d2, s3, d3));
        osync[0] <= xpack[65:64];
        odata[0] <= xpack[63:0];
        osync[1] <= xpack[131:130];
        odata[1] <= xpack[129:66];
        osync[2] <= xpack[197:196];
        odata[2] <= xpack[195:132];
        osync[3] <= xpack[263:262];
        odata[3] <= xpack[261:198];
        icnt <= 3'd0;
        ocnt <= 3'd4;
        oidx <= 2'd0;
      end else begin
        xpack = xpack;
        ocnt <= ocnt_n;
        oidx <= oidx_n;
      end
    end
  end
endmodule

module fc_xcode_rx (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        en,
  input  logic        in_valid,
  output logic        in_ready,
  input  logic [1:0]  in_sync,
  input  logic [63:0] in_data,
  output logic        out_valid,
  input  logic        out_ready,
  output logic [1:0]  out_sync,
  output logic [63:0] out_data
);
  `include "fc128_defs.vh"
  `include "fc_xcode.vh"

  logic        aligned;
  logic [2:0]  cap_n;
  logic [1:0]  csync [0:2];
  logic [63:0] cdata [0:2];
  logic [1:0]  osync [0:3];
  logic [63:0] odata [0:3];
  logic [2:0]  ocnt;
  logic [1:0]  oidx;
  logic [263:0] blk;

  wire completing = aligned && (cap_n == 3'd3);
  wire queue_room = (ocnt == 3'd0) || ((ocnt == 3'd1) && out_ready);
  wire ready_x = !completing || queue_room;
  wire take = en && rst_n && in_valid && ready_x;

  assign in_ready  = en ? ready_x : out_ready;
  assign out_valid = en ? (ocnt != 3'd0) : in_valid;
  assign out_sync  = en ? osync[oidx] : in_sync;
  assign out_data  = en ? odata[oidx] : in_data;

  always_ff @(posedge clk or negedge rst_n) begin
    reg [2:0]   ocnt_n;
    reg [1:0]   oidx_n;
    reg [1:0]   s0, s1, s2, s3;
    reg [63:0]  d0, d1, d2, d3;
    if (!rst_n || !en) begin
      blk      = 264'h0;
      aligned  <= 1'b0;
      cap_n    <= 3'd0;
      ocnt     <= 3'd0;
      oidx     <= 2'd0;
      csync[0] <= 2'b00;
      csync[1] <= 2'b00;
      csync[2] <= 2'b00;
      cdata[0] <= 64'h0;
      cdata[1] <= 64'h0;
      cdata[2] <= 64'h0;
      osync[0] <= 2'b00;
      osync[1] <= 2'b00;
      osync[2] <= 2'b00;
      osync[3] <= 2'b00;
      odata[0] <= 64'h0;
      odata[1] <= 64'h0;
      odata[2] <= 64'h0;
      odata[3] <= 64'h0;
    end else begin
      ocnt_n = ocnt;
      oidx_n = oidx;
      if ((ocnt != 3'd0) && out_ready) begin
        ocnt_n = ocnt - 3'd1;
        oidx_n = oidx + 2'd1;
      end

      if (!take) begin
        ocnt <= ocnt_n;
        oidx <= oidx_n;
      end else if (!aligned) begin
        if (in_sync[1] == 1'b0) begin
          csync[0] <= in_sync;
          cdata[0] <= in_data;
          cap_n    <= 3'd1;
          aligned  <= 1'b1;
        end
        ocnt <= ocnt_n;
        oidx <= oidx_n;
      end else if (in_sync[1] == 1'b0) begin
        csync[0] <= in_sync;
        cdata[0] <= in_data;
        cap_n    <= 3'd1;
        ocnt     <= ocnt_n;
        oidx     <= oidx_n;
      end else if (cap_n != 3'd3) begin
        csync[cap_n] <= in_sync;
        cdata[cap_n] <= in_data;
        cap_n        <= cap_n + 3'd1;
        ocnt         <= ocnt_n;
        oidx         <= oidx_n;
      end else begin
        s0 = csync[0];
        d0 = cdata[0];
        s1 = csync[1];
        d1 = cdata[1];
        s2 = csync[2];
        d2 = cdata[2];
        s3 = in_sync;
        d3 = in_data;
        aligned <= 1'b0;
        cap_n   <= 3'd0;
        if (fc_xcode_frame(s0, s1, s2, s3) && (ocnt_n == 3'd0)) begin
          blk = fc_xcode_dec(fc_xcode_unpack(s0, d0, d1, d2, d3));
          osync[0] <= blk[65:64];
          odata[0] <= blk[63:0];
          osync[1] <= blk[131:130];
          odata[1] <= blk[129:66];
          osync[2] <= blk[197:196];
          odata[2] <= blk[195:132];
          osync[3] <= blk[263:262];
          odata[3] <= blk[261:198];
          ocnt <= 3'd4;
          oidx <= 2'd0;
        end else begin
          ocnt <= ocnt_n;
          oidx <= oidx_n;
        end
      end
    end
  end
endmodule
