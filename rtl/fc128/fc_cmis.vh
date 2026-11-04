// CMIS 5.0 fields the bridge actually touches.
//
// Lower memory, page 10h, and page 11h follow OIF-CMIS-05.0. The identifier
// is the SFF-8024 code for an SFP/SFP+ (including SFP112) that speaks CMIS.
// Multi-byte monitors are big-endian: byte 14 is the temperature MSB,
// in units of 1/256 C, and byte 16 is the supply MSB, in units of 100 uV.
// ModuleState occupies byte 3 bits [3:1]. An SFP112 data path is lane 1.
// Page 10h byte 128 bit 0 is DPDeinit, byte 130 bit 0 is OutputDisableTx,
// byte 132 bit 0 is OutputSquelchForceTx, and byte 143 bit 0 is the
// write-only ApplyDPInit trigger. Page 10h byte 145 is the staged AppSel
// for lane 1: AppSelCode [7:4], DataPathID [3:1], ExplicitControl [0].
// Page 11h reports DPState (byte 128, lane 1 in [3:0]), OutputStatusRx
// (byte 132), OutputStatusTx (byte 133), DPStateChangedFlag (byte 134,
// clear on read), ConfigStatus (byte 202 [3:0]), the active AppSel
// (byte 206), and DPInitPending (byte 235). Bytes 135, 136, 137, 147, and
// 148 are the lane-1 clear-on-read flags FailureFlagTx, LOSFlagTx,
// CDRLOLFlagTx, LOSFlagRx, and CDRLOLFlagRx. A flag stays set while its
// input is set, and a pulse is held until that byte is read. Page 10h
// bytes 214, 215, 216, 226, and 227 bit 0 are the matching masks. Bits
// [7:1] are preserved and power up at 1. An unmasked flag forces lower
// byte 3 bit 0 to 0 and drives IntL low. Byte 2 bit 6, SteppedConfigOnly,
// stays clear. Lower bytes 86-97 advertise three one-lane applications.
// Lanes in the map are numbered from 1.

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
localparam [7:0] CMIS_SQFORCE   = 8'd132;
localparam [7:0] CMIS_APPLY     = 8'd143;
localparam [7:0] CMIS_SCS0      = 8'd145;
localparam [7:0] CMIS_OUTRX     = 8'd132;
localparam [7:0] CMIS_OUTTX     = 8'd133;
localparam [7:0] CMIS_DPFLAG    = 8'd134;
localparam [7:0] CMIS_FFAILTX   = 8'd135;
localparam [7:0] CMIS_FLOSTX    = 8'd136;
localparam [7:0] CMIS_FLOLTX    = 8'd137;
localparam [7:0] CMIS_FLOSRX    = 8'd147;
localparam [7:0] CMIS_FLOLRX    = 8'd148;
localparam [7:0] CMIS_MFAILTX   = 8'd214;
localparam [7:0] CMIS_MLOSTX    = 8'd215;
localparam [7:0] CMIS_MLOLTX    = 8'd216;
localparam [7:0] CMIS_MLOSRX    = 8'd226;
localparam [7:0] CMIS_MLOLRX    = 8'd227;
localparam [7:0] CMIS_CFGSTAT   = 8'd202;
localparam [7:0] CMIS_ACS0      = 8'd206;
localparam [7:0] CMIS_DPPEND    = 8'd235;
localparam [7:0] CMIS_APP_BASE  = 8'd86;
localparam [5:0] CMIS_DP_N      = 6'd7;
// Bytes 128..148, so the status pass also collects the five lane flags.
localparam [5:0] CMIS_LANE_N    = 6'd21;
localparam [5:0] CMIS_POLL_N    = 6'd18;
// SFF-8024 host electrical IDs and single-mode Fibre Channel media IDs.
localparam [7:0] CMIS_H_128     = 8'h4A;
localparam [7:0] CMIS_H_64      = 8'h29;
localparam [7:0] CMIS_H_32      = 8'h28;
localparam [7:0] CMIS_M_128     = 8'h45;
localparam [7:0] CMIS_M_64      = 8'h23;
localparam [7:0] CMIS_M_32      = 8'h22;
localparam [7:0] CMIS_LANES11   = 8'h11;
localparam [7:0] CMIS_LANE1     = 8'h01;
// AppSel 1, DataPathID 0 (lane 1), explicit control clear.
localparam [7:0] CMIS_APP_128   = 8'h10;

// Table 8-74. 0h and 8h-Fh are reserved and not used by this path.
localparam [3:0] CMIS_DP_DEACT  = 4'h1;
localparam [3:0] CMIS_DP_INIT   = 4'h2;
localparam [3:0] CMIS_DP_DEINIT = 4'h3;
localparam [3:0] CMIS_DP_ACT    = 4'h4;
localparam [3:0] CMIS_DP_TXON   = 4'h5;
localparam [3:0] CMIS_DP_TXOFF  = 4'h6;
localparam [3:0] CMIS_DP_INITED = 4'h7;
// ConfigStatus, page 11h byte 202 bits [3:0].
localparam [3:0] CMIS_CFG_NONE  = 4'h0;
localparam [3:0] CMIS_CFG_OK    = 4'h1;
localparam [3:0] CMIS_CFG_REJ   = 4'h2;
localparam [3:0] CMIS_CFG_APP   = 4'h3;
localparam [3:0] CMIS_CFG_DP    = 4'h4;
localparam [3:0] CMIS_CFG_BUSY  = 4'hC;
