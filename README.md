# Cursor_Rushi

## Cisco FC128 Proposal (Agilex 7 M039 R47)

Technical proposal for Cisco **128G Fibre Channel** on **Altera Agilex™ 7 M-Series AGM039 (R47)**.

| Artifact | Path |
|---|---|
| Full proposal | [`proposal/cisco_fc128/Cisco_FC128_Proposal.md`](proposal/cisco_fc128/Cisco_FC128_Proposal.md) |
| Executive brief | [`proposal/cisco_fc128/Executive_Brief.md`](proposal/cisco_fc128/Executive_Brief.md) |
| Architecture diagram | [`proposal/cisco_fc128/architecture.svg`](proposal/cisco_fc128/architecture.svg) |
| Slide deck | [`presentations/Cisco_FC128_Agilex7_Proposal.pptx`](presentations/Cisco_FC128_Agilex7_Proposal.pptx) |
| Deck builder | [`scripts/build_cisco_fc128_proposal.py`](scripts/build_cisco_fc128_proposal.py) |
| Soft datapath RTL | [`rtl/fc128/fc128_bridge_top.sv`](rtl/fc128/fc128_bridge_top.sv) |
| Simulation | [`sim/run_fc128.sh`](sim/run_fc128.sh) |

### I/O plan

- **Client:** 8 × 112G PAM4 (128GFC)
- **System:** 16 × 58G PAM4
- **Secondary:** 8 × 58G
- **Device:** Agilex 7 M 039 · R47

### Rebuild deck

```bash
pip install -r requirements.txt
python3 scripts/build_cisco_fc128_proposal.py
```

## FC128 soft datapath

`rtl/fc128/` is the synthesizable bridge behind the proposal diagram. Hardened F-Tile PMA stays outside the RTL. Each client port is one 112.2G lane gearboxed onto two 58G system lanes (116G aggregate, about 3.3% above the line rate). The per-port line rate selects 128GFC (both lanes), 64GFC (lane 0 only), or 32GFC (lane 0 with one IDLE inserted after every block and removed on the return path). Writing a new rate while the link is Active holds the link down, resets the shaper and the lane FIFOs onto that rate, and brings the link back. Bit 4 of the rate register stays set until the new rate is in use. The extra 8×58G bank mirrors the even lane of each pair in protect mode, or squelches.

The pipeline on each port is block lock, a self-synchronizing x^58+x^39+1 scrambler, link initialization, store-and-forward FC frames with CRC-32, buffer-to-buffer credit and R_RDY, and an RS(255,239) FEC engine over GF(2^8). A control block carries the FC-FS ordered set in bits `[31:0]` (first character in `[7:0]`): Idle is `BC 95 B5 B5`, R_RDY is `BC 95 4A 4A`, and NOS / OLS / LR / LRR use their FC-FS sequences. Frames are transmitted as SOFi3 … EOFt. The receiver accepts the SOF family and both running-disparity forms of EOFt, EOFn, and EOFdt. EOFa and the invalid EOF delimiters discard the frame. The pipe's container is still this 66-bit block. Control bit 5 packs four of those blocks into one Clause 119 256b/257b word on the system gearbox; the omitted nibble of a K28.5 ordered set is restored as `0xBC`. Link bring-up transmits NOS until block lock, then OLS, LR, LRR, and Idle. Active is that handshake, or a run of Idle from a peer that is already up. One NOS drops the link. `scripts/gen_fc_rs_tables.py` regenerates `rtl/fc128/fc_rs_tables.vh`. FC-PI-8 RS(544,514) over GF(2^10), roots alpha^0 through alpha^29, is `fc_rs544` (`scripts/gen_fc_rs544_tables.py`). A full codeword is 544 ten-bit symbols, so the 256-byte frame buffer still uses the shorter code. Control bit 6, together with the transcode, runs that code on the packed stream: twenty 257-bit words are the message, and the thirty parity symbols leave as five beats with sync `11`. The receiver locks onto that trailer, corrects the symbols, and strips the parity before the 66-bit blocks are restored. System-lane block lock crosses into the client clock through a two-flop synchronizer before it gates the return path. Each client cage has a CMIS 5.0 two-wire host at 7-bit address `0x50`. It publishes the SFF-8024 identifier, module state, flags, temperature, and supply from lower bytes 0–17, and it writes LowPwrRequestSW, SoftwareReset, lane-1 OutputDisableTx, and OutputSquelchForceTx. Lower bytes 86–97 advertise one-lane 128GFC-SM, 64GFC-SM, and 32GFC-SM. Control bit 6 is DPDeinit for lane 1. While that bit is clear and the module is ModuleReady, the lane steps to DPActivated unless OutputDisableTx or OutputSquelchForceTx is set. Page 11h bytes 135, 136, 137, 147, and 148 latch lane-1 FailureFlagTx, LOSFlagTx, CDRLOLFlagTx, LOSFlagRx, and CDRLOLFlagRx. A read clears the latch, and the flag sets again while the condition is still present. Bits [13:9] of the cage control register are the matching mask bits (1 masks the flag). An unmasked flag clears lower byte 3 bit 0 and pulls IntL low. The host publishes the five flags in `0x214 + 32*port` bits [15:11]. Page 11h lane status is reported at that same register. Page 11h bytes 154-155, 170-171, and 186-187 are lane-1 OpticalPowerTx, LaserBiasTx, and OpticalPowerRx. `0x300 + 32*port` is `{Rx power[15:0], Tx power[15:0]}` and `0x304 + 32*port` is the bias. Power counts 0.1 µW and bias counts 2 µA. A read leaves those monitors unchanged. `0x21C + 32*port` writes the staged AppSel byte (page 10h byte 145). Bit 7 of the control register pulses ApplyDPInit, which copies that byte into the active set when AppSel is 1–3 and DataPathID is lane 1, or reports ConfigRejectedInvalidAppSel / ConfigRejectedInvalidDataPath. An accepted apply on a live lane cycles through DPDeactivated before the link returns. LPMode and ResetL are cage pins. `0x218 + 32*port` selects that port's line rate, and bit 4 of that register stays set until the link is back on the new rate.

