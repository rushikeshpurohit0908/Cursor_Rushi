# Cursor_Rushi

## RX / TX DRA Architectures

Two Ku-band Direct Radiating Array options for the same 32-beam uplink / 40-beam downlink payload map.

### Option A — Direct-RF SoC (AGRW027/039)

| File | Description |
|---|---|
| [`dra/block_diagram.html`](dra/block_diagram.html) | Interactive block-diagram viewer |
| [`dra/block_diagram.svg`](dra/block_diagram.svg) | Vector block diagram |
| [`dra/block_diagram.png`](dra/block_diagram.png) | Raster export (2400 px wide) |
| [`dra/DRA_Uplink_Downlink.pptx`](dra/DRA_Uplink_Downlink.pptx) | PowerPoint deck (9 slides, 16:9) |
| [`dra/Speaker_Notes.md`](dra/Speaker_Notes.md) | Speaker notes |
| [`dra/build_dra_pptx.py`](dra/build_dra_pptx.py) | PPTX generator |

- **RX:** 14.0–14.5 GHz, 32 beams, 4× devices (8 ADC ch)
- **TX:** 10.7–12.75 GHz, 40/32 beams, 5× devices (8 DAC ch)
- **Isolation:** 9 Direct-RF devices on separate TX/RX paths

### Option B — Agilex 7 FPGA + TI AFE7950 RFIC

| File | Description |
|---|---|
| [`dra/agilex7_ti_rfic/architecture.md`](dra/agilex7_ti_rfic/architecture.md) | Architecture narrative |
| [`dra/agilex7_ti_rfic/block_diagram.html`](dra/agilex7_ti_rfic/block_diagram.html) | Interactive viewer |
| [`dra/agilex7_ti_rfic/block_diagram.svg`](dra/agilex7_ti_rfic/block_diagram.svg) | Vector block diagram |
| [`dra/agilex7_ti_rfic/block_diagram.png`](dra/agilex7_ti_rfic/block_diagram.png) | Raster export |
| [`dra/agilex7_ti_rfic/Agilex7_TI_AFE7950_DRA.pptx`](dra/agilex7_ti_rfic/Agilex7_TI_AFE7950_DRA.pptx) | PowerPoint deck (9 slides, 16:9) |
| [`dra/agilex7_ti_rfic/Speaker_Notes.md`](dra/agilex7_ti_rfic/Speaker_Notes.md) | Speaker notes |
| [`dra/agilex7_ti_rfic/build_pptx.py`](dra/agilex7_ti_rfic/build_pptx.py) | PPTX generator |

- **Slot model:** 1× Agilex 7 + 2× AFE7950 = 8 RF channels over JESD204C
- **RX:** 8× AFE7950 + 4× Agilex 7 (Ku→IF super-het into AFE)
- **TX:** 10× AFE7950 + 5× Agilex 7 (RF DAC; optional IF→Ku for upper band edge)
- **Space path:** AFE7950-SP + LMX2615-SP synthesizers
