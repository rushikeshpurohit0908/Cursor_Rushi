# Intel Oak Stream and Agilex™ 5 Platform Management

## Short answer

**Oak Stream (OKS)** is Intel’s next-generation Xeon server platform for
**Diamond Rapids**. **Agilex™ 5 E-Series SoC FPGAs** are Altera’s recommended
devices for the **next generation of data-center platform management** on that
class of servers—especially when you need to consolidate Secure Control Module
(SCM) and Platform Firmware Resiliency (PFR) / Platform Root of Trust (PRoT)
functions into one chip.

```text
Oak Stream host platform (HPM / motherboard)
  CPU(s) · VR · clocks · sensors · low-speed I/O
           │
           │  LTPI over LVDS
           │  (GPIO, I2C/SMBus, UART, data, OEM)
           ▼
DC-SCM / management module
  Agilex 5 E-Series SoC
    ├─ SCM FPGA functions (power sequencing, LTPI, GPIO expand)
    ├─ PRoT / PFR (auth, verify, secure update) via SDM
    └─ optional BMC / AMC consolidation (HPS + PCIe + Ethernet)
```

On current **Birch Stream (BHS)** reference platforms, Altera publicly documents
**MAX® 10** as the validated HPM / SCM / PFR 4.0 FPGA, and as the HPM FPGA on
**BHS+1**. Agilex 5 is the forward path for higher security, function
consolidation, and denser I/O—not a drop-in rename of the MAX 10 BHS BOM.

## Platform context

| Codename | Typical CPU generation | Platform role |
| --- | --- | --- |
| Eagle Stream (EGS) | Sapphire Rapids / Emerald Rapids era | Prior Xeon scalable platform |
| Birch Stream (BHS) | Granite Rapids / Sierra Forest (Xeon 6) | Current reference platform; MAX 10 validated for HPM/SCM/PFR |
| Oak Stream (OKS) | Diamond Rapids (Xeon 7 path) | Next platform; PCIe 6 / CXL-class I/O, higher core/memory density |

Oak Stream itself is an Intel **platform** name. Altera’s public platform-
management materials describe FPGA roles for OCP-style modular servers
(DC-SCM, HPM, UBB/OAM) and position Agilex 5 as the device family for those
roles going forward. Treat any specific Oak Stream reference-board OPN or pinout
as **program-confidential** unless you have the RVP / DC-SCM BOM from Intel or
Altera FAE channels.

## Where Agilex 5 sits in the management stack

OCP **DC-SCM** moves management, security, and control off the baseboard onto a
pluggable Secure Control Module. Low-speed signals between the Host Platform
Module (HPM) and SCM are tunneled with **LTPI** (LVDS Tunneling Protocol and
Interface).

| Role | Function | Agilex 5 fit |
| --- | --- | --- |
| **SCM FPGA** | DC-SCM power sequencing, LTPI endpoint, local GPIO/I2C expand | Soft LTPI IP; high I/O packages |
| **PRoT / PFR** | Authenticate firmware, verify boot chain, secure update | SDM (secure boot, bitstream auth/encrypt, SPDM, PUF, anti-tamper) |
| **BMC** | Boot orchestration, telemetry, thermal/power, OOB management | HPS (dual A76 + dual A55), Ethernet, USB, I3C/I2C, DDR |
| **AMC** | Add-in / OAM card management and HW RoT | Same SoC features at card form factor |
| **HPM FPGA** | Baseboard sequencing and LTPI peer | Still commonly MAX 10 on BHS/BHS+1; Agilex 3/5 when density or longevity drive a redesign |

Agilex 5’s main platform-management value proposition is **BOM consolidation**:
one E-Series SoC can host SCM + PFR (and, when required, BMC-class software on
the HPS) instead of separate CPLD/FPGA + discrete RoT silicon.

## Why Agilex 5 for Oak Stream–class designs

Compared with MAX 10–centric BHS designs, Agilex 5 E-Series adds:

1. **Secure Device Manager (SDM)** — hardened crypto for secure boot, bitstream
   authentication/encryption, SPDM attestation, anti-tamper, secure key
   provisioning, and PUF key storage. Needed for PFR 5.0–class RoT work that
   Altera demonstrated with Agilex 5 DC-SCM at OCP Summit.
2. **Hard Processor System** — dual Arm Cortex-A76 @ 1.8 GHz + dual Cortex-A55
   @ 1.5 GHz, plus USB 2.0/3.1, I2C/I3C, SPI, UART, 1G/2.5G Ethernet MAC, and
   TSN. Enough compute for BMC/AMC firmware stacks without an external SoC in
   many designs.
3. **PCIe 4.0 Hard IP** — host or management-plane connectivity for denser
   control modules.
4. **Official LTPI soft IP** — Quartus IP Catalog support for Agilex 5 (also
   Agilex 3 and MAX 10), compliant with OCP DC-SCM 2.1 LTPI rev 1.1, up to
   **500 Mbps** on Agilex 5, with GPIO / I2C / UART / OEM / data channel
   aggregation and link training.
5. **Intel 7 process + supply longevity** — Altera positions the family for
   multi-generation platform management with resilient lead times.

Use **MAX 10** when the design is cost/power sensitive, already validated on
BHS, or needs instant-on dual-config flash for a simple HPM/SCM CPLD role.
Use **Agilex 5 E-Series SoC** when Oak Stream–class security (PFR/PRoT),
SCM+PFR consolidation, or BMC-class HPS features are requirements.

