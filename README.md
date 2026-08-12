# Cursor_Rushi — DRDO AI Proposal

Technical proposal materials for a **DRDO AI Compute Platform** covering:

- **Training hardware** (secure GPU clusters)
- **Software stack** (PyTorch → OpenVINO → FPGA AI Suite → Quartus)
- **Inference on Altera® Agilex™ FPGAs** (edge, hostless, PCIe)

## Documents

| File | Description |
|---|---|
| [`proposal/DRDO_AI_Proposal.md`](proposal/DRDO_AI_Proposal.md) | Full technical & commercial narrative |
| [`proposal/DRDO_AI_Proposal.html`](proposal/DRDO_AI_Proposal.html) | Presentation-ready HTML (print to PDF) |
| [`proposal/BOM_Reference.md`](proposal/BOM_Reference.md) | Reference bill of materials |

## Quick positioning

**Train** on air-gapped GPUs → **optimize** with OpenVINO → **deploy inference** on Altera Agilex 3/5/7 with FPGA AI Suite for deterministic, SWaP-efficient defence workloads (ISR, EW, autonomy, C2).
