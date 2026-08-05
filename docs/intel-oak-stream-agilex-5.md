# Intel Oak Stream + Agilex 5 Platform Guide

This guide describes how **Intel Oak Stream** server platforms and **Altera Agilex 5**
FPGAs fit together for data-center platform management. It is an integration and
architecture guide, not a substitute for Intel platform reference designs, Altera
device handbooks, or the OCP DC-SCM specifications.

## Scope and naming

| Name | What it is |
| --- | --- |
| **Oak Stream** | Intel's next-generation Xeon server platform for **Diamond Rapids** processors |
| **Agilex 5** | Altera's mid-range FPGA/SoC family (Intel 7 process) used for platform management |
| **Oak Springs Canyon** | A separate, earlier infrastructure processing unit (IPU) product — **not** Oak Stream |

Do not conflate Oak Stream with Oak Springs Canyon. Oak Stream is a CPU server platform;
Agilex 5 on Oak Stream boards typically implements HPM, SCM, PRoT/PFR, BMC, or AMC
functions rather than general-purpose compute acceleration.

## Oak Stream platform overview

Oak Stream is the successor to **Birch Stream** (Granite Rapids / Sierra Forest /
Clearwater Forest). Public information points to these characteristics:

| Attribute | Oak Stream (expected) | Birch Stream (current) |
| --- | --- | --- |
| CPU generation | Diamond Rapids (Panther Cove) | Granite Rapids / Sierra Forest |
| Socket | LGA 9324 | LGA 7529 / LGA 4710 |
| Process node | Intel 18A | Intel 3 |
| Max P-cores | Up to 192 (4 × 48-core tiles) | Up to 128–288 (SKU dependent) |
| Memory | 8- or 16-channel DDR5; MRDIMM Gen 2 up to ~12,800 MT/s | Up to 12-channel DDR5 |
| PCIe | Gen 6 (with CXL support) | Gen 5 |
| TDP | Up to ~500 W per socket | Lower on current SKUs |
| Launch window | ~2026–2027 | 2024–2025 |

Oak Stream targets AI inference, HPC, and high-bandwidth data-center workloads.
Diamond Rapids adds improved **AMX** support (including FP8 and TF32) and is expected
to pair with Intel **Jaguar Shores** AI accelerators over PCIe Gen 6.

### Platform topology (conceptual)

```text
                         Oak Stream server
┌────────────────────────────────────────────────────────────────────┐
│  Diamond Rapids Xeon (HPM host)                                    │
│  ┌──────────┐  PCIe Gen 6 / CXL  ┌─────────────────────────────┐  │
│  │ CPU tiles│◄──────────────────►│ Accelerators (GPU, Jaguar    │  │
│  │ + I/O    │                    │ Shores, SmartNIC, etc.)       │  │
│  └────┬─────┘                    └─────────────────────────────┘  │
│       │ eSPI / PCIe / USB / I3C                                    │
│  ┌────▼──────────────────────────────────────────────────────┐    │
│  │ HPM FPGA (often MAX 10) — power seq, GPIO, LTPI bridge    │    │
│  └────┬──────────────────────────────────────────────────────┘    │
│       │ LTPI (LVDS)                                                │
│  ┌────▼──────────────────────────────────────────────────────┐    │
│  │ DC-SCM module                                              │    │
│  │  ┌─────────────┐  ┌──────────┐  ┌─────────────────────┐  │    │
│  │  │ Agilex 5    │  │ BMC SoC  │  │ PRoT / PFR (Agilex 5 │  │    │
│  │  │ SCM / RoT   │  │          │  │  or consolidated)    │  │    │
│  │  └─────────────┘  └──────────┘  └─────────────────────┘  │    │
│  └────────────────────────────────────────────────────────────┘    │
└────────────────────────────────────────────────────────────────────┘
```

## Why Agilex 5 on Oak Stream

Altera positions **Agilex 5 E-Series SoC FPGAs** as the next-generation platform
management device for modular xPU servers. Compared with MAX 10 (used widely on Birch
Stream reference platforms), Agilex 5 adds:

- **Secure Device Manager (SDM)** with hardened crypto, secure boot, bitstream
  authentication/encryption, SPDM attestation, anti-tamper, and PUF key storage
- **Hard Processor System (HPS)** — dual Cortex-A76 @ 1.8 GHz + dual Cortex-A55 @ 1.5 GHz
- **PCIe 4.0** hard IP (up to x8 on E-Series, up to x8 × 6 on D-Series)
- **LTPI IP** support in Quartus for OCP DC-SCM 2.0 HPM↔SCM tunneling
- **Function consolidation** — SCM + PRoT/PFR on a single Agilex 5 device to reduce BOM
- **AI tensor blocks** in the DSP for predictive failure monitoring and anomaly detection

