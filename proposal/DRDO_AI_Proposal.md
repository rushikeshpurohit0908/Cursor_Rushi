# AI Compute Platform Proposal for DRDO

**Sovereign Training & Edge Inference Architecture**  
**Hardware • Software • Training Systems • Altera FPGA Inference**

| Field | Detail |
|---|---|
| **Prepared for** | Defence Research & Development Organisation (DRDO), Government of India |
| **Document type** | Technical & Commercial Proposal |
| **Focus** | End-to-end AI platform: training infrastructure + FPGA-based inference |
| **Inference silicon** | Altera® Agilex™ FPGA family with FPGA AI Suite |
| **Classification** | Restricted — for authorized evaluation only |
| **Version** | 1.0 |

---

## 1. Executive Summary

DRDO laboratories increasingly require a **sovereign, air-gappable AI compute stack** that can:

1. **Train** domain-specific models on classified datasets within secure facilities.
2. **Deploy inference** at the tactical edge — UAVs, radar/EW payloads, ground vehicles, naval platforms, and command posts — under strict Size, Weight, Power, and Cost (**SWaP-C**) and environmental constraints.
3. Remain **field-upgradable**, **deterministic in latency**, and **independent of cloud GPUs** for operational inference.

This proposal defines a complete **AI Compute Platform** comprising:

| Layer | Recommended approach |
|---|---|
| **Training** | Secure GPU-accelerated training clusters (air-gapped), with MLOps tooling for model lifecycle |
| **Model optimization** | PyTorch / ONNX → OpenVINO™ IR → quantization & validation |
| **Inference (edge & platform)** | **Altera Agilex™ FPGAs** with **FPGA AI Suite**, hostless or SoC-attached |
| **Inference (datacenter / C2)** | Altera Agilex™ PCIe accelerator cards + optional GPU fallback |
| **Software** | Unified toolchain: training frameworks, OpenVINO, FPGA AI Suite, Quartus® Prime, secure OTA |

**Why Altera FPGAs for DRDO inference**

- Deterministic, low-latency inference suitable for fire-control, EW, and ISR timelines  
- Reconfigurable fabric — new models without board respins  
- Superior performance-per-watt vs GPUs in SWaP-constrained payloads  
- Long product life cycles aligned with defence programs (10–15+ years)  
- Hostless and SoC deployment options for platform electronics  
- Mature path from trained models via **OpenVINO + FPGA AI Suite**

---

## 2. Problem Statement & DRDO Needs

### 2.1 Typical DRDO AI workloads

| Domain | Example AI tasks | Deployment constraint |
|---|---|---|
| **ISR / EO-IR** | Object detection, tracking, change detection, ATR | UAV / UGV / pod — low power, low latency |
| **Radar & EW** | Pulse classification, emitter ID, spectrum anomaly | Real-time, deterministic, RF-coupled |
| **Sonar / UW** | Contact classification, LOFAR feature ML | Rugged, long endurance |
| **Autonomy** | Perception, path planning assist, SLAM aids | Safety-critical, certifiable path |
| **C4ISR / fusion** | Multi-sensor fusion, NLP for intel, decision aids | Secure facility + forward C2 |
| **Cyber / signals** | Malware/anomaly, protocol ML | Air-gapped training, edge sensors |

### 2.2 Gaps this proposal closes

- Training locked to commercial cloud GPUs → **on-prem / air-gapped training**
- Inference GPUs that are power-hungry and export-sensitive for edge → **FPGA inference**
- Ad-hoc model porting → **standardized OpenVINO → FPGA AI Suite pipeline**
- Short commercial silicon life → **long-lifecycle Altera Agilex devices**

---

## 3. Solution Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    SECURE TRAINING FACILITY                      │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐ │
│  │ Data Vault   │→ │ GPU Training │→ │ Model Registry / MLOps │ │
│  │ (classified) │  │ Cluster      │  │ (versioned artifacts)  │ │
│  └──────────────┘  └──────────────┘  └───────────┬────────────┘ │
└──────────────────────────────────────────────────┼──────────────┘
                                                   │ export IR / ONNX
                                                   ▼
