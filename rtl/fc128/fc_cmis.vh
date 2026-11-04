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
// byte 3 bit 0 to 0 and drives IntL low. Bytes 154-155, 170-171, and
// 186-187 are lane-1 OpticalPowerTx, LaserBiasTx, and OpticalPowerRx.
// Power counts 0.1 uW and bias counts 2 uA. The lower address is the
// MSB, and a read leaves the value in place. Bytes 139-146 and 149-152
// are the Tx-power, laser-bias, and Rx-power high-alarm, low-alarm,
// high-warning, and low-warning flags. A high flag is the monitor above
// the fixed threshold; a low flag is the monitor below it. The flag
// stays set while that comparison is true and holds a pulse until the
// byte is read. Page 10h bytes 218-225 and 228-231 bit 0 are those
// masks and power up at 1. An unmasked flag is part of IntL. Byte 2
// bit 6, SteppedConfigOnly, stays clear. Lower bytes 86-97 advertise
// three one-lane applications. Lanes in the map are numbered from 1.

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
localparam [7:0] CMIS_OPT_TX    = 8'd154;
localparam [7:0] CMIS_BIAS_TX   = 8'd170;
localparam [7:0] CMIS_OPT_RX    = 8'd186;
localparam [7:0] CMIS_F_TXHA    = 8'd139;
localparam [7:0] CMIS_F_TXLA    = 8'd140;
localparam [7:0] CMIS_F_TXHW    = 8'd141;
localparam [7:0] CMIS_F_TXLW    = 8'd142;
localparam [7:0] CMIS_F_BIHA    = 8'd143;
localparam [7:0] CMIS_F_BILA    = 8'd144;
localparam [7:0] CMIS_F_BIHW    = 8'd145;
localparam [7:0] CMIS_F_BILW    = 8'd146;
localparam [7:0] CMIS_F_RXHA    = 8'd149;
localparam [7:0] CMIS_F_RXLA    = 8'd150;
localparam [7:0] CMIS_F_RXHW    = 8'd151;
localparam [7:0] CMIS_F_RXLW    = 8'd152;
localparam [7:0] CMIS_M_TXHA    = 8'd218;
localparam [7:0] CMIS_M_TXLA    = 8'd219;
localparam [7:0] CMIS_M_TXHW    = 8'd220;
localparam [7:0] CMIS_M_TXLW    = 8'd221;
localparam [7:0] CMIS_M_BIHA    = 8'd222;
localparam [7:0] CMIS_M_BILA    = 8'd223;
localparam [7:0] CMIS_M_BIHW    = 8'd224;
localparam [7:0] CMIS_M_BILW    = 8'd225;
localparam [7:0] CMIS_M_RXHA    = 8'd228;
localparam [7:0] CMIS_M_RXLA    = 8'd229;
localparam [7:0] CMIS_M_RXHW    = 8'd230;
localparam [7:0] CMIS_M_RXLW    = 8'd231;
// Table 8-55 thresholds, fixed for this host. Unsigned. A value equal
// to the threshold does not set the flag.
localparam [15:0] CMIS_TX_HA    = 16'd20000;
localparam [15:0] CMIS_TX_HW    = 16'd15000;
localparam [15:0] CMIS_TX_LW    = 16'd2000;
localparam [15:0] CMIS_TX_LA    = 16'd1000;
localparam [15:0] CMIS_BI_HA    = 16'd40000;
localparam [15:0] CMIS_BI_HW    = 16'd30000;
localparam [15:0] CMIS_BI_LW    = 16'd10000;
localparam [15:0] CMIS_BI_LA    = 16'd5000;
localparam [15:0] CMIS_RX_HA    = 16'd10000;
localparam [15:0] CMIS_RX_HW    = 16'd5000;
localparam [15:0] CMIS_RX_LW    = 16'd100;
localparam [15:0] CMIS_RX_LA    = 16'd32;
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
