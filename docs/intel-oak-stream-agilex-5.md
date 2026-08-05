# Intel Oak Stream + Agilex 5

## Short answer

You **can** attach an Agilex 5 FPGA to an Intel **Oak Stream** server, but only
as a **PCIe Gen 4 (or slower) endpoint** in a Gen 6 slot. Oak Stream is the
data-center platform for the **Diamond Rapids** Xeon generation (LGA 9324,
PCIe Gen 6, CXL, up to 16-channel DDR5). **Agilex 5 is a mid-range edge/embedded
FPGA family whose hard PCIe tops out at Gen 4**, so it cannot use the platform's
Gen 6 or CXL bandwidth. It will link-train down to Gen 4 and work, but it is the
wrong device if the goal is a high-bandwidth Oak Stream accelerator.

For a data-center acceleration or CXL card on Oak Stream, use **Agilex 7**
(PCIe Gen 5 / CXL 1.1, up to 116G transceivers) or **Agilex 9**, not Agilex 5.

| Question | Answer |
| --- | --- |
| Does an Agilex 5 card physically fit an Oak Stream PCIe slot? | Yes, PCIe slots are backward compatible. |
| Will it link up? | Yes, it negotiates down to PCIe Gen 4/3/2/1. |
| Can it run at PCIe Gen 6? | No. Agilex 5 hard IP is Gen 4 maximum. |
| Can it act as a CXL device? | No. Agilex 5 has no CXL hard IP. |
| Is Agilex 5 the right device for a Gen 6/CXL Oak Stream accelerator? | No, use Agilex 7 or 9. |

## What each name means

**Oak Stream** is not an FPGA. It is Intel's next-generation server *platform*
for the **Diamond Rapids** (Xeon) generation. Publicly reported platform traits:

- LGA 9324 socket, 1S/2S/4S configurations;
- **PCIe Gen 6** and **CXL** host connectivity;
- up to 16-channel DDR5 (MRDIMM);
- Intel 18A-class process for the Diamond Rapids CPU.

It is the follow-on to the **Birch Stream** platform (Granite Rapids / Sierra
Forest). Treat Oak Stream as "the Gen 6 / CXL Xeon host you plug into."

**Agilex 5** is a mid-range Altera/Intel FPGA and SoC FPGA family aimed at edge,
embedded, and smaller-form-factor designs. Relevant hard-IP limits:

| Feature | Agilex 5 E-Series | Agilex 5 D-Series |
| --- | --- | --- |
| Logic elements | 50k – 656k | 515k – 1,616k |
| Transceivers | up to 24 × 28G | up to 48 × 28G |
| PCIe hard IP | up to **PCIe 4.0 x4** | up to 6 × **PCIe 4.0 x8** |
| Ethernet hard IP | 10/25GbE ×6 | 10/25GbE ×24 |
| Hard processor | Arm Cortex-A55 / A76 | Arm Cortex-A55 / A76 |
| CXL hard IP | none | none |

The decisive point is the PCIe row: **Agilex 5's hard PCIe controller is
Gen 4**. There is no Gen 5, Gen 6, or CXL hard IP in the family.

## Why the pairing is a mismatch for a data-center accelerator

Oak Stream's value in the socket-to-device path is Gen 6 / CXL bandwidth and
memory-coherent attach. An Agilex 5 endpoint gives up all of that:

1. **Bandwidth.** A Gen 6 x16 host link is ~256 GB/s per direction. Agilex 5's
   best case is a single Gen 4 x8 (~16 GB/s per direction). That is roughly an
   order of magnitude below what the slot can carry, so the FPGA becomes the
   bottleneck.
2. **No CXL.** Oak Stream exposes CXL for memory/cache-coherent devices. Agilex 5
   cannot present as a CXL Type 1/2/3 device — it has no CXL hard IP — so
   memory-pooling and coherent-accelerator use cases are off the table.
3. **Target market.** Agilex 5 is optimized for power and size at the edge. Its
   transceivers (28G) and PCIe (Gen 4) are sized for embedded and networking
   edge designs, not for saturating a flagship server slot.

