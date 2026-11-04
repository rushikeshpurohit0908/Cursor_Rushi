// Reflected CRC-32 used by Fibre Channel frames (poly 0x04C11DB7).
// Init 0xFFFFFFFF, final value is the one's complement. "123456789" -> 0xCBF43926.

function automatic [31:0] crc32_update(input [31:0] crc_in, input [7:0] data);
  integer ci;
  reg [31:0] c;
  begin
    c = crc_in ^ {24'h0, data};
    for (ci = 0; ci < 8; ci = ci + 1) begin
      if (c[0])
        c = (c >> 1) ^ 32'hEDB88320;
      else
        c = c >> 1;
    end
    crc32_update = c;
  end
endfunction