## Recommended architecture for an Oak Stream DC-SCM

```text
                    ┌──────────────── Oak Stream HPM ────────────────┐
                    │  Diamond Rapids CPU domain                      │
                    │  power rails · clocks · board GPIO/I2C/UART     │
                    │         ▲                                       │
                    │         │ LTPI LVDS (clk+data each way)         │
                    └─────────┼───────────────────────────────────────┘
                              │
                    ┌─────────┼──────── DC-SCM ───────────────────────┐
                    │         ▼                                       │
                    │  ┌──────────────────────────────────────────┐   │
                    │  │ Agilex 5 E-Series SoC                    │   │
                    │  │                                          │   │
                    │  │  Fabric: LTPI IP · sequencers · glue     │   │
                    │  │  SDM:    PRoT / PFR / secure config      │   │
                    │  │  HPS:    OpenBMC or AMC firmware (opt.)  │   │
                    │  │  I/O:    QSPI · 1GbE MNG · USB · I3C     │   │
                    │  └──────────────────────────────────────────┘   │
                    │         SPI/QSPI flash · DDR (if HPS used)      │
                    └─────────────────────────────────────────────────┘
```

### Design checklist

1. **Pick the endpoint role first** — SCM-only, SCM+PFR, or SCM+PFR+BMC.
   That drives whether you need an SoC (HPS) SKU or can stay fabric-centric.
2. **Instantiate Altera LTPI IP** for the HPM↔SCM LVDS link. Do not invent a
   private LVDS framing protocol if the peer expects OCP DC-SCM LTPI.
3. **Enable SDM security features** required by the PFR profile (secure boot,
   authenticated bitstreams, key provisioning, SPDM as applicable).
4. **Partition flash** — configuration image(s) for the FPGA, plus measured
   firmware store for BMC/PFR payloads when those functions live on-chip.
5. **Bring up HPS only if software needs it** — OpenBMC / custom AMC stacks
   need DDR, Ethernet, and a proven boot chain (SDM → ATF → U-Boot → Linux or
   Zephyr). A pure sequencer + LTPI SCM can stay fabric-only.
6. **Keep HPM peer compatibility** — if the Oak Stream HPM still uses MAX 10
   LTPI (as on BHS+1), verify LTPI speed grades and channel maps against that
   peer before freezing the Agilex 5 pinout.
7. **Confirm the OPN with FAE** — package, I/O count, transceiver need, and
   industrial/commercial grade must match the DC-SCM form factor and thermal
   envelope. Public marketing docs do not publish a frozen Oak Stream Agilex 5
   BOM.

## Device selection notes

| Consideration | Guidance |
| --- | --- |
| Series | Prefer **Agilex 5 E-Series SoC** for platform management (power/size optimized). |
| Density | Size from LTPI + sequencing + PFR logic, then add HPS software headroom. Mid densities (for example 028B-class) are common evaluation points; final LE count is design-specific. |
| Package | Small VPBGA packages matter for DC-SCM real estate; confirm I/O vs. ball-map early. |
| LTPI rate | Agilex 5 LTPI IP supports up to 500 Mbps; negotiate a common rate with the HPM peer. |
| Tools | Quartus Prime Pro with the LTPI IP from the IP Catalog; follow the current LTPI UG for the Quartus version in use. |

Related OPN research in this repo’s history (for example
`A5EB028BB23BI6X`) is useful for **MSL / mass / package** diligence, but is
**not** by itself proof of an official Oak Stream reference BOM.

## What this note does *not* claim

- A public, complete Oak Stream RVP schematic or FPGA OPN list.
- That Agilex 5 replaces MAX 10 on every HPM in the first Oak Stream
  platforms—Altera still documents MAX 10 on BHS and as HPM on BHS+1.
- Bit-exact PFR 5.0 policy content (use the Intel/Altera PFR collateral for
  the target generation).

For board-level OPNs, pin mux, and reference RTL, use the Intel Oak Stream /
DC-SCM program package or Altera FAE deliverables.

## References

1. Altera — *Implementing Next-Generation Data Center Platform Management Using MAX 10 and Agilex 5 Devices* (solution brief):
   https://docs.altera.com/api/khub/documents/cHdlwLWfSYL8G69RHjKTXg/content
2. Altera — *LVDS Tunneling Protocol and Interface (LTPI) IP User Guide* (Agilex 3 / Agilex 5 / MAX 10):
   https://docs.altera.com/r/docs/844310/current
3. Altera — LTPI IP features (DC-SCM 2.1 LTPI 1.1, up to 500 Mbps on Agilex 5):
   https://docs.altera.com/r/docs/844310/26.1/lvds-tunneling-protocol-and-interface-ltpi-ip-user-guide/ip-features?contentId=YfZuM5m0lNgbCtQIDKh2oA
4. Altera — *Agilex 5 FPGAs and SoCs Device Overview*:
   https://docs.altera.com/r/docs/762191/current/agilex-5-fpgas-and-socs-device-overview
5. Altera — Agilex 5 product page:
   https://www.altera.com/products/fpga/agilex/5
6. OCP — Hardware Management / DC-SCM:
   https://www.opencompute.org/
7. Altera LinkedIn — Agilex 5 DC-SCM + PFR 5.0 demo (OCP Summit 2024):
   https://www.linkedin.com/posts/altera-fpga_this-week-from-october-15th-to-17th-at-activity-7251698329716207617-412O
