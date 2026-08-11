# Agilex on the OCP DC-SCM

## Naming

"SC-DCM" is a transposition of **DC-SCM** — the OCP **Datacenter-ready Secure
Control Module**. There is no Altera product called SC-DCM. This note covers
using **Agilex** FPGAs as the programmable device on a DC-SCM (and on the host
board it mates with).

## Short answer

**Agilex 5 E-Series is the intended Agilex device for DC-SCM platform
management**, and it is a supported target for the LTPI IP that carries the
DC-SCM-to-host link. Altera positions MAX 10 and Agilex 5 as its two platform
management families; Agilex 5's advantage is that its Secure Device Manager
lets you **collapse the SCM CPLD and the PRoT/PFR device into one chip**.

| Role on the module | Use | Notes |
| --- | --- | --- |
| SCM FPGA (the "DC-SCM CPLD") | **Agilex 5 E-Series** or MAX 10 | Power sequencing + LTPI tunneling. |
| PRoT / PFR device | **Agilex 5 E-Series** | SDM crypto; can be merged with the SCM FPGA. |
| HPM FPGA (host side) | MAX 10 or **Agilex 5 / Agilex 3** | Platform power sequencing, LTPI, GPIO expansion. |
| Low-cost, I/O-bound, high volume | MAX 10 | Lower power/cost, instant-on, embedded flash. |

Pick Agilex 5 when you want security consolidation, an Arm HPS on the module,
or headroom. Pick MAX 10 when the job is pin count, instant-on, and unit cost.

## What the DC-SCM actually is

The OCP Hardware Management project's DC-SCM specification moves server
**management, security, and control** functions off the processor motherboard
onto a small pluggable module. The motherboard it plugs into is the **HPM**
(Host Processor Module), and the connector between them is the **DC-SCI**
(Datacenter-ready Secure Control Interface).

Per the DC-SCM 2 specification, the module's primary elements are:

- **BMC** — the service processor monitoring the platform;
- **BMC flash** — one or more devices holding BMC firmware;
- **BIOS flash** — one or more devices holding BIOS firmware per node;
- **DC-SCM CPLD** — the programmable device holding application-specific logic
  and the optional LTPI interface (**this is where the Agilex device goes**);
- **RoT security processor** — optional, attests BMC/BIOS/other firmware;
- **TPM** — optional.

The DC-SCI is an **SFF-TA-1002 Type 1 compliant 4C+ connector** (a 4C connector
plus the 28-pin "OCP bay" from OCP NIC 3.0). Note that Type 2 connectors are
explicitly **not** compliant and must not be used for DC-SCM. Defined
mechanical form factors are Horizontal (HFF, split into External EFF and
Internal IFF), Vertical (VFF, short and long), and Compact (CFF).

Because the module must serve diverse platforms over a fixed pinout, DC-SCM 2
introduced **LTPI** to tunnel many low-speed interfaces over a few LVDS pairs,
freeing DC-SCI pins for high-speed per-socket interfaces such as PCIe, eSPI,
and SPI. That tunneling job is the single biggest reason there is an FPGA on
the module at all.

## The four FPGA roles in a managed platform

Altera's platform-management material splits the work across four logical FPGA
roles. One physical device can implement more than one of them:

| Logical FPGA | Functions |
| --- | --- |
| **SCM FPGA** (on the DC-SCM) | DC-SCM power sequencing; DC-SCM LTPI tunneling. |
| **HPM FPGA** (on the host board) | Platform power sequencing; DC-SCM LTPI tunneling; GPIO expansion. |
| **PRoT FPGA** | Platform Root of Trust / Platform Firmware Resilience; authentication and verification; secure update. |
| **BMC FPGA** | Platform boot, telemetry, power and thermal management, firmware updates, out-of-band management. |

The SCM FPGA and HPM FPGA are the two ends of the LTPI link. The PRoT function
is the one most worth folding into the Agilex 5 SCM device.

