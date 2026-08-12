# DRDO AI Compute Platform — Executive Brief

**One page · Altera FPGA inference + sovereign training**

## Offer

An end-to-end AI platform for DRDO: **secure GPU training** in-facility, and **field inference on Altera Agilex™ FPGAs** using FPGA AI Suite and OpenVINO™.

## Why it matters

| Need | Answer |
|---|---|
| Classified training data | Air-gapped GPU cluster + MLOps |
| Edge SWaP & latency | Agilex 3/5/7 FPGA inference |
| Model portability | PyTorch → OpenVINO IR → FPGA AI Suite |
| Program longevity | Long-lifecycle FPGA silicon & tools |
| Indian ecosystem | Design-in with SI / DPSU partners |

## Hardware at a glance

- **Training:** Multi-node GPU servers, IB/RoCE, encrypted storage, no public cloud dependency  
- **Inference:** Agilex SoC modules (UAV/UGV), hostless payloads (EW/munitions), PCIe/SmartNIC cards (C2/radar)

## Software path

`Train → ONNX → OpenVINO → dla_compiler → Quartus bitstream → OpenVINO FPGA / HETERO runtime`

## Suggested start

1. 2-day architecture workshop with nominated labs  
2. PoC: two models on Agilex evaluation kits (8–12 weeks)  
3. Pilot: rugged module + training slice  

**Documents:** `DRDO_AI_Proposal.md` (full) · `DRDO_AI_Proposal.html` (present) · `BOM_Reference.md` (BOM)
