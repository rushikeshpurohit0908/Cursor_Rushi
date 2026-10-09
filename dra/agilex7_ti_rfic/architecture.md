# Agilex 7 + TI AFE7950 DRA Architecture

Discrete RFIC + FPGA option for the Ku-band Direct Radiating Array payload.

## Device map

| Role | Devices | Channels |
|---|---|---|
| RX RFIC | 8 × TI AFE7950 | 4 RX ADC × 8 = **32 RX** |
| RX FPGA | 4 × Altera Agilex 7 | 8 beams / FPGA |
| TX RFIC | 10 × TI AFE7950 | 4 TX DAC × 10 = **40 TX** |
| TX FPGA | 5 × Altera Agilex 7 | 8 beams / FPGA |
| Clock / LO | LMX2615-SP or LMX2820 | Shared SYSREF + LO |

**Per slot:** 1 × Agilex 7 + 2 × AFE7950 (8 RF channels) over JESD204C Subclass-1.

## RF plan

### RX uplink — 14.0–14.5 GHz (32 beams)
AFE7950 RF input tops out near 12 GHz, so Ku uplink uses a **super-heterodyne** stage:

`Antenna → LNA → Ku→IF mixer (LO from LMX) → IF (~8 GHz class) → AFE7950 RX ADC + DDC → JESD204C → Agilex 7`

In Agilex 7: digital beamforming (4-color, 8-way spatial reuse) → UL channelizer (4 × 125 MHz/beam) → DVB-RCS2 / 3GPP-NTN Low-PHY → router fabric.

### TX downlink — 10.7–12.75 GHz (40 NTN / 32 DVB-S2X)
Much of the Ku downlink sits inside the AFE7950 TX RF range (to 12 GHz):

`Router → Agilex 7 Low-PHY framer + DBFN (4-color, 8–10 way) → JESD204C → AFE7950 DUC + 12 GSPS DAC → [optional IF→Ku for 12.0–12.75] → HPA → Antenna`

DVB-S2X-only mode parks spare TX channels on the FPGA-5 / AFE pair (beams 33–40 idle).

## Why this split

- **Standard ecosystem:** JESD204B/C to Agilex 7 F-tile / E-tile SerDes.
- **RF flexibility:** Swap AFE7950 ↔ AFE7950-SP; retune LO for band variants.
- **Isolation:** Physically separate RX and TX FPGA+RFIC clusters (9 FPGAs + 18 AFEs).
- **Trade vs Direct-RF SoC:** more BOM devices and board area; cleaner RFIC/FPGA role split and multi-vendor sourcing.

## Related files

- `block_diagram.svg` / `.png` / `.html` — visual architecture
- `Agilex7_TI_AFE7950_DRA.pptx` — slide deck
- `Speaker_Notes.md` — presenter notes
- `../` — prior Direct-RF AGRW027/039 SoC option for comparison
