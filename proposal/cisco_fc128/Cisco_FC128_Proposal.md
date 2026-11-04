# Cisco Proposal — 128G Fibre Channel on Agilex™ 7 M-Series

**Altera Confidential** · Technical proposal for Cisco Systems  
**Device:** Agilex 7 M-Series **AGM039** · Package family **R47**  
**Application:** Fibre Channel **FC-128 / 128GFC** line card / bridge datapath

---

## 1. Executive summary

Altera proposes **Agilex™ 7 FPGA M-Series AGM039 (R47)** as the programmable datapath for Cisco’s next-generation **128G Fibre Channel** design.

The device maps the stated I/O plan with headroom:

| Domain | Channels | Rate | Role |
|---|---:|---|---|
| **Client (line)** | **8** | **112G PAM4** | 8 × 128GFC optical / electrical clients (FC-PI-8) |
| **System (primary)** | **16** | **58G PAM4** | Chip-to-chip / fabric toward Cisco ASIC or switch |
| **System (secondary)** | **8** | **58G** | Redundant fabric, debug, management, or expansion |

**Why AGM039 R47 fits**

- F-Tile **FHT** supports up to **116 Gbps PAM4** — covers 128GFC’s **112.2 Gbps** PAM4 line rate.
- F-Tile **FGT** supports up to **58 Gbps PAM4** — covers the 16 + 8 system-side channels.
- ~3.85M LEs, hardened Ethernet/PCIe options, and R47 package density for a multi-port FC bridge or line-card gearbox.

---

## 2. Requirements (as stated)

1. **Fibre Channel FC128** — 128GFC / FC-PI-8 class interface  
2. **Client side:** 8 channels × **112G**  
3. **System side:** 16 channels × **58G**  
4. **Additional:** 8 channels × **58G**  
5. **FPGA:** Agilex 7 **M 039** series, **R47** package

---

## 3. Fibre Channel 128G context

| Item | Spec |
|---|---|
| Marketing name | **128GFC** |
| Physical interface | FC-PI-8 |
| Line signaling | **PAM4**, **112.2 Gbps** (56.1 GBd) |
| Throughput (nominal) | ~12.4 GB/s per lane |
| FEC | Mandatory (RS-FEC class per FC-FS) |
| Optics form factor | SFP112 class (SR / LI / LW variants) |
| Backward compatibility | Two prior generations (64GFC / 32GFC) typical |

Client electrical I/O to the optical module is also PAM4 at the same rate — no optical-side modulation conversion. Host FEC terminates in the FPGA/ASIC.

---

## 4. Proposed architecture

```
                 CLIENT SIDE (FHT)                    SYSTEM SIDE (FGT)
   ┌──────────────────────────────────┐     ┌──────────────────────────────────┐
   │  8 × 112G PAM4  (128GFC)         │     │  16 × 58G PAM4  → Cisco ASIC     │
   │  SFP112 cages / onboard SerDes   │     │   8 × 58G       → secondary path │
   └────────────────┬─────────────────┘     └──────────────────▲───────────────┘
                    │                                          │
                    ▼                                          │
        ┌───────────────────────────────────────────────────────┴──────────┐
        │                                                                  │
        │              Altera Agilex™ 7 M-Series AGM039 (R47)               │
        │                                                                  │
        │   ┌─────────────┐  ┌──────────────────┐  ┌────────────────────┐  │
        │   │ FC-128 PCS  │→ │ Gearbox / Mux    │→ │ System PCS / MAC   │  │
        │   │ + RS-FEC    │  │ + buffering      │  │ or raw SerDes      │  │
        │   └─────────────┘  │ + credit / QoS   │  └────────────────────┘  │
        │                    └──────────────────┘                          │
        │   Soft logic: FC framing, rate-match, stats, CMIS mgmt bridge    │
        │   Optional: HBM2E / DDR5 for deep buffering (package-dependent)  │
        └──────────────────────────────────────────────────────────────────┘
```

### Bandwidth budget

| Path | Aggregate raw SerDes BW |
|---|---:|
| Client 8 × 112.2G | **~897.6 Gbps** |
| System 16 × 58G | **~928 Gbps** |
| Secondary 8 × 58G | **~464 Gbps** |

Primary client ↔ system path is **rate-matched with ~3% headroom** on the 16×58G fabric — appropriate for FEC/PCS overhead and clock-domain margining. The secondary 8×58G bank is available for dual-ASIC attach, hitless protection, diagnostics, or future port expansion.

---

## 5. Device & package recommendation

### Target OPN family

