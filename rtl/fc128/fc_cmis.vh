// CMIS 5.0 fields the bridge actually touches.
//
// Lower memory, page 10h, and page 11h follow OIF-CMIS-05.0. The identifier
// is the SFF-8024 code for an SFP/SFP+ (including SFP112) that speaks CMIS.
// Multi-byte monitors are big-endian: byte 14 is the temperature MSB,
// in units of 1/256 C, and byte 16 is the supply MSB, in units of 100 uV.
// ModuleState occupies byte 3 bits [3:1]. An SFP112 data path is lane 1.
// Page 10h byte 128 bit 0 is DPDeinit, byte 130 bit 0 is OutputDisableTx,
// and byte 143 bit 0 is the write-only ApplyDPInit trigger. Page 11h reports
// DPState (byte 128, lane 1 in [3:0]), OutputStatusRx (byte 132),
// OutputStatusTx (byte 133), DPStateChangedFlag (byte 134, clear on read),
// and DPInitPending (byte 235). Lanes in the map are numbered from 1.

localparam [6:0] CMIS_DEV       = 7'h50;
localparam [7:0] CMIS_ID_SFP    = 8'h20;
localparam [7:0] CMIS_REV50     = 8'h50;
localparam [2:0] CMIS_ST_LOW    = 3'd1;
localparam [2:0] CMIS_ST_UP     = 3'd2;
localparam [2:0] CMIS_ST_RDY    = 3'd3;
localparam [2:0] CMIS_ST_DN     = 3'd4;
localparam [2:0] CMIS_ST_FLT    = 3'd5;
localparam [7:0] CMIS_CTL       = 8'd26;
localparam [7:0] CMIS_PAGE      = 8'd127;
localparam [7:0] CMIS_LANE_PAGE = 8'h10;
localparam [7:0] CMIS_STAT_PAGE = 8'h11;
localparam [7:0] CMIS_DPDEINIT  = 8'd128;
localparam [7:0] CMIS_TXDIS     = 8'd130;
localparam [7:0] CMIS_APPLY     = 8'd143;
localparam [7:0] CMIS_OUTRX     = 8'd132;
localparam [7:0] CMIS_OUTTX     = 8'd133;
localparam [7:0] CMIS_DPFLAG    = 8'd134;
localparam [7:0] CMIS_DPPEND    = 8'd235;
localparam [5:0] CMIS_DP_N      = 6'd7;
localparam [5:0] CMIS_POLL_N    = 6'd18;

// Table 8-74. 0h and 8h-Fh are reserved and not used by this path.
localparam [3:0] CMIS_DP_DEACT  = 4'h1;
localparam [3:0] CMIS_DP_INIT   = 4'h2;
localparam [3:0] CMIS_DP_DEINIT = 4'h3;
localparam [3:0] CMIS_DP_ACT    = 4'h4;
localparam [3:0] CMIS_DP_TXON   = 4'h5;
localparam [3:0] CMIS_DP_TXOFF  = 4'h6;
localparam [3:0] CMIS_DP_INITED = 4'h7;