```text
        DC-SCM module                              HPM (motherboard)
┌──────────────────────────────┐            ┌──────────────────────────────┐
│ BMC   RoT   TPM              │            │  CPU0        CPU1            │
│ BMC flash   BIOS flash       │            │                              │
│                              │            │                              │
│  ┌────────────────────────┐  │  DC-SCI    │  ┌────────────────────────┐  │
│  │  SCM FPGA (Agilex 5)   │  │  4C+       │  │  HPM FPGA              │  │
│  │  - power sequencing    │◄─┼────────────┼─►│  - power sequencing    │  │
│  │  - LTPI tunneling      │  │  LVDS      │  │  - LTPI tunneling      │  │
│  │  - PRoT / PFR (merged) │  │  (LTPI)    │  │  - GPIO expansion      │  │
│  └────────────────────────┘  │            │  └────────────────────────┘  │
└──────────────────────────────┘            └──────────────────────────────┘
        tunneled over LTPI: GPIO, I2C/SMBus, UART, Data, OEM channels
        kept as dedicated DC-SCI pins: PCIe, eSPI, USB, SPI, PECI, SGMII
```

## Why Agilex 5 E-Series for the SCM device

**Security handled in hardened logic.** The Agilex 5 **Secure Device Manager
(SDM)** is a dedicated block with triple-redundant lockstep processors, boot
ROM, sensors, and hardened crypto IP. It provides secure boot, configuration
bitstream authentication (on all Agilex 5 devices), encryption, side-channel
attack protection, integrity checking, attestation via **SPDM**, anti-tamper,
secure key provisioning, and **PUF** key storage. For a module whose entire
purpose is being the platform's trust anchor, getting these from hardened
silicon rather than soft logic is the main argument.

**BOM consolidation.** Those SDM features are what let you implement the SCM
CPLD and the PRoT/PFR function in one Agilex 5 instead of two devices. On a
module that is deliberately small, removing a chip is worth real money and real
board area.

**An Arm HPS on the module.** Agilex 5 SoC FPGA variants carry two Cortex-A76
at 1.8 GHz and two Cortex-A55 at 1.5 GHz, with hard peripherals that map
directly onto DC-SCM plumbing: USB 2.0 and USB 3.1, I2C, I3C, SPI, UART,
10/100/1000 Mbps and 2.5 Gbps Ethernet MAC with TSN, plus DDR4/LPDDR4/LPDDR5
controllers. Several of these are exactly the interfaces the DC-SCI carries.

**Headroom.** PCIe 4.0 connectivity and tensor-mode DSP blocks leave room for
things a plain CPLD cannot do, such as AI-driven predictive failure monitoring
and security anomaly detection.

## Choosing between MAX 10, Agilex 3, and Agilex 5

| Criterion | MAX 10 | Agilex 3 | Agilex 5 E-Series |
| --- | --- | --- | --- |
| LTPI IP support | Yes | Yes | Yes |
| Instant-on / non-volatile | Yes (embedded flash, dual-config RSU) | — | Configuration from external flash |
| Hardened crypto / SPDM attestation / PUF | Limited | — | **Yes (SDM)** |
| Hard Arm processor | No (soft NIOS) | — | **Yes (A76 + A55)** |
| I/O density in small package | 485 I/O in 19 × 19 mm VPBGA (40k/50k LE) | — | Good |
| Cost and power at volume | **Lowest** | Low | Higher |
| Reference-platform validation | Validated for HPM, SCM, and PFR 4.0 designs on Birch Stream reference platforms; HPM FPGA on the BHS+1 reference platform | — | Newer |

Practical reading of that table:

- If the SCM device is mostly sequencing, glue, and LTPI, and you are cost- and
  volume-sensitive, **MAX 10** remains the safe pick — it has the reference
  platform validation history behind it.
- If you want to delete the separate RoT/PFR chip, need attestation and PUF in
  hardened silicon, or want an HPS on the module, use **Agilex 5 E-Series**.
- **Agilex 3** is a valid LTPI target and sits between the two; treat it as the
  option when Agilex-family tooling matters but Agilex 5 is more device than
  the module needs.

Note the instant-on difference. MAX 10 is non-volatile with embedded
configuration flash; Agilex 5 configures from external flash via the SDM. On a
module that gates platform power sequencing, **validate that your Agilex 5
configuration time meets the platform's power-sequencing deadlines** before
committing, and keep the earliest sequencing steps tolerant of that latency.

## The LTPI link

LTPI is the LVDS Tunneling Protocol and Interface that carries GPIO, I2C/SMBus,
UART, data, and OEM channels between the SCM FPGA and the HPM FPGA over
source-synchronous LVDS pairs. DC-SCM 2.2 pairs with **LTPI specification 1.2**.

