// CMIS 5.0 fields the bridge actually touches.
//
// Lower memory and page 10h follow OIF-CMIS-05.0. The identifier is the
// SFF-8024 code for an SFP/SFP+ (including SFP112) that speaks CMIS.
// Multi-byte monitors are big-endian: byte 14 is the temperature MSB,
// in units of 1/256 C, and byte 16 is the supply MSB, in units of 100 uV.
// ModuleState occupies byte 3 bits [3:1]. Byte 2 bit 6 is SteppedConfigOnly
// and stays clear, so ApplyDPInit may reconfigure an active lane.
// OutputDisableTx for media lane 1 is page 10h byte 130 bit 0.
// OutputSquelchForceTx is page 10h byte 132 bit 0. DPDeinit for host lane 1
// is page 10h byte 128 bit 0. Page 10h byte 143 bit 0 is the write-only
// ApplyDPInit trigger. Page 10h byte 145 is staged AppSel for lane 1:
// AppSelCode [7:4], DataPathID [3:1], ExplicitControl [0].
// Page 11h byte 128 bits [3:0] are that lane's data path state. Byte 132
// bit 0 is OutputStatusRx, byte 133 bit 0 is OutputStatusTx, and byte 134
// bit 0 is DPStateChangedFlag (clear on read, steady states only).
// Byte 202 bits [3:0] are ConfigStatus. Byte 206 is the active AppSel.
// Byte 235 bit 0 is DPInitPending. Bytes 135, 136, and 137 are the lane-1
// FailureFlagTx, LOSFlagTx, and CDRLOLFlagTx latches. Bytes 147 and 148 are
// LOSFlagRx and CDRLOLFlagRx. Each is clear-on-read. The matching mask bits
// are page 10h bytes 214, 215, 216, 226, and 227, and a 1 masks that flag
// out of the interrupt. Bytes 154-155, 170-171, and 186-187 are the lane-1
// OpticalPowerTx, LaserBiasTx, and OpticalPowerRx monitors (Table 8-79).
// Power is an unsigned count of 0.1 uW. Bias is an unsigned count of 2 uA
// (page 01h byte 160 scaling factor 1). The first byte of each pair is the
// MSB. These monitors are not clear-on-read. Bytes 139-146 and 149-152 are
// the lane-1 high/low alarm and warning flags for those monitors (Tables
// 8-77 and 8-78). A high flag is set when the monitor is greater than the
// matching page 02h threshold, and a low flag when it is less (Table 8-55).
// Each flag is clear-on-read and stays set while the comparison is still
// true. The matching mask bits are page 10h bytes 218-225 and 228-231.
// Lower byte 9 holds the module temperature and supply flags (Table 8-9).
// Bits [7:4] are TempMon high alarm, low alarm, high warning, low warning.
// Bits [3:0] are the same four flags for VccMon. Temperature is signed,
// in units of 1/256 C. A high flag is the monitor greater than the page 02h
// threshold (bytes 128-143, Table 8-40) and a low flag is the monitor less
// than it. Byte 32 is the matching mask. A read of byte 9 clears a latch
// whose comparison is no longer true.
// Lower byte 8 bit 0 is ModuleStateChangedFlag (Table 8-8). Table 6-9 sets
// it on entry to ModuleLowPwr, ModuleReady, and ModuleFault, and suppresses
// it when that state's exit condition is already true. ModulePwrUp and
// ModulePwrDn do not set it. A read of byte 8 clears it. It does not stay
// set just because the module remains in the new state. Byte 31 bit 0 is
// ModuleStateChangedMask (Table 8-11). Bits [7:1] of that byte are left as
// the module set them.
// Lower bytes 18-19 and 20-21 are Aux1Mon and Aux2Mon. Aux1 is laser
// temperature, signed 1/256 C. Aux2 is TEC current, signed, in units of
// 100/32767 percent. Byte 10 is the eight clear-on-read flags: Aux1 high
// alarm, low alarm, high warning, low warning, then the same four for Aux2.
// A high flag is the monitor greater than the page 02h threshold (bytes
// 144-159) and a low flag is the monitor less than it. Equality is not a
// flag. A negative TEC current must not set a high alarm. Byte 33 is the
// matching mask, the whole byte. A read of byte 10 clears a latch whose
// comparison is no longer true. Bytes 18-21 are not clear-on-read.
// Lower bytes 22-23 and 24-25 are Aux3Mon and CustomMon. Aux3 is the
// additional supply Vcc2, signed, in units of 100 uV. Custom is laser
// frequency error, signed, in units of 1 MHz. Byte 11 is the eight
// clear-on-read flags: Aux3 high alarm, low alarm, high warning, low
// warning, then the same four for Custom. A high flag is the monitor
// greater than the page 02h threshold (bytes 160-175) and a low flag is
// the monitor less than it. Equality is not a flag. A negative Vcc2 or
// frequency error must not set a high alarm. Byte 34 is the matching
// mask, the whole byte. A read of byte 11 clears a latch whose comparison
// is no longer true. Bytes 22-25 are not clear-on-read.
// Page 00h bytes 128-143 are VendorName and bytes 148-163 are VendorPN.
// Each field is 16 space-padded ASCII characters. Byte 128 is the first
// character. Writes to those bytes do not change the value.
// Lanes in the map are numbered from 1.
// Lower bytes 86-97 advertise three one-lane applications. Host interface
// IDs are SFF-8024 Table 4-5. Media IDs are the single-mode Fibre Channel
// codes in Table 4-7: 128GFC-SM, 64GFC-SM, and 32GFC-SM.

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
localparam [7:0] CMIS_SQFORCE  = 8'd132;
localparam [7:0] CMIS_APPLY    = 8'd143;
localparam [7:0] CMIS_SCS0     = 8'd145;
localparam [7:0] CMIS_OUTRX    = 8'd132;
localparam [7:0] CMIS_OUTTX    = 8'd133;
localparam [7:0] CMIS_DPFLAG   = 8'd134;
localparam [7:0] CMIS_FAILTX   = 8'd135;
localparam [7:0] CMIS_LOSTX    = 8'd136;
localparam [7:0] CMIS_LOLTX    = 8'd137;
localparam [7:0] CMIS_ALM_TX   = 8'd139;
localparam [7:0] CMIS_ALM_RX   = 8'd149;
localparam [7:0] CMIS_MOD_FLG  = 8'd8;
localparam [7:0] CMIS_MON_FLG  = 8'd9;
localparam [7:0] CMIS_AUX_FLG  = 8'd10;
localparam [7:0] CMIS_A3_FLG   = 8'd11;
localparam [7:0] CMIS_AUX1_MON = 8'd18;
localparam [7:0] CMIS_AUX2_MON = 8'd20;
localparam [7:0] CMIS_AUX3_MON = 8'd22;
localparam [7:0] CMIS_CUST_MON = 8'd24;
localparam [7:0] CMIS_VEND_PAGE = 8'h00;
localparam [7:0] CMIS_VNAME = 8'd128;
localparam [7:0] CMIS_VPN   = 8'd148;
// Page 00h, space-padded. Byte 128 is the MSB of the first word.
// "ALTERA" and "SFP112-128GFC".
localparam [127:0] CMIS_VENDOR_NAME = 128'h414C5445524120202020202020202020;
localparam [127:0] CMIS_VENDOR_PN   = 128'h5346503131322D313238474643202020;
localparam [7:0] CMIS_MSK_SC   = 8'd31;
localparam [7:0] CMIS_MSK_MON  = 8'd32;
localparam [7:0] CMIS_MSK_AUX  = 8'd33;
localparam [7:0] CMIS_MSK_A3   = 8'd34;
localparam [7:0] CMIS_LOSRX    = 8'd147;
localparam [7:0] CMIS_LOLRX    = 8'd148;
localparam [7:0] CMIS_OPT_TX   = 8'd154;
localparam [7:0] CMIS_BIAS_TX  = 8'd170;
localparam [7:0] CMIS_OPT_RX   = 8'd186;
localparam [7:0] CMIS_TH_PAGE  = 8'h02;
localparam [7:0] CMIS_TH_TX_HA = 8'd176;
localparam [7:0] CMIS_TH_TX_LA = 8'd178;
localparam [7:0] CMIS_TH_TX_HW = 8'd180;
localparam [7:0] CMIS_TH_TX_LW = 8'd182;
localparam [7:0] CMIS_TH_BI_HA = 8'd184;
localparam [7:0] CMIS_TH_BI_LA = 8'd186;
localparam [7:0] CMIS_TH_BI_HW = 8'd188;
localparam [7:0] CMIS_TH_BI_LW = 8'd190;
localparam [7:0] CMIS_TH_RX_HA = 8'd192;
localparam [7:0] CMIS_TH_RX_LA = 8'd194;
localparam [7:0] CMIS_TH_RX_HW = 8'd196;
localparam [7:0] CMIS_TH_RX_LW = 8'd198;
// Page 02h thresholds. Nominal cage samples sit inside every window:
// temperature 0x2880 (40.5 C) and supply 0x80E8 (3.3 V), Tx 0x2710 and
// 0x00C8, bias 0x4E20 and 0x2710, Rx 0x1388. Rx 0 is below both Rx low
// thresholds. Temperature thresholds are signed.
localparam [7:0] CMIS_TH_T_HA  = 8'd128;
localparam [7:0] CMIS_TH_T_LA  = 8'd130;
localparam [7:0] CMIS_TH_T_HW  = 8'd132;
localparam [7:0] CMIS_TH_T_LW  = 8'd134;
localparam [7:0] CMIS_TH_V_HA  = 8'd136;
localparam [7:0] CMIS_TH_V_LA  = 8'd138;
localparam [7:0] CMIS_TH_V_HW  = 8'd140;
localparam [7:0] CMIS_TH_V_LW  = 8'd142;
localparam [7:0] CMIS_TH_A1_HA = 8'd144;
localparam [7:0] CMIS_TH_A1_LA = 8'd146;
localparam [7:0] CMIS_TH_A1_HW = 8'd148;
localparam [7:0] CMIS_TH_A1_LW = 8'd150;
localparam [7:0] CMIS_TH_A2_HA = 8'd152;
localparam [7:0] CMIS_TH_A2_LA = 8'd154;
localparam [7:0] CMIS_TH_A2_HW = 8'd156;
localparam [7:0] CMIS_TH_A2_LW = 8'd158;
localparam [7:0] CMIS_TH_A3_HA = 8'd160;
localparam [7:0] CMIS_TH_A3_LA = 8'd162;
localparam [7:0] CMIS_TH_A3_HW = 8'd164;
localparam [7:0] CMIS_TH_A3_LW = 8'd166;
localparam [7:0] CMIS_TH_CU_HA = 8'd168;
localparam [7:0] CMIS_TH_CU_LA = 8'd170;
localparam [7:0] CMIS_TH_CU_HW = 8'd172;
localparam [7:0] CMIS_TH_CU_LW = 8'd174;
localparam signed [15:0] CMIS_TEMP_HA = 16'sh4B00;
localparam signed [15:0] CMIS_TEMP_LA = -16'sd1280;
localparam signed [15:0] CMIS_TEMP_HW = 16'sh4600;
localparam signed [15:0] CMIS_TEMP_LW = 16'sd0;
localparam [15:0] CMIS_VCC_HA  = 16'h8CA0;
localparam [15:0] CMIS_VCC_LA  = 16'h7530;
localparam [15:0] CMIS_VCC_HW  = 16'h875A;
localparam [15:0] CMIS_VCC_LW  = 16'h7A76;
// Aux1 laser temperature, signed 1/256 C: 70 C / 20 C / 65 C / 25 C.
// Aux2 TEC current, signed 100/32767 percent: +80% / -80% / +60% / -60%.
// Nominal samples 50 C (12800) and about +10% (3277) sit inside both windows.
localparam signed [15:0] CMIS_AUX1_HA = 16'sd17920;
localparam signed [15:0] CMIS_AUX1_LA = 16'sd5120;
localparam signed [15:0] CMIS_AUX1_HW = 16'sd16640;
localparam signed [15:0] CMIS_AUX1_LW = 16'sd6400;
localparam signed [15:0] CMIS_AUX2_HA = 16'sd26214;
localparam signed [15:0] CMIS_AUX2_LA = -16'sd26214;
localparam signed [15:0] CMIS_AUX2_HW = 16'sd19660;
localparam signed [15:0] CMIS_AUX2_LW = -16'sd19660;
// Aux3 additional supply, signed 100 uV: 1.980 V / 1.620 V / 1.890 V / 1.710 V.
// Custom laser frequency error, signed 1 MHz: +2000 / -2000 / +1000 / -1000.
// Nominal samples 1.800 V (18000) and +250 MHz sit inside both windows.
localparam signed [15:0] CMIS_AUX3_HA = 16'sd19800;
localparam signed [15:0] CMIS_AUX3_LA = 16'sd16200;
localparam signed [15:0] CMIS_AUX3_HW = 16'sd18900;
localparam signed [15:0] CMIS_AUX3_LW = 16'sd17100;
localparam signed [15:0] CMIS_CUST_HA = 16'sd2000;
localparam signed [15:0] CMIS_CUST_LA = -16'sd2000;
localparam signed [15:0] CMIS_CUST_HW = 16'sd1000;
localparam signed [15:0] CMIS_CUST_LW = -16'sd1000;
localparam [15:0] CMIS_TX_HA   = 16'h4000;
localparam [15:0] CMIS_TX_LA   = 16'h0008;
localparam [15:0] CMIS_TX_HW   = 16'h3000;
localparam [15:0] CMIS_TX_LW   = 16'h0010;
localparam [15:0] CMIS_BI_HA   = 16'h6000;
localparam [15:0] CMIS_BI_LA   = 16'h0800;
localparam [15:0] CMIS_BI_HW   = 16'h5000;
localparam [15:0] CMIS_BI_LW   = 16'h1000;
localparam [15:0] CMIS_RX_HA   = 16'h3000;
localparam [15:0] CMIS_RX_LA   = 16'h0001;
localparam [15:0] CMIS_RX_HW   = 16'h2000;
localparam [15:0] CMIS_RX_LW   = 16'h0010;
localparam [7:0] CMIS_CFGSTAT  = 8'd202;
localparam [7:0] CMIS_ACS0     = 8'd206;
localparam [7:0] CMIS_MSK_FAIL = 8'd214;
localparam [7:0] CMIS_MSK_LOSTX = 8'd215;
localparam [7:0] CMIS_MSK_LOLTX = 8'd216;
localparam [7:0] CMIS_MSK_TX_HA = 8'd218;
localparam [7:0] CMIS_MSK_TX_LA = 8'd219;
localparam [7:0] CMIS_MSK_TX_HW = 8'd220;
localparam [7:0] CMIS_MSK_TX_LW = 8'd221;
localparam [7:0] CMIS_MSK_BI_HA = 8'd222;
localparam [7:0] CMIS_MSK_BI_LA = 8'd223;
localparam [7:0] CMIS_MSK_BI_HW = 8'd224;
localparam [7:0] CMIS_MSK_BI_LW = 8'd225;
localparam [7:0] CMIS_MSK_LOSRX = 8'd226;
localparam [7:0] CMIS_MSK_LOLRX = 8'd227;
localparam [7:0] CMIS_MSK_RX_HA = 8'd228;
localparam [7:0] CMIS_MSK_RX_LA = 8'd229;
localparam [7:0] CMIS_MSK_RX_HW = 8'd230;
localparam [7:0] CMIS_MSK_RX_LW = 8'd231;
localparam [7:0] CMIS_DPPEND   = 8'd235;
localparam [7:0] CMIS_APP_BASE = 8'd86;
localparam [5:0] CMIS_POLL_N   = 6'd18;
// SFF-8024 host electrical IDs and single-mode media IDs.
localparam [7:0] CMIS_H_128    = 8'h4A;
localparam [7:0] CMIS_H_64     = 8'h29;
localparam [7:0] CMIS_H_32     = 8'h28;
localparam [7:0] CMIS_M_128    = 8'h45;
localparam [7:0] CMIS_M_64     = 8'h23;
localparam [7:0] CMIS_M_32     = 8'h22;
localparam [7:0] CMIS_LANES11  = 8'h11;
localparam [7:0] CMIS_LANE1    = 8'h01;
// AppSel 1, DataPathID 0 (lane 1), module signal-integrity defaults.
localparam [7:0] CMIS_APP_128  = 8'h10;
// CMIS 5.0 data path state encodings.
localparam [3:0] CMIS_DP_DEACT  = 4'h1;
localparam [3:0] CMIS_DP_INIT   = 4'h2;
localparam [3:0] CMIS_DP_DEINIT = 4'h3;
localparam [3:0] CMIS_DP_ACT    = 4'h4;
localparam [3:0] CMIS_DP_TXON   = 4'h5;
localparam [3:0] CMIS_DP_TXOFF  = 4'h6;
localparam [3:0] CMIS_DP_INITD  = 4'h7;
// ConfigStatus encodings, page 11h byte 202 bits [3:0].
localparam [3:0] CMIS_CFG_NONE = 4'h0;
localparam [3:0] CMIS_CFG_OK   = 4'h1;
localparam [3:0] CMIS_CFG_REJ  = 4'h2;
localparam [3:0] CMIS_CFG_APP  = 4'h3;
localparam [3:0] CMIS_CFG_DP   = 4'h4;
localparam [3:0] CMIS_CFG_BUSY = 4'hC;