MAX 10 remains the cost-optimized choice for high-volume HPM and simple SCM roles.
Agilex 5 is the upgrade path when security, I/O density, or HPS offload is required.

## Agilex 5 device families

### E-Series (power- and size-optimized)

Best fit for **DC-SCM, PRoT, PFR, BMC offload, and AMC** roles on Oak Stream boards.

| Resource | E-Series range |
| --- | --- |
| Logic elements | 50k – 656k |
| Package | As small as 15 mm × 15 mm |
| Transceivers | Up to 24 × 28 Gbps |
| PCIe | Up to PCIe 4.0 ×4 + 10/25 GbE ×6 hard IP |
| Memory (HPS) | DDR4 @ 2,667 Mbps; DDR5 @ 3,600 Mbps; LPDDR4/5 @ 3,733 Mbps |
| AI (INT8 peak) | Up to ~26 TOPS |
| HPS | Dual A76 + dual A55 |

Common platform-management OPNs include smaller E-Series parts (for example A5E008,
A5E013) with Final data-sheet status, and mid-density parts such as A5ED065 for
development kits.

### D-Series (performance-optimized)

Better suited to **higher-throughput management, add-in card control, or workloads
that need more fabric and PCIe bandwidth** — not the default DC-SCM SCM choice.

| Resource | D-Series range |
| --- | --- |
| Logic elements | 515k – 1,616k |
| Package | As small as 32 mm × 32 mm |
| Transceivers | Up to 48 × 28 Gbps |
| PCIe | Up to 6 × PCIe 4.0 ×8 + 24 × 10/25 GbE hard IP |
| Memory (HPS) | DDR5 @ 5,600 Mbps; LPDDR5 @ 5,500 Mbps |
| AI (INT8 peak) | Up to ~152.6 TOPS |
| Post-quantum secure boot | Supported on D-Series |

## Platform management roles

Oak Stream boards following **OCP DC-MHS / DC-SCM** modular architecture assign FPGA
functions as follows.

### HPM FPGA (Host Platform Module)

Located on the main server board next to the CPU. Typical responsibilities:

- Platform power sequencing
- GPIO expansion and board-specific pin muxing
- LTPI bridge toward the DC-SCM
- Voltage regulator and clock control handshakes

On Birch Stream reference platforms this role is often a **MAX 10**. Oak Stream designs
may continue with MAX 10 for HPM or migrate HPM logic into a larger Agilex 5 when
consolidation is desired.

### SCM FPGA (Secure Control Module)

Located on the removable **DC-SCM** mezzanine. Typical responsibilities:

- LTPI endpoint toward HPM
- Board management interface bridging (I2C/SMBus tunneling, UART, GPIO)
- Security policy enforcement hooks
- In-field upgrade support for management firmware

**Agilex 5 E-Series SoC** is the recommended SCM device for new Oak Stream designs
because of SDM security, HPS, and LTPI IP support.

### PRoT / PFR (Platform Root of Trust / Platform Firmware Resiliency)

- Authenticates and verifies host firmware before release
- Monitors SPI flash buses to the CPU and BMC
- Supports measured boot and recovery flows

Agilex 5 can host PRoT/PFR in fabric, in HPS software, or as a consolidated SCM+PRoT
design. Birch Stream PFR 4.0 reference designs used MAX 10; Oak Stream generation
designs are expected to move PRoT/PFR to Agilex 5.

### BMC and AMC

- **BMC** on DC-SCM handles out-of-band management (power, thermal, telemetry, Redfish).
- **AMC** on accelerator OAM modules or PCIe add-in cards provides per-card RoT and
  management.

Agilex 5 E-Series with HPS can run BMC-adjacent control tasks or serve as the AMC
RoT on accelerator cards.

## LTPI: HPM↔SCM interconnect

**LTPI** (LVDS Tunneling Protocol and Interface) is defined in **OCP DC-SCM 2.0**. It
replaces legacy SGPIO-style HPM↔SCM links with source-synchronous LVDS.

### Supported Quartus families

| Device family | LTPI IP in Quartus |
| --- | --- |
| Agilex 5 | Yes |
| Agilex 3 | Yes |
| MAX 10 | Yes |
| Cyclone V | **No** |

### LTPI channel types

LTPI time-multiplexes these logical channels over four differential pairs (TX/RX clock
and data in each direction):

- GPIO
- I2C / SMBus (with clock stretching for LTPI latency)
- UART
- Raw data / OEM extensions (including AVMM-style register access)

### LTPI design checklist

1. Instantiate **LTPI IP** from the Quartus IP Catalog for the correct endpoint role
   (HPM controller/target vs SCM controller/target).
2. Match **LVDS I/O bank** placement and termination to the DC-SCM connector pinout.
3. Run **timing closure** on the 25 MHz base link clock and negotiated speed modes.
4. Validate **I2C tunneling** against the BMC's expected bus topology on both HPM and
   SCM sides.
