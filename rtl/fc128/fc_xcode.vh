// Clause 119 256b/257b transcoding for this bridge's 66-bit blocks.
//
// tx_coded bit 0 is the first transmitted sync bit. In this RTL that is
// sync[1]: data is 2'b01, control is 2'b10. Payload bit 0 is the first
// transmitted payload bit (data[0]).
//
// A 257-bit word with bit 0 set is four data payloads. A word with bit 0
// clear and any of bits [4:1] clear has at least one control block: bit
// [j+1] is 1 when block j is data. The second nibble of the first control
// block's first byte is omitted and rebuilt from the first nibble.
// Figure 82-5 supplies that nibble, except first-nibble 0xC restores 0xB
// so an FC ordered set (K28.5 = 0xBC) survives. Ethernet 0xCC is the
// block type that nibble would otherwise rebuild. An unknown nibble
// restores 0 and invalidates that control block's sync header.
// Bit 0 clear and bits [4:1] all set is the invalid-sync coding of 119.2.4.2.

function automatic [3:0] fc_xcode_hi_nibble(input [3:0] lo);
  begin
    case (lo)
      4'h1: fc_xcode_hi_nibble = 4'hE; // 0xE1
      4'h2: fc_xcode_hi_nibble = 4'hD; // 0xD2
      4'h3: fc_xcode_hi_nibble = 4'h3; // 0x33
      4'h4: fc_xcode_hi_nibble = 4'hB; // 0xB4
      4'h5: fc_xcode_hi_nibble = 4'h5; // 0x55
      4'h6: fc_xcode_hi_nibble = 4'h6; // 0x66
      4'h7: fc_xcode_hi_nibble = 4'h8; // 0x87
      4'h8: fc_xcode_hi_nibble = 4'h7; // 0x78
      4'h9: fc_xcode_hi_nibble = 4'h9; // 0x99
      4'hA: fc_xcode_hi_nibble = 4'hA; // 0xAA
      4'hB: fc_xcode_hi_nibble = 4'h4; // 0x4B
      4'hC: fc_xcode_hi_nibble = 4'hB; // 0xBC, K28.5
      4'hD: fc_xcode_hi_nibble = 4'h2; // 0x2D
      4'hE: fc_xcode_hi_nibble = 4'h1; // 0x1E
      4'hF: fc_xcode_hi_nibble = 4'hF; // 0xFF
      default: fc_xcode_hi_nibble = 4'h0;
    endcase
  end
endfunction

function automatic [256:0] fc_xcode_enc(
  input [1:0]  s0, input [63:0] d0,
  input [1:0]  s1, input [63:0] d1,
  input [1:0]  s2, input [63:0] d2,
  input [1:0]  s3, input [63:0] d3
);
  reg          all_data;
  reg          any_bad;
  reg [1:0]    c;
  reg [3:0]    pos;
  reg [255:0]  payloads;
  reg [256:0]  x;
  begin
    all_data = (s0 == FC_SYNC_DATA) && (s1 == FC_SYNC_DATA) &&
               (s2 == FC_SYNC_DATA) && (s3 == FC_SYNC_DATA);
    any_bad = ((s0 != FC_SYNC_DATA) && (s0 != FC_SYNC_CTRL)) ||
              ((s1 != FC_SYNC_DATA) && (s1 != FC_SYNC_CTRL)) ||
              ((s2 != FC_SYNC_DATA) && (s2 != FC_SYNC_CTRL)) ||
              ((s3 != FC_SYNC_DATA) && (s3 != FC_SYNC_CTRL));
    pos = {(s3 == FC_SYNC_DATA), (s2 == FC_SYNC_DATA),
           (s1 == FC_SYNC_DATA), (s0 == FC_SYNC_DATA)};
    payloads = {d3, d2, d1, d0};
    if (s0 == FC_SYNC_CTRL)
      c = 2'd0;
    else if (s1 == FC_SYNC_CTRL)
      c = 2'd1;
    else if (s2 == FC_SYNC_CTRL)
      c = 2'd2;
    else
      c = 2'd3;

    x = 257'h0;
    if (!any_bad && all_data) begin
      x[0]       = 1'b1;
      x[64:1]    = d0;
      x[128:65]  = d1;
      x[192:129] = d2;
      x[256:193] = d3;
    end else if (!any_bad) begin
      x[0]   = 1'b0;
      x[4:1] = pos;
      case (c)
        2'd0: begin
          x[8:5]   = payloads[3:0];
          x[256:9] = payloads[255:8];
        end
        2'd1: begin
          x[72:5]   = payloads[67:0];
          x[256:73] = payloads[255:72];
        end
        2'd2: begin
          x[136:5]   = payloads[131:0];
          x[256:137] = payloads[255:136];
        end
        default: begin
          x[200:5]   = payloads[195:0];
          x[256:201] = payloads[255:200];
        end
      endcase
    end else begin
      x[0]     = 1'b0;
      x[4:1]   = 4'b1111;
      x[8:5]   = payloads[3:0];
      x[256:9] = payloads[255:8];
    end
    fc_xcode_enc = x;
  end
