# RX / TX DRA Architecture — Speaker Notes

## Slide 1 — Title
Introduce the Ku-band DRA payload: separate RX and TX AGRW027/039 clusters, Direct-RF 64 Gsps, digital beamforming, and a 58 Gbps SerDes fabric.

## Slide 2 — System Overview
Walk the three-box story: RX uplink (32 beams / 4 devices), TX downlink (40/32 beams / 5 devices), and the router that bridges them to the feeder link.

## Slide 3 — Block Diagram
Use the full diagram to show antenna → LNA → RX cluster → DSP → router → TX DSP → DAC cluster → HPA → antenna. Call out Device 5 spare channels in DVB-S2X-only mode.

## Slide 4 — RX Cluster
Emphasize 8 ADC channels per device mapping to 8 beams, and the ADC → DDC → DBFN → channelizer → Low-PHY chain.

## Slide 5 — TX Cluster
Mirror the RX story with DAC channels. Note NTN uses 40 beams; DVB-S2X-only parks 4 idle DACs on Device 5.

## Slide 6 — DSP Detail
Compare uplink vs downlink beamforming reuse (4-color both sides; 8-way UL vs 8–10 way DL) and the 4 × 125 MHz / beam UL channelizer.

## Slide 7 — Isolation & Control
Justify the 9-device separate-silicon choice (cleanest TX→RX isolation), Arm A53 HPS control plane, and multi-device phase-sync for coherent arrays.

## Slide 8 — Spec Table
Quick reference for band, beams, devices, converters, sample rate, reuse, and air interfaces.

## Slide 9 — Summary
Close on the nine-device conservative architecture: separated paths, Direct-RF converters, DBFN, and coherent phase sync.
