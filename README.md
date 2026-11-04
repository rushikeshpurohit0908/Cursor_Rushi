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

The pipeline on each port is block lock, a self-synchronizing x^58+x^39+1 scrambler, store-and-forward FC frames with CRC-32, buffer-to-buffer credit and R_RDY, and an RS(255,239) FEC engine over GF(2^8). Ordered-set bytes are an internal coding so the bridge can be simulated; they are not a bit-exact FC-FS map. Production FC-PI-8 FEC is an RS(544,514)-class code. `fc_rs_fec` is the block that code replaces. `scripts/gen_fc_rs_tables.py` is the reference codec and regenerates `rtl/fc128/fc_rs_tables.vh`.

Run the self-checking simulations with Icarus Verilog:

```bash
bash sim/run_fc128.sh
```

The top-level CSR (client clock, word addresses) is:

| Offset | Register |
|---|---|
| `0x000` | ID `0xFC128039` |
| `0x008` | Control: reset, system loopback, FEC, scrambler, secondary protect |
| `0x00C` | Client block-lock bits |
| `0x010` | Port enable |
| `0x018` | Load credits `{client[15:8], system[7:0]}` |
| `0x100 + 32*port` | Frame, CRC, and FEC counters |
