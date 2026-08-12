# DRDO AI Proposal — Bill of Materials (Reference)

Illustrative BOM for discovery workshops. Quantities and SKUs to be finalized after Phase-0.

## A. Training facility

| # | Item | Spec (ref.) | Qty | Notes |
|---|---|---|---|---|
| T1 | GPU training node | 8× datacenter GPU, dual CPU, 1–2 TB RAM, NVMe | 4–16 | Air-gapped |
| T2 | CPU ETL node | High-core CPU, 512 GB–1 TB RAM | 2–4 | Data pipeline |
| T3 | Storage system | Encrypted parallel/object, 0.5–2 PB usable | 1 | AES-256 at rest |
| T4 | IB / RoCE fabric | NDR or equivalent leaf-spine | 1 | Training fabric |
| T5 | Mgmt / bastion | Hardened jump hosts + MFA | 2 | Ops |
| T6 | Rack / PDU / cooling | As-built | Lot | Facility |

## B. Inference — Altera FPGA

| # | Item | Spec (ref.) | Qty | Notes |
|---|---|---|---|---|
| I1 | Agilex 7 PCIe eval kit | DE10-Agilex or OFS-class board | 2–4 | Lab PoC |
| I2 | Agilex 5 SoC / modular kit | E-Series modular DK | 2–4 | Edge SW bring-up |
| I3 | Agilex 3 eval | Low-SWaP exploration | 1–2 | Optional |
| I4 | Rugged Agilex 5 SOM | Conduction-cooled production intent | TBD | Pilot |
| I5 | Agilex 7 PCIe / SmartNIC | C2 / radar co-process | TBD | Pilot |
| I6 | Host rugged SBC / server | For PCIe look-aside | TBD | As required |

## C. Software & tools

| # | Item | Notes |
|---|---|---|
| S1 | Quartus Prime (design suite) | Synthesis / P&R |
| S2 | FPGA AI Suite | `dla_compiler`, Architecture Optimizer, emulation |
| S3 | OpenVINO toolkit | IR conversion & runtime plugins |
| S4 | Training frameworks | PyTorch / TF in air-gapped registry |
| S5 | MLOps | MLflow/DVC self-hosted |

## D. Services

| # | Item | Notes |
|---|---|---|
| V1 | Architecture workshop (2 days) | Workload & SWaP discovery |
| V2 | Model porting PoC | 1–2 networks to Agilex |
| V3 | Board / SOM design assist | With Indian SI / DPSU |
| V4 | Engineer enablement | OpenVINO + FPGA AI Suite training |
| V5 | Multi-year support | TAC + longevity |

---

See `DRDO_AI_Proposal.md` for full technical narrative and `DRDO_AI_Proposal.html` for presentation view.