Run the self-checking simulations with Icarus Verilog:

```bash
bash sim/run_fc128.sh
```

The top-level CSR (client clock, word addresses) is:

| Offset | Register |
|---|---|
| `0x000` | ID `0xFC128039` |
| `0x008` | Control: reset, system loopback, FEC, scrambler, secondary protect, 256b/257b transcode, RS(544,514) |
| `0x00C` | Client block-lock bits |
| `0x010` | Port enable |
| `0x018` | Load credits `{client[15:8], system[7:0]}` |
| `0x01C` | Client link-up bits |
| `0x020` | System link-up bits |
| `0x028` | System block-lock bits, synced onto the client clock |
| `0x100 + 32*port` | Frame, CRC, and FEC counters |
| `0x118 + 32*port` | Link state `{system_ls[2:0], client_ls[2:0], system_up, client_up}` |
| `0x11C + 32*port` | RS(544,514) `{uncorrectable codewords[15:0], corrected symbols[15:0]}` |
| `0x200 + 32*port` | CMIS control: poll, LowPwrRequestSW, SoftwareReset pulse, OutputDisableTx1, LPMode, ResetL deasserted, DPDeinit, ApplyDPInit pulse, OutputSquelchForceTx, lane-flag masks `[13:9]` (1 = masked) |
| `0x204 + 32*port` | CMIS status: identifier, revision, module state, present, monitors valid |
| `0x208 + 32*port` | CMIS `{VccMonVoltage[15:0], TempMonValue[15:0]}` |
| `0x20C + 32*port` | CMIS module flags, bytes 11..8 |
| `0x210 + 32*port` | CMIS readback: LowPwrRequestSW, OutputDisableTx, armed, OutputSquelchForceTx |
| `0x214 + 32*port` | Lane 1: DPState `[3:0]`, DPDeinit, DPActivated, OutputStatusRx, OutputStatusTx, DPStateChangedFlag, DPInitPending, valid, FailureFlagTx, LOSFlagTx, CDRLOLFlagTx, LOSFlagRx, CDRLOLFlagRx `[15:11]` |
| `0x218 + 32*port` | Line rate `[1:0]`: `0` 128GFC, `1` 64GFC, `2` 32GFC. Bit 4 is set while the new rate is applied |
| `0x21C + 32*port` | Staged AppSel `[7:0]`, active AppSel `[15:8]`, ConfigStatus `[19:16]` |
| `0x300 + 32*port` | Lane 1 `{OpticalPowerRx[15:0], OpticalPowerTx[15:0]}`, 0.1 µW |
| `0x304 + 32*port` | Lane 1 LaserBiasTx `[15:0]`, 2 µA |
