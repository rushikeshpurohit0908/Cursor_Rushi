// Shared constants for the FC128 PoC datapath.
// Ordered-set bytes are an internal coding for this bridge so the gearbox,
// credit, and frame checks are executable. They are not a bit-exact FC-FS map.

localparam [1:0] FC_SYNC_DATA = 2'b01;
localparam [1:0] FC_SYNC_CTRL = 2'b10;

localparam [7:0] FC_IDLE = 8'h1E;
localparam [7:0] FC_SOF  = 8'hFB;
localparam [7:0] FC_EOF  = 8'hFD;
localparam [7:0] FC_RRDY = 8'hF1;
// Link primitives. NOS is loss of sync, then OLS -> LR -> LRR -> Idle.
localparam [7:0] FC_NOS  = 8'h11;
localparam [7:0] FC_OLS  = 8'h12;
localparam [7:0] FC_LR   = 8'h14;
localparam [7:0] FC_LRR  = 8'h15;

// fc_link_sm state codes. Active is the only state that passes frames.
localparam [2:0] FC_LS_DOWN = 3'd0;
localparam [2:0] FC_LS_OLS  = 3'd1;
localparam [2:0] FC_LS_LR   = 3'd2;
localparam [2:0] FC_LS_LRR  = 3'd3;
localparam [2:0] FC_LS_ACQ  = 3'd4;
localparam [2:0] FC_LS_ACT  = 3'd5;

// SOF layout: {32'h0, length[15:0], 8'h00, FC_SOF}
// EOF layout: {crc32[31:0], 24'h0, FC_EOF}
// length is the FC payload in bytes. When FEC is enabled the codeword on the
// wire is length+16 and the CRC covers the length payload bytes only.
