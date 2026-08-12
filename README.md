# Cursor_Rushi — DRDO AI Proposal

Technical proposal materials for a **DRDO AI Compute Platform** covering:

- **Training hardware** (secure GPU clusters)
- **Software stack** (PyTorch → OpenVINO → FPGA AI Suite → Quartus)
- **Inference on Altera® Agilex™ FPGAs** (edge, hostless, PCIe)

## Documents

| File | Description |
|---|---|
| [`proposal/LRDE_AI_Slide_Deck.html`](proposal/LRDE_AI_Slide_Deck.html) | **LRDE slide deck** (16 slides, keyboard nav) |
| [`proposal/LRDE_Slide_Speaker_Notes.md`](proposal/LRDE_Slide_Speaker_Notes.md) | Speaker notes for the LRDE deck |
| [`proposal/DRDO_AI_Proposal.md`](proposal/DRDO_AI_Proposal.md) | Full technical & commercial narrative |
| [`proposal/DRDO_AI_Proposal.html`](proposal/DRDO_AI_Proposal.html) | Long-form HTML proposal |
| [`proposal/Executive_Brief.md`](proposal/Executive_Brief.md) | One-page executive summary |
| [`proposal/BOM_Reference.md`](proposal/BOM_Reference.md) | Reference bill of materials |

## LRDE slide deck

Open `proposal/LRDE_AI_Slide_Deck.html` in a browser:

- **← / →** or **Space** — navigate  
- **F** — fullscreen · **P** — print / save PDF  
- Tailored for **Electronics & Radar Development Establishment** (AESA, pulse/emitter AI, ERP co-process)

## Quick positioning

**Train** on air-gapped GPUs → **optimize** with OpenVINO → **deploy inference** on Altera Agilex 3/5/7 with FPGA AI Suite for deterministic, SWaP-efficient **radar** workloads at LRDE.