┌─────────────────────────────────────────────────────────────────┐
│              MODEL OPTIMIZATION & VALIDATION LAB                 │
│   PyTorch/ONNX → OpenVINO IR → Quantize (INT8/FP16) → Emulate   │
│              FPGA AI Suite (dla_compiler) + accuracy gates        │
└───────────────────────────────┬─────────────────────────────────┘
                                │ bitstream / network .bin
                ┌───────────────┼───────────────┐
                ▼               ▼               ▼
        ┌─────────────┐ ┌─────────────┐ ┌─────────────────┐
        │ Edge SoC    │ │ Hostless    │ │ PCIe Card /     │
        │ Agilex 5/3  │ │ Agilex 7/5  │ │ SmartNIC        │
        │ (UAV/UGV)   │ │ (payload)   │ │ (C2 / radar)    │
        └─────────────┘ └─────────────┘ └─────────────────┘
                     ALTERA FPGA INFERENCE TIER
```

**Design principle:** Train once in a secure GPU facility; **deploy everywhere** on Altera FPGAs with a single conversion toolchain.

---

## 4. Training Hardware

Training remains GPU-centric for large CNNs, transformers, and multi-modal models. The proposal includes a **sovereign training cluster** sized for DRDO lab use.

### 4.1 Recommended training cluster (reference configuration)

| Component | Specification (illustrative) | Qty (ref.) | Role |
|---|---|---|---|
| **GPU compute nodes** | Dual-socket Xeon/EPYC, 8× datacenter GPUs (e.g. H100/H200 or approved equivalent), 1–2 TB system RAM, NVMe | 4–16 nodes | Model training & fine-tuning |
| **GPU interconnect** | NVLink / NVSwitch within node; InfiniBand NDR or RoCE between nodes | As required | Distributed training |
| **CPU-only nodes** | High-core CPUs for ETL, labeling assist, classical ML | 2–4 | Data pipeline |
| **Storage** | Parallel FS or object store, encrypted at rest (AES-256), 0.5–2 PB usable | 1 system | Datasets & checkpoints |
| **Networking** | Air-gapped leaf-spine; no external internet; optional diode for model export | 1 fabric | Security |
| **Mgmt / jump** | Hardened bastion, MFA, SIEM integration | 2 | Operations |

### 4.2 Training software stack

| Layer | Tools |
|---|---|
| OS | RHEL / Rocky / Ubuntu LTS (hardened CIS baseline) |
| Containers | Kubernetes (air-gapped registry) or Slurm + Apptainer |
| Frameworks | PyTorch, TensorFlow, JAX (as needed) |
| Distributed | NCCL, DeepSpeed, FSDP, Horovod |
| Experiment tracking | MLflow / Weights & Biases self-hosted (air-gapped) |
| Data | Label Studio / CVAT (on-prem), DVC |
| Security | Full-disk encryption, signed containers, SBOM, audit logs |

### 4.3 Training → inference handoff

1. Export trained model as **ONNX** or framework-native checkpoint.  
2. Convert with **OpenVINO** to Intermediate Representation (`.xml` + `.bin`).  
3. Quantize and validate accuracy against golden test sets.  
4. Compile for target FPGA architecture with **FPGA AI Suite `dla_compiler`**.  
5. Sign artifacts; promote through Model Registry to field load.

---

## 5. Inference Hardware — Altera FPGAs

Altera FPGAs are the **primary inference substrate** for this proposal, covering edge payloads through command-and-control accelerators.

### 5.1 Device family mapping

| Altera device | Peak AI class (INT8, illustrative) | Best-fit DRDO use |
|---|---|---|
| **Agilex™ 3** | Up to ~2.6 TOPS | Smallest SWaP — munitions electronics, handheld, sensor nodes |
| **Agilex™ 5 E-Series** | Up to ~26 TOPS | UAV/UGV perception, EO pods, vehicle ECUs |
| **Agilex™ 5 D-Series** | Up to ~152 TOPS | High-performance edge ISR, multi-stream vision |
| **Agilex™ 7 I/M-Series** | Up to ~89 TOPS (M-Series class) | Radar/EW co-processors, PCIe cards, SmartNICs, C2 racks |
| **SoC FPGAs (HPS)** | Device-dependent | Single-chip Linux host + AI IP (reduced BOM) |

*TOPS figures are architecture- and IP-configuration dependent; final performance is sized per model via FPGA AI Suite Architecture Optimizer.*

### 5.2 Deployment form factors

| Form factor | Description | Typical platform |
|---|---|---|
| **Hostless / DDR-free** | Standalone AI IP in fabric; minimal or no external DRAM; lowest latency path | Missile electronics, tightly coupled sensors |
| **SoC-attached (HPS)** | Hard Processor System runs OpenVINO runtime; fabric runs AI IP | UAV companion computers, ground robots |
| **PCIe look-aside** | FPGA card attached to rugged server / SBC | Shelter C2, shipboard, lab validation |
| **SmartNIC / OFS** | Open FPGA Stack based boards for in-line or look-aside acceleration | Secure networking, multi-sensor ingest |

### 5.3 Reference inference BOM (example kits)

**A. Lab / evaluation kit**

| Item | Notes |
|---|---|
| Agilex 7 PCIe development board (e.g. DE10-Agilex class) | OpenVINO + FPGA AI Suite bring-up |
| Agilex 5 modular / SoC kit | Edge software stack development |
| Host workstation | Ubuntu, Quartus Prime, FPGA AI Suite, OpenVINO |

**B. Rugged edge module (production intent)**

| Item | Notes |
|---|---|
| Custom SOM / COM with Agilex 5 | Conduction-cooled, MIL connectors as required |
| Camera / RF front-end interfaces | MIPI, CXP, JESD204, Aurora, Ethernet |
| Secure boot & bitstream encryption | Anti-tamper options per program |

**C. C2 / rack inference**

| Item | Notes |
|---|---|
| Agilex 7 PCIe / OFS SmartNIC cards | Multi-stream batch + low-latency modes |
| Rugged 19" server (air-gapped) | Host for look-aside acceleration |

### 5.4 Why FPGA over GPU for DRDO edge inference

| Criterion | GPU | Altera FPGA |
|---|---|---|
| Latency determinism | Variable (batch/driver) | **Hard real-time friendly** |
| Power (edge) | High | **Lower W for fixed models** |
| Longevity | Short consumer/datacenter cycles | **Long defence lifecycle** |
| Reconfigurability | Fixed ISA | **Bitstream updates for new models** |
| Sensor coupling | Needs host CPU/GPU pipeline | **Direct fabric I/O (JESD, LVDS, Eth)** |
| Export / supply | Often constrained | **FPGA path supports program control** |

---

## 6. Software Stack

### 6.1 End-to-end toolchain

```
Train (PyTorch/TF) 
    → Export ONNX 
    → OpenVINO convert_model / ovc  →  IR (.xml/.bin)
    → Quantize & accuracy check
    → FPGA AI Suite dla_compiler (--march <arch.arch>)
    → Architecture Optimizer (area vs FPS trade-off)
    → Bit-accurate OpenVINO emulation (pre-silicon)
    → Quartus Prime: integrate AI IP → bitstream
    → Field runtime: OpenVINO HETERO:FPGA,CPU  (or hostless)
