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

`rtl/fc128/` is the synthesizable bridge behind the proposal diagram. Hardened F-Tile PMA stays outside the RTL. Each client port is one 112.2G lane gearboxed onto two 58G system lanes (116G aggregate, about 3.3% above the line rate). The extra 8×58G bank mirrors the even lane of each pair in protect mode, or squelches.

The pipeline on each port is block lock, a self-synchronizing x^58+x^39+1 scrambler, link initialization, store-and-forward FC frames with CRC-32, buffer-to-buffer credit and R_RDY, and an RS(255,239) FEC engine over GF(2^8). A control block carries the FC-FS ordered set in bits `[31:0]` (first character in `[7:0]`): Idle is `BC 95 B5 B5`, R_RDY is `BC 95 4A 4A`, and NOS / OLS / LR / LRR use their FC-FS sequences. Frames are transmitted as SOFi3 … EOFt. The receiver accepts the SOF family and both running-disparity forms of EOFt, EOFn, and EOFdt. EOFa and the invalid EOF delimiters discard the frame. The pipe's container is still this 66-bit block. Control bit 5 packs four of those blocks into one Clause 119 256b/257b word on the system gearbox; the omitted nibble of a K28.5 ordered set is restored as `0xBC`. Link bring-up transmits NOS until block lock, then OLS, LR, LRR, and Idle. Active is that handshake, or a run of Idle from a peer that is already up. One NOS drops the link. Production FC-PI-8 FEC is an RS(544,514)-class code. `fc_rs_fec` is the block that code replaces. `scripts/gen_fc_rs_tables.py` is the reference codec and regenerates `rtl/fc128/fc_rs_tables.vh`. System-lane block lock crosses into the client clock through a two-flop synchronizer before it gates the return path.

Run the self-checking simulations with Icarus Verilog:

```bash
bash sim/run_fc128.sh
```

The top-level CSR (client clock, word addresses) is:

| Offset | Register |
|---|---|
| `0x000` | ID `0xFC128039` |
| `0x008` | Control: reset, system loopback, FEC, scrambler, secondary protect, 256b/257b transcode |
| `0x00C` | Client block-lock bits |
| `0x010` | Port enable |
| `0x018` | Load credits `{client[15:8], system[7:0]}` |
| `0x01C` | Client link-up bits |
| `0x020` | System link-up bits |
| `0x028` | System block-lock bits, synced onto the client clock |
| `0x100 + 32*port` | Frame, CRC, and FEC counters |
| `0x118 + 32*port` | Link state `{system_ls[2:0], client_ls[2:0], system_up, client_up}` |
