# Cursor_Rushi

## RX / TX DRA Architecture

Ku-band Direct Radiating Array payload architecture (AGRW027/039 device clusters).

| File | Description |
|---|---|
| [`dra/block_diagram.html`](dra/block_diagram.html) | Interactive block-diagram viewer |
| [`dra/block_diagram.svg`](dra/block_diagram.svg) | Vector block diagram |
| [`dra/block_diagram.png`](dra/block_diagram.png) | Raster export (2400 px wide) |
| [`dra/DRA_Uplink_Downlink.pptx`](dra/DRA_Uplink_Downlink.pptx) | PowerPoint deck (9 slides, 16:9) |
| [`dra/build_dra_pptx.py`](dra/build_dra_pptx.py) | PPTX generator script |

### Architecture at a glance

- **RX uplink:** 14.0–14.5 GHz, 32 spot beams, 4× devices (8 ADC ch each)
- **TX downlink:** 10.7–12.75 GHz, 40 beams (NTN) / 32 (DVB-S2X), 5× devices (8 DAC ch each)
- **Fabric:** 58 Gbps SerDes onboard router between clusters
- **Isolation:** physically separate TX/RX silicon paths (9 devices total)
