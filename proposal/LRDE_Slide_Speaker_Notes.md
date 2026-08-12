# LRDE Slide Deck — Speaker Notes

**Deck:** `LRDE_AI_Slide_Deck.html` (16 slides)  
**Audience:** LRDE leadership, radar signal-processing, and AI teams (Bengaluru)

### How to present
- Open the HTML in Chrome/Edge → press **F** for fullscreen  
- **← / →** or **Space** to navigate · **P** to print/PDF  
- Direct link to a slide: `#12`

---

## Slide-by-slide notes

### 1 — Title
Open with Altera brand, then LRDE. Emphasize **radar-specific** AI — not a generic datacenter pitch.

### 2 — Agenda
Promise a full path: training lab → toolchain → Agilex inference → PoC.

### 3 — LRDE context
Anchor to LRDE charter: ground / ship / airborne / space-related radars; AESA; AI/ML for radar applications on DRDO foresight lists.

### 4 — Problem
Two pain points: classified training data trapped on-prem; GPUs poor fit for ERP/SWaP. Desired outcome = train on-prem, infer on FPGA beside DSP.

### 5 — Architecture
“Train once, infer on Agilex.” Point at three deploy points: hostless ERP, SoC edge, PCIe shelter.

### 6 — Training hardware
Air-gapped GPU cluster sized for spectrogram / RD / track models. Stress encryption and no public cloud.

### 7 — Training software
PyTorch + MLOps inside the wire; handoff is ONNX → OpenVINO IR → FPGA AI Suite.

### 8 — Agilex mapping
Map devices to LRDE placements (mini SoC radar → mobile → multi-channel → ERP/PCIe). Note TOPS are configuration-dependent.

### 9 — Form factors
Hostless for pulse windows; SoC for transportable radars; PCIe/OFS for shelters and labs. Mention JESD204 attach.

### 10 — FPGA vs GPU
Determinism, fabric I/O, power, longevity — the LRDE buying criteria.

### 11 — Toolchain
Walk the one-liner flow; name OpenVINO, FPGA AI Suite (`dla_compiler`), Quartus.

### 12 — Use cases (PoC picks)
1. Emitter/pulse ID  
2. Target/clutter assist on RD maps  
3. Netted fusion in shelter  
Ask LRDE which two to start with.

### 13 — Security
Data residency, air gap, bitstream trust, Indian SI/DPSU partners.

### 14 — Roadmap
Phase 0→3 with clear deliverables. PoC in 8–12 weeks after discovery.

### 15 — BOM
Categories only; commercials after workshop. Point to `BOM_Reference.md`.

### 16 — Next steps
Close on workshop date, two models, KPI gates, SOW.

---

## Suggested workshop ask
> “Nominate ERP and AI owners for a 2-day session; bring one labeled pulse dataset and one RD/track dataset for PoC scoping.”
