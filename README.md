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

The pipeline on each port is block lock, a self-synchronizing x^58+x^39+1 scrambler, link initialization, store-and-forward FC frames with CRC-32, buffer-to-buffer credit and R_RDY, and an RS(255,239) FEC engine over GF(2^8). A control block carries the FC-FS ordered set in bits `[31:0]` (first character in `[7:0]`): Idle is `BC 95 B5 B5`, R_RDY is `BC 95 4A 4A`, and NOS / OLS / LR / LRR use their FC-FS sequences. Frames are transmitted as SOFi3 … EOFt. The receiver accepts the SOF family and both running-disparity forms of EOFt, EOFn, and EOFdt. EOFa and the invalid EOF delimiters discard the frame. The pipe's container is still this 66-bit block. Control bit 5 packs four of those blocks into one Clause 119 256b/257b word on the system gearbox; the omitted nibble of a K28.5 ordered set is restored as `0xBC`. Link bring-up transmits NOS until block lock, then OLS, LR, LRR, and Idle. Active is that handshake, or a run of Idle from a peer that is already up. One NOS drops the link. `scripts/gen_fc_rs_tables.py` regenerates `rtl/fc128/fc_rs_tables.vh`. FC-PI-8 RS(544,514) over GF(2^10), roots alpha^0 through alpha^29, is `fc_rs544` (`scripts/gen_fc_rs544_tables.py`). A full codeword is 544 ten-bit symbols, so the 256-byte frame buffer still uses the shorter code. Control bit 6, together with the transcode, runs that code on the packed stream: twenty 257-bit words are the message, and the thirty parity symbols leave as five beats with sync `11`. The receiver locks onto that trailer, corrects the symbols, and strips the parity before the 66-bit blocks are restored. System-lane block lock crosses into the client clock through a two-flop synchronizer before it gates the return path. Each client cage has a CMIS 5.0 two-wire host at 7-bit address `0x50`. It publishes the SFF-8024 identifier, module state, flags, temperature, and supply from lower bytes 0–17, and it writes LowPwrRequestSW, SoftwareReset, lane-1 OutputDisableTx, and OutputSquelchForceTx. Lower bytes 86–97 advertise one-lane 128GFC-SM, 64GFC-SM, and 32GFC-SM. Control bit 6 is DPDeinit for lane 1. While that bit is clear and the module is ModuleReady, the lane steps to DPActivated unless OutputDisableTx or OutputSquelchForceTx is set. Page 11h bytes 135, 136, 137, 147, and 148 latch lane-1 FailureFlagTx, LOSFlagTx, CDRLOLFlagTx, LOSFlagRx, and CDRLOLFlagRx. A read clears the latch, and the flag sets again while the condition is still present. Bits [13:9] of the cage control register are the matching mask bits (1 masks the flag). An unmasked flag clears lower byte 3 bit 0 and pulls IntL low. The host publishes the five flags in `0x214 + 32*port` bits [15:11]. Page 11h lane status is reported at that same register. Page 11h bytes 154-155, 170-171, and 186-187 are lane-1 OpticalPowerTx, LaserBiasTx, and OpticalPowerRx. `0x300 + 32*port` is `{Rx power[15:0], Tx power[15:0]}` and `0x304 + 32*port` is the bias. Power counts 0.1 µW and bias counts 2 µA. A read leaves those monitors unchanged. Page 11h bytes 139-146 and 149-152 are the lane-1 high/low alarm and warning flags for Tx power, laser bias, and Rx power. The module sets a high flag when the monitor is greater than the page 02h threshold and a low flag when it is less. `0x308 + 32*port` reports the twelve flags. `0x30C + 32*port` is the mask, reset to `12'hFFF`, and a 1 keeps that flag off IntL. Lower byte 9 is the module temperature and supply flags: temperature high alarm, low alarm, high warning, and low warning in bits [7:4], and the same four for supply voltage in bits [3:0]. Temperature is a signed compare in units of 1/256 °C. Those bits are published in `0x20C + 32*port` bits [15:8]. `0x310 + 32*port` is the byte-32 mask, reset to `8'hFF`, and a 1 keeps that flag off IntL. A read of byte 9 clears a flag whose comparison is no longer true. Lower byte 8 bit 0 is ModuleStateChangedFlag, published in `0x20C + 32*port` bit 0. The module sets it on entry to ModuleLowPwr, ModuleReady, or ModuleFault, and skips it when that state is left immediately. ModulePwrUp and ModulePwrDn do not set it. A read clears it, and it stays clear until the next qualifying state entry. `0x314 + 32*port` bit 0 is the byte-31 mask, reset to 1. Lower byte 10 is the Aux1 and Aux2 alarm/warning flags: laser-temperature high alarm, low alarm, high warning, and low warning in bits [7:4], and the same four for TEC current in bits [3:0]. Aux1 is signed 1/256 °C at bytes 18-19. Aux2 is signed TEC current, in units of 100/32767 percent, at bytes 20-21. Those flags are published in `0x20C + 32*port` bits [23:16]. `0x318 + 32*port` is the byte-33 mask, reset to `8'hFF`, and a 1 keeps that flag off IntL. A read of byte 10 clears a flag whose comparison is no longer true. `0x31C + 32*port` is `{Aux2[15:0], Aux1[15:0]}`. A negative TEC current does not set a high alarm. Nominal samples are 50 °C and about +10 percent. Lower byte 11 is the Aux3 and Custom alarm/warning flags: Vcc2 high alarm, low alarm, high warning, and low warning in bits [7:4], and the same four for laser frequency error in bits [3:0]. Aux3 is signed additional supply, in units of 100 µV, at bytes 22-23. Custom is signed laser frequency error, in units of 1 MHz, at bytes 24-25. Those flags are published in `0x20C + 32*port` bits [31:24]. `0x400 + 32*port` is the byte-34 mask, reset to `8'hFF`, and a 1 keeps that flag off IntL. A read of byte 11 clears a flag whose comparison is no longer true. `0x404 + 32*port` is `{Custom[15:0], Aux3[15:0]}`. A negative Vcc2 or frequency reading does not set a high alarm. Nominal samples are 1.800 V and +250 MHz. `0x21C + 32*port` writes the staged AppSel byte (page 10h byte 145). Bit 7 of the control register pulses ApplyDPInit, which copies that byte into the active set when AppSel is 1–3 and DataPathID is lane 1, or reports ConfigRejectedInvalidAppSel / ConfigRejectedInvalidDataPath. An accepted apply on a live lane cycles through DPDeactivated before the link returns. LPMode and ResetL are cage pins. `0x218 + 32*port` selects that port's line rate, and bit 4 of that register stays set until the link is back on the new rate.

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
| `0x20C + 32*port` | CMIS module flags, bytes 11..8. Byte 8 bit 0 (bit 0) is ModuleStateChangedFlag. Byte 9 (bits [15:8]) is temperature and Vcc alarm/warning flags. Byte 10 (bits [23:16]) is Aux1/Aux2 alarm/warning flags. Byte 11 (bits [31:24]) is Aux3/Custom alarm/warning flags |
| `0x210 + 32*port` | CMIS readback: LowPwrRequestSW, OutputDisableTx, armed, OutputSquelchForceTx |
| `0x214 + 32*port` | Lane 1: DPState `[3:0]`, DPDeinit, DPActivated, OutputStatusRx, OutputStatusTx, DPStateChangedFlag, DPInitPending, valid, FailureFlagTx, LOSFlagTx, CDRLOLFlagTx, LOSFlagRx, CDRLOLFlagRx `[15:11]` |
| `0x218 + 32*port` | Line rate `[1:0]`: `0` 128GFC, `1` 64GFC, `2` 32GFC. Bit 4 is set while the new rate is applied |
| `0x21C + 32*port` | Staged AppSel `[7:0]`, active AppSel `[15:8]`, ConfigStatus `[19:16]` |
| `0x300 + 32*port` | Lane 1 `{OpticalPowerRx[15:0], OpticalPowerTx[15:0]}`, 0.1 µW |
| `0x304 + 32*port` | Lane 1 LaserBiasTx `[15:0]`, 2 µA |
| `0x308 + 32*port` | Lane 1 alarm/warning flags `[11:0]`: Tx power HA/LA/HW/LW, bias HA/LA/HW/LW, Rx power HA/LA/HW/LW |
| `0x30C + 32*port` | Lane 1 alarm masks `[11:0]`, same order (1 = masked, reset `12'hFFF`) |
| `0x310 + 32*port` | Module temperature and Vcc alarm masks `[7:0]`, same order as byte 9 (1 = masked, reset `8'hFF`) |
| `0x314 + 32*port` | ModuleStateChangedMask (byte 31 bit 0). 1 = masked, reset 1 |
| `0x318 + 32*port` | Aux1/Aux2 alarm masks `[7:0]`, same order as byte 10 (1 = masked, reset `8'hFF`) |
| `0x31C + 32*port` | `{Aux2[15:0], Aux1[15:0]}`. Aux1 is laser temperature in 1/256 °C. Aux2 is TEC current in units of 100/32767 percent |
| `0x400 + 32*port` | Aux3/Custom alarm masks `[7:0]`, same order as byte 11 (1 = masked, reset `8'hFF`) |
| `0x404 + 32*port` | `{Custom[15:0], Aux3[15:0]}`. Aux3 is Vcc2 in 100 µV. Custom is laser frequency error in MHz |
| `0x500 + 32*port` | VendorName bytes 128-131. Byte 128 is the MSB |
| `0x504 + 32*port` | VendorName bytes 132-135 |
| `0x508 + 32*port` | VendorName bytes 136-139 |
| `0x50C + 32*port` | VendorName bytes 140-143 |
| `0x510 + 32*port` | VendorPN bytes 148-151. Byte 148 is the MSB |
| `0x514 + 32*port` | VendorPN bytes 152-155 |
| `0x518 + 32*port` | VendorPN bytes 156-159 |
| `0x51C + 32*port` | VendorPN bytes 160-163 |
