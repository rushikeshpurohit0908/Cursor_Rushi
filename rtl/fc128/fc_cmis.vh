// CMIS 5.0 fields the bridge actually touches.
//
// Lower memory and page 10h follow OIF-CMIS-05.0. The identifier is the
// SFF-8024 code for an SFP/SFP+ (including SFP112) that speaks CMIS.
// Multi-byte monitors are big-endian: byte 14 is the temperature MSB,
// in units of 1/256 C, and byte 16 is the supply MSB, in units of 100 uV.
// ModuleState occupies byte 3 bits [3:1]. OutputDisableTx for media lane 1
// is page 10h byte 130 bit 0. DPDeinit for host lane 1 is page 10h byte 128
// bit 0. Page 11h byte 128 bits [3:0] are that lane's data path state.
// Lanes in the map are numbered from 1.

localparam [6:0] CMIS_DEV      = 7'h50;
localparam [7:0] CMIS_ID_SFP   = 8'h20;
localparam [7:0] CMIS_REV50    = 8'h50;
localparam [2:0] CMIS_ST_LOW   = 3'd1;
localparam [2:0] CMIS_ST_UP    = 3'd2;
localparam [2:0] CMIS_ST_RDY   = 3'd3;
localparam [2:0] CMIS_ST_DN    = 3'd4;
localparam [2:0] CMIS_ST_FLT   = 3'd5;
localparam [7:0] CMIS_CTL      = 8'd26;
localparam [7:0] CMIS_PAGE     = 8'd127;
localparam [7:0] CMIS_LANE_PAGE = 8'h10;
localparam [7:0] CMIS_STAT_PAGE = 8'h11;
localparam [7:0] CMIS_DPDEINIT = 8'd128;
localparam [7:0] CMIS_TXDIS    = 8'd130;
localparam [5:0] CMIS_POLL_N   = 6'd18;
// CMIS 5.0 data path state encodings.
localparam [3:0] CMIS_DP_DEACT  = 4'h1;
localparam [3:0] CMIS_DP_INIT   = 4'h2;
localparam [3:0] CMIS_DP_DEINIT = 4'h3;
localparam [3:0] CMIS_DP_ACT    = 4'h4;
localparam [3:0] CMIS_DP_TXON   = 4'h5;
localparam [3:0] CMIS_DP_TXOFF  = 4'h6;
localparam [3:0] CMIS_DP_INITD  = 4'h7;