| Attribute | Recommendation |
|---|---|
| Device | **AGM039** (Agilex 7 M-Series) |
| Package | **R47** family (confirm R47A / R47B / R47C with Cisco BOM) |
| Logic | ~3.85M LE / ~1.31M ALM |
| High-speed TXRX | F-Tile FHT up to **116G PAM4**; FGT up to **58G PAM4** |

### R47 package options (select at BOM freeze)

| Package | Tile mix (typical) | 116G-class | 58G-class | Fit notes |
|---|---|---:|---:|---|
| **R47A** | 3× F-Tile + 1× R-Tile | 8 | 48 | Fits I/O plan + adds **PCIe 5.0 / CXL** host path |
| **R47B** | 4× F-Tile + HBM2E | 8 | 64 | Max fabric BW + **in-package HBM** for deep FC buffering |
| **R47C** | 4× F-Tile | **16** | 64 | Headroom if client ports grow beyond 8 |

**Baseline recommendation:** **R47A** if Cisco needs a PCIe/CXL host attach; **R47B** if deep on-package memory is required for store-and-forward or virtual-output queues; **R47C** if the roadmap needs more than eight 112G clients.

### Channel assignment (baseline)

| Bank | Count × rate | Tile resource | Assignment |
|---|---|---|---|
| Client | 8 × 112G PAM4 | **FHT** | 128GFC ports 0–7 |
| System A | 16 × 58G PAM4 | **FGT** | Primary ASIC / fabric |
| System B | 8 × 58G | **FGT** (or FHT @ 58G) | Secondary / protect / debug |

All three banks fit inside a single AGM039 R47 device with transceiver margin remaining for clocks, spares, and bring-up loops.

---

## 6. Datapath functions (FPGA soft + hardened IP)

1. **128GFC PMA/PCS** — 112.2G PAM4 SerDes, equalization, CDR  
2. **Mandatory RS-FEC** — encode/decode per FC-FS / FC-PI-8  
3. **FC framing & credit** — R_RDY / BB_Credit, frame delimiters, link init  
4. **Gearbox** — 8×112G ↔ 16×58G rate adaptation and lane striping  
5. **System-side PCS** — Cisco-defined chip-to-chip protocol or Ethernet-class PCS  
6. **Management** — CMIS bridge for SFP112 modules; MDIO/I²C; telemetry counters  
7. **Optional** — cut-through vs store-and-forward; congestion notify; SEU scrubbing

---

## 7. Why Agilex 7 M-Series for Cisco FC128

| Need | Altera answer |
|---|---|
| 112G PAM4 client | F-Tile **FHT to 116G PAM4** |
| Dense 58G system fabric | F-Tile **FGT to 58G PAM4** (48–64 ch depending on R47 SKU) |
| Single-chip 8-port FC128 bridge | One AGM039 covers client + both system banks |
| Memory for deep queues | DDR5 external and/or **HBM2E** (R47B) |
| Host / control attach | R-Tile **PCIe 5.0 / CXL** on R47A |
| Long lifecycle & local support | Altera production roadmap + India FAE coverage for Cisco |

---

## 8. Engagement plan (suggested)

| Phase | Scope | Outcome |
|---|---|---|
| **0 — Align** | Confirm R47A vs B vs C; Cisco system SerDes protocol; FEC ownership | Frozen I/O & package |
| **1 — Architecture** | Block diagram, BW/latency budget, pin mux, thermal | Architecture review sign-off |
| **2 — PoC** | 1–2 client ports + system loopback on AGM039 kit / Cisco board | Link-up + BER evidence |
| **3 — Pilot** | Full 8×112G + 16×58G integration; CMIS; stats | Proto bring-up |
| **4 — Production** | Timing closure, SEU, PVT, manufacturing test vectors | PVT / FCS support |

---

## 9. Open items for Cisco

1. Exact **R47** SKU (A / B / C) and HBM requirement  
2. System-side protocol on the **16×58G** and **8×58G** banks (raw SerDes, Ethernet PCS, proprietary)  
3. Soft vs hardened FEC ownership and latency budget  
4. Tri-rate requirement (128/64/32GFC) per client port  
5. Mechanical: SFP112 count, front-panel vs mid-plane optics  
6. Control-plane attach (PCIe, AXI, local CPU)  

---

## 10. Ask

Approve AGM039 R47 as the baseline FPGA for the Cisco **FC128** proposal and schedule a joint architecture workshop to freeze package SKU and system-side SerDes definition.

**Prepared for:** Cisco Systems  
**Prepared by:** Altera (FAE / Account team)  
**Device baseline:** Agilex™ 7 M-Series AGM039 · R47  
