# Cisco FC128 — Executive Brief

**One page · Agilex™ 7 M-Series AGM039 (R47)**

## Offer

A single-chip **128G Fibre Channel** datapath on **Agilex 7 AGM039 R47**: eight **112G PAM4** client ports (128GFC) gearboxed to a **16×58G** primary system fabric, with an additional **8×58G** bank for protect / expansion. **Altera Search IP** (TCAM / BCAM / MBL) provides the recommended classify / lookup fabric for zoning, ACL, VSAN, and DID-SID ahead of the gearbox.

## I/O map

| Side | Channels | Rate | Use |
|---|---:|---|---|
| Client | 8 | 112G PAM4 | 128GFC (FC-PI-8) |
| System | 16 | 58G PAM4 | Cisco ASIC / fabric |
| System+ | 8 | 58G | Secondary / debug |

Aggregate: **~898 Gbps** client ↔ **~928 Gbps** primary system (**~3% headroom**).

## Device fit

- **FHT** to 116G PAM4 → covers 112.2G 128GFC clients  
- **FGT** to 58G PAM4 → covers 16+8 system channels  
- **Search IP** — TCAM (ternary ACL/zoning), BCAM (exact FID/WWPN), MBL (HBM/DDR scale-out)  
- R47A (PCIe/CXL), R47B (HBM2E), or R47C (more 116G) — pick at BOM freeze  

## Suggested start

1. Freeze R47 SKU + system SerDes protocol + Search IP enablement  
2. Architecture workshop (BW, FEC, latency, table sizing)  
3. PoC: 1–2 client ports + system loopback + sample classify path  

**Deck:** `Cisco_FC128_Agilex7_Proposal.pptx` · **Full:** `Cisco_FC128_Proposal.md`