5. Exercise **link state machine** paths: detect, negotiate, configure, operational,
   fault recovery.
6. Cross-test against the partner endpoint (HPM MAX 10 ↔ SCM Agilex 5 is a common
   Oak Stream combination).

Refer to the [LTPI IP User Guide](https://docs.altera.com/r/docs/844310/current) and
the [OCP DC-SCM 2.0 LTPI specification](https://www.opencompute.org/documents/ocp-dcm-scm-2-0-ltpi-ver-1-0-pdf)
for normative protocol details.

## Key host interfaces

Agilex 5 platform-management designs on Oak Stream typically expose:

| Interface | Typical use |
| --- | --- |
| **eSPI** | Connection to Diamond Rapids PCH-side management |
| **PCIe 4.0** | Management endpoint, BMC communication, or debug |
| **I3C / I2C / SPI** | VR, EEPROM, temperature sensors, FRU |
| **UART** | Serial debug and BMC console bridging |
| **QSPI** | Configuration flash and RSU image storage |
| **1 GbE / 2.5 GbE** | Dedicated management NIC on DC-SCM |
| **LTPI (LVDS)** | HPM↔SCM tunnel |

Oak Stream host CPUs provide **PCIe Gen 6** to accelerators. Agilex 5 management devices
remain on **PCIe 4.0** — this is expected and does not limit their role.

## Security architecture

Agilex 5 **Secure Device Manager (SDM)** underpins platform trust:

1. **Secure boot** — authenticated FPGA configuration bitstream
2. **Bitstream encryption** — protects IP in transit and at rest
3. **SPDM attestation** — proves device identity to the host BMC/BIOS chain
4. **Anti-tamper** — detects physical intrusion attempts
5. **PUF key storage** — device-unique keys without external secure element (optional)
6. **Remote System Update (RSU)** — A/B firmware slots for in-field upgrades

For PRoT/PFR flows, the Agilex 5 device sits in the SPI path between the BMC/CPU and
boot flash, verifying signatures before allowing code to execute. Plan the trust chain
early: SDM → PRoT bitstream → BMC firmware → host BIOS/UEFI → OS.

D-Series devices add **post-quantum cryptography (PQC) secure boot** for long-lived
platforms.

## Development workflow

### 1. Obtain platform collateral

Before starting RTL, collect from Intel/Altera/OEM partners:

- Oak Stream reference validation platform (RVP) schematics and BOM
- DC-SCM connector pinout and LTPI channel map
- HPM↔SCM signal list (GPIO, I2C bus numbering, UART ports)
- Power-sequencing script and VR PMBus addresses
- Expected PRoT/PFR policy (which SPI buses are monitored)

Oak Stream RVP details are not yet as public as Birch Stream **Avenue City** /
**Beechnut City** platforms. Treat pre-release collateral as NDA-bound.

### 2. Select devices and Quartus edition

| Role | Suggested device | Quartus edition |
| --- | --- | --- |
| HPM (simple) | MAX 10 (high I/O density 19×19 mm package) | Quartus Prime **Standard** |
| SCM / PRoT | Agilex 5 E-Series SoC (e.g., A5E013 – A5E065) | Quartus Prime **Pro** |
| AMC on OAM | Agilex 5 E-Series | Quartus Prime **Pro** |

Pin down the exact OPN, package, speed grade, and temperature grade before generating
IP. Changing devices late invalidates LTPI PHY placement and HPS DDR calibration.

### 3. Start from Golden System Reference Design (GSRD)

For Agilex 5 HPS bring-up, use the official GSRD rather than a blank project:

- Repository: [altera-fpga/agilex5e-ed-gsrd](https://github.com/altera-fpga/agilex5e-ed-gsrd)
- Documentation: [Agilex 5 E-Series Premium GSRD User Guide](https://altera-fpga.github.io/latest/embedded-designs/agilex-5/e-series/premium/gsrd/ug-gsrd-agx5e-premium/)
- Development kit: DK-A5E065BB32AEA (065B Premium) or DK-A5E065AB32AEA (065A Premium)
- Quartus version: 26.1 (check release notes for your installed version)

The GSRD provides HPS-first boot (Cortex-A55), DDR calibration, peripheral enablement,
and a fabric subsystem suitable as a starting point for SCM firmware development.

### 4. Add platform-management IP

In Quartus Prime Pro:

1. Add **LTPI IP** with the correct endpoint configuration.
2. Add **PRoT/PFR IP** if using Altera's reference PFR solution (validate against PFR
   version required by the platform).
3. Connect HPS bridges to fabric CSRs for software-driven management tasks.
4. Generate **SDM-signed** bitstreams for production.

### 5. Software stack

| Layer | Source |
| --- | --- |
| Arm Trusted Firmware | [altera-fpga/arm-trusted-firmware](https://github.com/altera-fpga/arm-trusted-firmware) |
| U-Boot | [altera-fpga/u-boot-socfpga](https://github.com/altera-fpga/u-boot-socfpga) |
| Linux | [altera-fpga/linux-socfpga](https://github.com/altera-fpga/linux-socfpga) |
| RSU / firmware update | [LIBRSU](https://github.com/altera-fpga/librsu) + RSU driver |
| Root filesystem | Yocto meta-altera layer |

Boot order for HPS-first designs: SDM loads bitstream → ATF on A55 → U-Boot → Linux.
BMC firmware on a separate SoC coordinates with the Agilex 5 HPS over I3C/PCIe.

### 6. Validation

| Test | Pass criteria |
| --- | --- |
| LTPI link bring-up | State machine reaches Operational; GPIO loopback passes |
| I2C tunneling | BMC can probe HPM VRs and sensors at expected addresses |
| Power sequencing | Rails come up in spec order; fault shutdown works |
| PRoT/PFR | Unsigned BIOS rejected; signed recovery image accepted |
| RSU | A/B slot swap succeeds without bricking |
| Thermal | Agilex 5 junction temp within limit under DC-SCM airflow |

## Device selection guide

| Requirement | Recommendation |
| --- | --- |
| Smallest DC-SCM BOM, basic LTPI bridge | MAX 10 SCM + MAX 10 HPM |
| Secure boot + PRoT on Oak Stream | Agilex 5 E-Series SoC (SCM + PRoT consolidated) |
| Need HPS Linux for custom management agent | Agilex 5 E-Series SoC |
| >400 single-chip I/O pins on HPM | MAX 10 high I/O density (485 I/O, 19×19 mm VPBGA) |
| High-bandwidth PCIe management endpoint | Agilex 5 D-Series |
| AI-driven predictive maintenance in fabric | Agilex 5 E- or D-Series (tensor mode DSP) |

## Birch Stream → Oak Stream migration notes

Teams porting Birch Stream (BHS) platform-management designs should plan for:

1. **New CPU socket and power delivery** — LGA 9324 changes HPM layout and sequencing
2. **eSPI / sideband changes** — re-verify against Diamond Rapids documentation
3. **Higher host PCIe generation** — management devices stay on PCIe 4.0; review switch
   topology
4. **Agilex 5 upgrade from MAX 10** — budget for Quartus Pro, SDM signing infrastructure,
   and HPS software stack if moving PRoT to Agilex 5
5. **LTPI interoperability** — HPM and SCM may use different FPGA families; validate
   cross-family LTPI links early
6. **CXL and memory** — 16-channel MRDIMM configurations affect board size and DC-SCM
   placement; confirm mechanical constraints

## Common pitfalls

- **Assuming Oak Springs Canyon guidance applies** — that IPU uses Agilex 7 FPGAs in a
  SmartNIC/DPU context, not DC-SCM platform management.
- **Using Cyclone V for LTPI** — not supported; see the LTPI on Cyclone V guide for
  alternatives.
- **Mixing Quartus Standard and Pro IP** — Agilex 5 and LTPI require Quartus Prime Pro.
- **Skipping SDM signing in production** — unsigned bitstreams defeat PRoT trust claims.
- **Treating pre-release Oak Stream specs as final** — socket, memory channel count, and
  launch dates may change before production RVPs ship.

## References

| Document | URL |
| --- | --- |
| Agilex 5 product overview | https://www.altera.com/products/fpga/agilex/5 |
| Agilex 5 device data sheet (813918) | https://docs.altera.com/r/docs/813918/current |
| Platform management solution brief (MAX 10 + Agilex 5) | https://docs.altera.com/api/khub/documents/cHdlwLWfSYL8G69RHjKTXg/content |
| LTPI IP User Guide | https://docs.altera.com/r/docs/844310/current |
| OCP DC-SCM 2.0 LTPI specification | https://www.opencompute.org/documents/ocp-dc-scm-2-0-ltpi-ver-1-0-pdf |
| OCP DC-MHS / modular hardware | https://www.opencompute.org/wiki/Server/DC-MHS |
| Agilex 5 E-Series GSRD | https://github.com/altera-fpga/agilex5e-ed-gsrd |
| Agilex 5 E-Series GSRD user guide | https://altera-fpga.github.io/latest/embedded-designs/agilex-5/e-series/premium/gsrd/ug-gsrd-agx5e-premium/ |
| Agilex 5 white paper (Intel 764697) | https://cdrdv2-public.intel.com/764697/agilex-5-fpga-whitepaper.pdf |
| Intel OCP modular hardware story | https://www.intel.com/content/www/us/en/customer-spotlight/stories/open-compute-project-customer-story.html |
