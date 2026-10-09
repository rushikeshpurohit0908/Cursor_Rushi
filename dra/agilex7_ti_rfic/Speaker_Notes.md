# Agilex 7 + TI AFE7950 — Speaker Notes

## Slide 1 — Title
Position this as the discrete RFIC + FPGA alternative to the Direct-RF SoC DRA option. Same beam counts and air interfaces; different silicon split.

## Slide 2 — System Overview
Three roles: AFE7950 converts RF↔digital, Agilex 7 runs beamforming/PHY, slot model ties them (1 FPGA + 2 AFEs = 8 channels).

## Slide 3 — Block Diagram
Walk Antenna → LNA → mixer → AFE → JESD → Agilex → router → Agilex → JESD → AFE → HPA → Antenna. Call out separate RX/TX clusters.

## Slide 4 — RX
Explain why Ku uplink needs super-het (AFE RF ceiling ~12 GHz). Mixer + LMX LO feeds AFE RX; FPGA does DBFN/channelizer/Low-PHY.

## Slide 5 — TX
Most of 10.7–12.75 GHz can be direct RF DAC; optional IF→Ku only for the upper edge. FPGA 5 / spare AFEs idle in DVB-S2X-only mode.

## Slide 6 — Interconnect
JESD204C Subclass-1 + shared SYSREF/LO for coherent multi-device beamforming. Router fabric bridges clusters and feeder link.

## Slide 7 — Comparison
Trade density (Direct-RF SoC) vs flexibility / multi-vendor / space-grade RFIC path (this option).

## Slide 8 — BOM
9 Agilex 7 + 18 AFE7950 as the conservative isolated TX/RX build. Mention AFE7950-SP for space.

## Slide 9 — Summary
Close on the slot model and Ku band plan (super-het RX, RF-DAC TX).