None of this makes the combination *broken*; it makes it *underutilized*. PCIe
is backward compatible, so a Gen 4 endpoint in a Gen 6 slot link-trains to the
highest common speed (Gen 4) and runs normally.

## When the pairing is fine

Pair Agilex 5 with an Oak Stream host when the FPGA's job does **not** depend on
Gen 6 / CXL bandwidth, for example:

- a management, security, or platform-control adjunct (BMC-side, root of trust,
  glue logic, sensor/GPIO aggregation);
- a moderate I/O or protocol-bridging card where Gen 4 x4/x8 is plenty
  (25GbE-class networking, storage front-ends, sensor ingest);
- lab bring-up, prototyping, or software enablement where you already have
  Agilex 5 hardware and only need functional PCIe enumeration;
- a cost- or power-constrained deployment where an Agilex 7/9 card is overkill.

In these roles the Gen 6 slot is simply future-proof headroom you are not using,
which is acceptable.

## Choosing the right FPGA for Oak Stream

If the requirement is "an FPGA accelerator that exploits the Oak Stream host,"
step up the Agilex line:

| Need | Recommended family | Reason |
| --- | --- | --- |
| Edge/embedded, Gen 4 is enough | **Agilex 5** | Lowest power/cost, integrated Arm SoC. |
| Gen 5 / CXL 1.1 accelerator | **Agilex 7** | PCIe Gen 5 hard IP, CXL, up to 116G transceivers. |
| Highest bandwidth / newest interfaces | **Agilex 9** | Top-of-stack transceivers and compute. |

Match the FPGA's PCIe generation to what you actually need from the link, not to
the highest generation the slot supports.

## Practical integration notes (Agilex 5 as a Gen 4 endpoint)

If you do build an Agilex 5 card for an Oak Stream (or any Gen 6) host:

1. **Instantiate the Agilex 5 hard PCIe (P-Tile / R-Tile-class) IP as an
   Endpoint** at the width you need (up to x4 on E-Series, up to x8 on
   D-Series). Do not expect the tool to offer Gen 5/Gen 6 modes — they do not
   exist for this family.
2. **Expect and allow down-training.** The host slot advertises Gen 6; the link
   will settle at Gen 4. Confirm the negotiated speed with `lspci -vv`
   (`LnkSta:` line) once the host boots.
3. **Do not plan on CXL.** If a design review lists CXL/coherent memory as a
   requirement, Agilex 5 disqualifies itself at that step; re-select the device.
4. **Size the DMA/data path to Gen 4.** Buffer, descriptor, and back-pressure
   design should assume the Gen 4 ceiling, not the slot's Gen 6 rating.
5. **Signal integrity / retimers.** A Gen 6 platform's channel budget assumes
   Gen 6 devices; a Gen 4 endpoint is well within margin, but follow the board
   vendor's retimer/AIC guidance for the specific slot.

## Acceptance checklist

- [ ] The workload does **not** require PCIe Gen 5/Gen 6 bandwidth.
- [ ] The workload does **not** require CXL / coherent memory attach.
- [ ] Agilex 5 hard PCIe is configured as an Endpoint at a supported width
      (≤ Gen 4 x4 E-Series, ≤ Gen 4 x8 D-Series).
- [ ] Negotiated link speed verified on the host (`lspci -vv` → `LnkSta`).
- [ ] If any Gen 5/Gen 6/CXL requirement exists, device re-selected to
      Agilex 7 or Agilex 9.

## References

- Altera, *Agilex 5 FPGA and SoC FPGA Overview* (E-Series and D-Series
  feature tables, PCIe 4.0 hard IP, transceiver and Arm SoC specs):
  <https://www.altera.com/products/fpga/agilex/5>
- Public reporting on the Intel **Oak Stream** platform for **Diamond Rapids**
  Xeon (LGA 9324, PCIe Gen 6, CXL, 16-channel DDR5). Oak Stream is a CPU server
  platform, not an FPGA. Confirm final specifications against Intel platform
  documentation when it is released, as pre-launch details can change.