```

### 6.2 Core software components

| Component | Role |
|---|---|
| **PyTorch / TensorFlow** | Model development & training |
| **ONNX** | Framework-neutral exchange |
| **Intel Distribution of OpenVINO™** | IR conversion, plugins, heterogeneous execution |
| **Altera FPGA AI Suite** | Architecture optimization, AI IP generation, `dla_compiler`, emulation |
| **Quartus® Prime** | FPGA synthesis, place & route, bitstream |
| **Platform Designer** | SoC / interconnect integration |
| **Open FPGA Stack (OFS)** (optional) | Standardized PCIe / shell for accelerator cards |
| **Secure update agent** | Signed bitstream & network-bin delivery |

*FPGA AI Suite 2026.x aligns with OpenVINO 2025.4-class toolchains; exact version pinning is provided in the project SOW.*

### 6.3 Runtime modes

| Mode | OpenVINO device hint | Use when |
|---|---|---|
| FPGA-only | `FPGA` | All layers map to AI IP |
| Heterogeneous | `HETERO:FPGA,CPU` | Unsupported layers fall back to CPU |
| Hostless | Custom / direct | No host OS; lowest SWaP |

### 6.4 MLOps & DevSecOps for defence

- Air-gapped container registry and signed model artifacts  
- CI pipelines for accuracy regression on golden datasets  
- Bitstream encryption keys under HSM / program key management  
- SBOM generation for all software drops  
- Traceability: dataset hash → model hash → bitstream hash

---

## 7. Reference Use-Case Packages

### Package 1 — EO/IR ATR on UAV

| Item | Choice |
|---|---|
| Training | Secure GPU cluster; YOLOv8/RT-DETR or DRDO custom detector |
| Inference | Agilex 5 SoC module, INT8, MIPI/CoaXPress ingest |
| KPI targets | ≥30 FPS @ 1080p class, <50 ms e2e, <15–25 W module budget (sizing workshop) |

### Package 2 — Radar / EW classifier

| Item | Choice |
|---|---|
| Training | Spectrogram / I-Q CNN or transformer on air-gapped GPUs |
| Inference | Agilex 7 hostless or PCIe co-processor with JESD204C ADC path |
| KPI targets | Deterministic pipeline latency; continuous spectrum windows |

### Package 3 — Multi-sensor C2 fusion node

| Item | Choice |
|---|---|
| Training | Fusion / transformer models in secure lab |
| Inference | Agilex 7 PCIe cards in rugged server; OpenVINO hetero |
| KPI targets | Multi-stream throughput; signed model hot-swap |

---

## 8. Security, Assurance & Sovereignty

| Control | Approach |
|---|---|
| **Data residency** | Training & datasets never leave DRDO premises |
| **Air gap** | Training cluster isolated; controlled diode export of IR/bitstreams |
| **Bitstream security** | Encryption, authentication, anti-tamper options |
| **Supply chain** | Traceable BOM; approved distributor / program logistics |
| **Long-term support** | Multi-year silicon & tool support agreements |
| **Indigenous integration** | Partner with Indian SI / DPSU for board design, qualification, and ILS |

---

## 9. Implementation Roadmap

| Phase | Duration (indicative) | Deliverables |
|---|---|---|
| **Phase 0 — Discovery** | 4–6 weeks | Workload survey, model inventory, SWaP envelopes, success metrics |
| **Phase 1 — PoC** | 8–12 weeks | 1–2 models on Agilex eval kits; accuracy & latency report |
| **Phase 2 — Pilot** | 3–6 months | Rugged prototype module; training cluster slice; MLOps baseline |
| **Phase 3 — Scale** | Program-driven | Production SOM/PCIe, qualification (environmental), ILS docs |
| **Phase 4 — Fleet** | Ongoing | Model updates, bitstream OTA, training refresh cycles |

---

## 10. Commercial Outline (to be tailored)

> Detailed pricing is provided under a separate commercial annex after discovery.

### 10.1 Bill of Materials categories

1. **Training hardware** — GPU nodes, storage, networking, racks, PDUs  
2. **Inference hardware** — Altera devices, SOMs, PCIe cards, development kits  
3. **Software licenses** — Quartus Prime, FPGA AI Suite entitlements, OS/support  
4. **Services** — Architecture workshops, model porting, board bring-up, training for DRDO engineers  
5. **Support** — Multi-year TAC, silicon longevity, security patches  

### 10.2 Engagement models

- **PoC grant / evaluation** — kits + FAE support  
- **Turnkey lab** — training cluster + inference lab in one SOW  
- **Design-in** — FPGA IP + schematic review with DRDO / DPSU partners  
- **Training academy** — OpenVINO + FPGA AI Suite courses for DRDO scientists  

---

## 11. Why This Proposal

1. **Complete stack** — training GPUs + Altera FPGA inference, not a point product.  
2. **Defence-fit inference** — deterministic, SWaP-efficient, long-lifecycle Agilex FPGAs.  
3. **Proven toolchain** — PyTorch → OpenVINO → FPGA AI Suite → Quartus.  
4. **Scalable from lab to platform** — same model path for UAV, EW, and C2.  
5. **Sovereign operations** — air-gapped MLOps and signed field updates.  

---

## 12. Next Steps

1. Nominate DRDO labs / projects for a **2-day architecture workshop**.  
2. Select **2 flagship models** for Phase-1 PoC on Agilex evaluation hardware.  
3. Define **SWaP, latency, and accuracy gates** for go/no-go.  
4. Issue **technical SOW + commercial annex** for PoC and pilot.  

---

## Annex A — Technology References

- Altera FPGA AI Suite (model compile, Architecture Optimizer, emulation)  
- Intel Distribution of OpenVINO toolkit  
- Altera Agilex 3 / 5 / 7 device families  
- Quartus Prime design software  
- Open FPGA Stack (OFS) for PCIe accelerator shells  

## Annex B — Glossary

| Term | Meaning |
|---|---|
| **ATR** | Automatic Target Recognition |
| **HPS** | Hard Processor System (SoC FPGA CPU) |
| **IR** | Intermediate Representation (OpenVINO) |
| **OFS** | Open FPGA Stack |
| **SWaP-C** | Size, Weight, Power, and Cost |
| **TOPS** | Tera Operations Per Second |

## Annex C — Document control

| Version | Date | Notes |
|---|---|---|
| 1.0 | 2026-08-12 | Initial DRDO AI platform proposal (HW/SW, training, Altera inference) |

---

*Altera, Agilex, Quartus, and the Altera logo are trademarks of Altera Corporation. OpenVINO is a trademark of Intel Corporation. All other trademarks are the property of their respective owners. Performance figures are illustrative and subject to workload, precision, and architecture configuration. Final sizing requires a joint architecture workshop.*