endfunction

// Four recovered blocks, each {sync[1:0], data[63:0]}, block 0 in [65:0].
function automatic [263:0] fc_xcode_dec(input [256:0] x);
  reg          invalid;
  reg [1:0]    c;
  reg [3:0]    pos;
  reg [3:0]    lo;
  reg [3:0]    hi;
  reg [255:0]  p;
  reg [1:0]    s0, s1, s2, s3;
  reg [63:0]   d0, d1, d2, d3;
  begin
    pos = x[4:1];
    invalid = (x[0] == 1'b0) && (pos == 4'b1111);
    if (x[0] == 1'b1) begin
      d0 = x[64:1];
      d1 = x[128:65];
      d2 = x[192:129];
      d3 = x[256:193];
      s0 = FC_SYNC_DATA;
      s1 = FC_SYNC_DATA;
      s2 = FC_SYNC_DATA;
      s3 = FC_SYNC_DATA;
    end else begin
      if (pos[0] == 1'b0)
        c = 2'd0;
      else if (pos[1] == 1'b0)
        c = 2'd1;
      else if (pos[2] == 1'b0)
        c = 2'd2;
      else
        c = 2'd3;
      if (invalid)
        c = 2'd0;

      p = 256'h0;
      case (c)
        2'd0: begin
          lo      = x[8:5];
          hi      = invalid ? 4'h0 : fc_xcode_hi_nibble(lo);
          p[3:0]  = lo;
          p[7:4]  = hi;
          p[255:8] = x[256:9];
        end
        2'd1: begin
          p[67:0]  = x[72:5];
          lo       = p[67:64];
          hi       = fc_xcode_hi_nibble(lo);
          p[71:68] = hi;
          p[255:72] = x[256:73];
        end
        2'd2: begin
          p[131:0]   = x[136:5];
          lo         = p[131:128];
          hi         = fc_xcode_hi_nibble(lo);
          p[135:132] = hi;
          p[255:136] = x[256:137];
        end
        default: begin
          p[195:0]   = x[200:5];
          lo         = p[195:192];
          hi         = fc_xcode_hi_nibble(lo);
          p[199:196] = hi;
          p[255:200] = x[256:201];
        end
      endcase

      d0 = p[63:0];
      d1 = p[127:64];
      d2 = p[191:128];
      d3 = p[255:192];

      if (invalid) begin
        s0 = 2'b00;
        s1 = 2'b11;
        s2 = 2'b00;
        s3 = 2'b11;
      end else begin
        s0 = pos[0] ? FC_SYNC_DATA : FC_SYNC_CTRL;
        s1 = pos[1] ? FC_SYNC_DATA : FC_SYNC_CTRL;
        s2 = pos[2] ? FC_SYNC_DATA : FC_SYNC_CTRL;
        s3 = pos[3] ? FC_SYNC_DATA : FC_SYNC_CTRL;
        if (hi == 4'h0) begin
          case (c)
            2'd0: s0 = 2'b11;
            2'd1: s1 = 2'b11;
            2'd2: s2 = 2'b11;
            default: s3 = 2'b11;
          endcase
        end
      end
    end
    fc_xcode_dec = {s3, d3, s2, d2, s1, d1, s0, d0};
  end
endfunction

// Lane map: one 257-bit word on four 66-bit beats. Beat 0 carries
// xcoded[63:0], with xcoded[256] in sync[0] and sync[1] clear so a
// receiver can find the group. Beats 1, 2, 3 use sync 10, 11, 10.
// Sync is not scrambled, so the marker survives fc_scrambler.
function automatic [263:0] fc_xcode_pack(input [256:0] x);
  reg [263:0] p;
  begin
    p[63:0]    = x[63:0];
    p[65:64]   = {1'b0, x[256]};
    p[129:66]  = x[127:64];
    p[131:130] = 2'b10;
    p[195:132] = x[191:128];
    p[197:196] = 2'b11;
    p[261:198] = x[255:192];
    p[263:262] = 2'b10;
    fc_xcode_pack = p;
  end
endfunction

function automatic [256:0] fc_xcode_unpack(
  input [1:0]  s0, input [63:0] d0,
  input [63:0] d1,
  input [63:0] d2,
  input [63:0] d3
);
  reg [256:0] x;
  begin
    x[63:0]    = d0;
    x[127:64]  = d1;
    x[191:128] = d2;
    x[255:192] = d3;
    x[256]     = s0[0];
    fc_xcode_unpack = x;
  end
endfunction

function automatic logic fc_xcode_frame(
  input [1:0] s0, input [1:0] s1, input [1:0] s2, input [1:0] s3
);
  begin
    fc_xcode_frame = (s0[1] == 1'b0) && (s1 == 2'b10) &&
                     (s2 == 2'b11) && (s3 == 2'b10);
  end
endfunction