Both ends must be a supported LTPI IP target:

| Device family | LTPI IP support |
| --- | --- |
| Agilex 3 | Yes |
| Agilex 5 | Yes |
| MAX 10 | Yes |
| Cyclone V | **No** |

If you were considering Cyclone V for either endpoint: it is not a supported
target, and retargeting generated LTPI files from a supported family is not a
viable substitute, because the delivered core's PHY, PLL, reset, and timing
assumptions are device-specific.

The two endpoints do not have to be the same family. A common split is MAX 10
on the HPM and Agilex 5 on the DC-SCM, since the module carries the security
burden and the host side is mostly sequencing and GPIO expansion.

## Design checklist

- [ ] Confirm which DC-SCM revision and form factor you are targeting
      (HFF EFF/IFF, VFF short/long, or CFF) and match the mechanical outline.
- [ ] Use an **SFF-TA-1002 Type 1** 4C+ DC-SCI connector. Do not use Type 2.
- [ ] Decide single-node vs dual-node DC-SCI pinout before pin planning; the
      dual-node definition leans harder on LTPI to free per-socket pins.
- [ ] Choose the SCM device against the table above; explicitly decide whether
      PRoT/PFR is merged into it or kept as a separate chip.
- [ ] Verify both LTPI endpoints are supported families and that the IP
      revision matches the DC-SCM revision (DC-SCM 2.2 → LTPI 1.2).
- [ ] Configure each LTPI instance for its role: HPM vs SCM endpoint, and
      controller vs target.
- [ ] Enable the SDM security features you actually intend to ship — secure
      boot, bitstream authentication, encryption, key provisioning — and plan
      key management before board bring-up, not after.
- [ ] Budget Agilex 5 configuration time against platform power-sequencing
      deadlines.
- [ ] Check the LVDS channel budget across the DC-SCI connector for the
      negotiated LTPI speed.
- [ ] Plan in-field update paths for both the FPGA image and the firmware it
      attests.

## Common pitfalls

1. **Treating the SCM FPGA as a plain CPLD.** It is the platform trust anchor
   and the LTPI endpoint. Sizing it purely on I/O count misses both jobs.
2. **Choosing an unsupported LTPI family.** LTPI IP is not available for every
   Altera family; verify before committing a device to either endpoint.
3. **Mismatched spec revisions.** The DC-SCM revision and the LTPI
   specification version track together. Mixing them breaks interoperability.
4. **Assuming instant-on.** Migrating a MAX 10 sequencing design to Agilex 5
   without re-checking configuration latency can break power sequencing.
5. **Using a Type 2 SFF-TA-1002 connector** because it mechanically mates. The
   specification explicitly excludes it from DC-SCM use.
6. **Deferring security provisioning.** PUF, key provisioning, and attestation
   affect board test and manufacturing flow, not just RTL.

## References

- OCP, *Datacenter Secure Control Module (DC-SCM) Specification*, rev 2.2:
  <https://www.opencompute.org/documents/ocp-dc-scm-rev2-2-ver1-0-pdf>
- OCP, *DC-SCM Specification* rev 1.0 (background):
  <https://www.opencompute.org/documents/ocp-dc-scm-spec-rev-1-0-pdf>
- Altera, *Implementing Data Center Platform Management Using MAX 10 and
  Agilex 5 Devices* (solution brief ss-1167): FPGA roles, Agilex 5 SDM and HPS
  features, MAX 10 reference-platform validation and VPBGA packages.
- Altera, *Device Configuration User Guide: Agilex 5 FPGAs and SoCs* —
  Secure Device Manager:
  <https://docs.altera.com/r/docs/813773/25.1/device-configuration-user-guide-agilextm-5-fpgas-and-socs/secure-device-manager>
- Altera, *Agilex 5 FPGA and SoC FPGA Overview*:
  <https://www.altera.com/products/fpga/agilex/5>
- OCP, *DC-SCM 2.2 LVDS Tunneling Protocol and Interface (LTPI) Specification*
  1.2 — normative LTPI frame, state machine, and channel definitions:
  <https://www.opencompute.org/documents/ocp-dc-scm-2-0-ltpi-ver-1-0-pdf>
