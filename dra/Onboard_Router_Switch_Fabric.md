# Onboard Router / Switch Fabric

Central interconnect in the Ku-band DRA regenerative payload. It sits between the **RX device cluster** (post Low-PHY handoff), the **TX device cluster** (pre Low-PHY framer), and the **Feeder-link stage**.

```
RX cluster (4 devices) ──┐
                         ├──►  Onboard Router / Switch Fabric  ──► Feeder-link stage
TX cluster (5 devices) ──┘              │
                                        └── cross-connect UL↔DL / beam↔beam
```

## Why it exists

This is a **regenerative** (not bent-pipe) payload:

1. Uplink is demodulated / decoded to the Low-PHY handoff on each RX AGRW027/039 (or Agilex 7 in the RFIC option).
2. The fabric **switches packets / transport blocks** — not raw ADC samples.
3. Downlink beams are re-framed and modulated on the TX cluster.
4. The feeder link attaches at the same fabric so gateway traffic and user-beam traffic share one switching domain.

That keeps high-rate Direct-RF sample paths **inside** each RF device and only moves processed user-plane / control-plane traffic across the chassis.

## Topology

| Port group | Endpoints | Role |
|---|---|---|
| RX ports | 4× RX devices (Beams 1–32) | Ingress from DVB-RCS2 / 3GPP-NTN Low-PHY |
| TX ports | 5× TX devices (Beams 1–40 / 1–32) | Egress to DVB-S2X / 3GPP-NTN Low-PHY framer |
| Feeder ports | Feeder-link modem / gateway stage | Ground gateway UL/DL and TT&C overlay |
| Control | HPS / management plane | Telemetry, route tables, beam maps, health |

Recommended logical topology: **non-blocking Clos-style or crossbar fabric** with:

- East-west paths between RX and TX clusters (onboard UL→DL regeneration)
- North-south paths to the feeder-link stage
- Optional multicast / replication for broadcast beams and ephemeris / control floods

Physical implementation options (pick per platform constraints):

1. **Central switch FPGA/ASIC** with many 58G-class SerDes into all device clusters  
2. **Distributed mesh** — each AGRW/Agilex terminates SerDes and participates in a chip-to-chip fabric protocol  
3. **Hybrid** — local RX/TX aggregation switches + spine to feeder

The block diagrams assume a **logical central fabric** for clarity; the BOM can be either a dedicated switch device or fabric IP spread across the device HPS/FPGA fabric.

## SerDes & link class

| Item | Spec |
|---|---|
| Line-rate class | **58 Gbps-class SerDes** (PAM4), Altera F-tile / equivalent |
| Encoding | 64b/66b or 256b/257b PCS as used by the chosen chip-to-chip / Ethernet-lite stack |
| Reach | Short-reach onboard (backplane / cable assembly / MCM) |
| Sync | Shared reference clock + deterministic latency where needed for timing-sensitive control |
| Redundancy | 1+1 or N+1 spare lanes per trunk for SEU / link failure |

“58 Gbps” in the architecture is the **SerDes lane class**, not a single aggregate number for the whole payload. Aggregate fabric capacity is **lanes × ports × efficiency**.

### Example port plan (Direct-RF SoC option)

| Link | Suggested lanes | Notes |
|---|---|---|
| Each RX device ↔ fabric | 2–4 × 58G | Sized to post-Low-PHY UL user + control traffic |
| Each TX device ↔ fabric | 2–4 × 58G | Sized to DL framer input (+ replication headroom) |
| Fabric ↔ feeder stage | 4–8 × 58G | Gateway aggregate + protection |
| Fabric control / debug | 1–2 × lower-rate | Or out-of-band Ethernet / PCIe |

Exact lane counts are closed after traffic engineering (modulation, coding, duty cycle, overbooking).

## Traffic classes

| Class | Direction | Content | Priority |
|---|---|---|---|
| User plane | RX→TX, RX→Feeder, Feeder→TX | Demodulated packets / TBs after Low-PHY | High, rate-shaped per beam |
| Control plane | Bidirectional | Beam maps, ACM commands, RRC-like NTN signaling | Highest |
| Sync / timing | Fabric-wide | Timing packets, beam hop schedules | Highest / reserved |
| Telemetry | Devices→Feeder/HPS | Health, SERDES BER, thermal, HPS logs | Best effort / dedicated queue |
| Multicast | Fabric→TX set | Broadcast / group beams, ephemeris | Configurable |

Queuing: strict priority for control/sync, then shaped user queues per beam or per SLA color (fits 4-color reuse bookkeeping).

## Switching functions

1. **UL→DL cross-connect** — regenerative forwarding between uplink beams and downlink beams (beam-to-beam mesh).  
2. **Feeder gateway** — concentrate user traffic to/from the ground gateway modem.  
3. **Beam remap** — update forwarding tables when the DRA steers or recolors beams.  
4. **Load balance / spare** — steer around a failed TX/RX device; align with Device 5 spare DAC channels in DVB-S2X-only mode.  
5. **Replication** — 1:N for broadcast / NTN SIB-like content.  
6. **Isolation** — keep RX and TX RF silicon separate while still allowing digital cross-connect (cleanest TX→RX RF isolation preserved).

## Bandwidth sketch (order-of-magnitude)

Fabric carries **post-demod** traffic, not 64 Gsps samples.

| Path | Drivers | Implication |
|---|---|---|
| UL ingress | 32 beams × (up to 4 × 125 MHz channels) after RCS2/NTN decode | Aggregate user bits ≪ RF sample rate |
| DL egress | 40 (NTN) or 32 (DVB-S2X) beams after framing | Slightly higher if DL ACM denser than UL |
| Feeder | Gateway mirror of aggregate user + overhead | Often the fattest single trunk |
| Overhead | Headers, ACM, ARQ/HARQ meta, encryption, FEC pad | Plan ~20–40% on top of user bits |

58G-class multi-lane trunks are chosen for:

- Headroom under peak ACM  
- Link aggregation / failover  
- Future beam-count growth without respining the backplane

## Control plane

Each RF/DSP device already has a **Quad-core Arm Cortex-A53 (HPS)** for local control. The fabric adds:

| Function | Owner |
|---|---|
| Route / beam forwarding tables | Fabric controller (+ ground via feeder) |
| SerDes bring-up, eye / BER monitors | Fabric + device HPS |
| Phase-sync coordination across cluster | Device phase-sync IP; fabric carries sync messages if needed |
| FDIR (fault detection, isolation, recovery) | HPS cluster + fabric manager |
| Software loads / configs | Feeder → fabric → device HPS |

## Mapping to both architecture options

| Option | Fabric attachment |
|---|---|
| **A — Direct-RF AGRW027/039** | SerDes from each of 9 devices into fabric; Low-PHY already on-device |
| **B — Agilex 7 + TI AFE7950** | SerDes from each of 9 Agilex 7 FPGAs into fabric; JESD204C stays local to each FPGA↔AFE slot |

In both cases the fabric sees the **same logical ports** (4 RX + 5 TX + feeder). Only the device that terminates Low-PHY changes.

## Design checklist

- [ ] Confirm regenerative vs partial-regenerative (which OSI/3GPP layers terminate onboard)  
- [ ] Close per-beam peak / average rates for RCS2 and NTN profiles  
- [ ] Size RX/TX/feeder lane counts with failover  
- [ ] Define cell/packet format (custom vs RoE/eCPRI-like vs Ethernet + custom ethertype)  
- [ ] QoS / color-aware scheduling aligned with 4-color reuse  
- [ ] SEU-hardened tables and scrubbing for route state  
- [ ] Keep RF TX/RX silicon split; only digital meets at the fabric  

## Related slides / diagrams

- Block diagram callout: `dra/block_diagram.svg` (center bar)  
- Editable overview slide: `dra/DRA_Architecture_Editable_Slide.pptx`  
- Fabric deep-dive slides: `dra/DRA_Fabric_Editable_Slides.pptx`
