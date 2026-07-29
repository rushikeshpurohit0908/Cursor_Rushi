# CvP Avalon-ST Mode for the Periphery Image

This guide describes how to load the Configuration via Protocol (CvP)
**periphery image** using the **Avalon Streaming (Avalon-ST) x8**
configuration scheme on Stratix 10–class devices. It is an integration
guide based on the public Altera / Intel CvP and configuration user
guides. It does not replace the device-family CvP implementation guide,
pin connection guidelines, or board schematic for your design.

## Important distinction: two Avalon-ST roles

CvP designs mention Avalon-ST in two different places. Do not conflate
them:

| Role | What it is | Used for |
| --- | --- | --- |
| Avalon-ST PCIe Hard IP | Application interface of the CvP-capable PCIe Endpoint IP | Host communication and core-image download over PCIe |
| Avalon-ST x8 configuration scheme | Passive SDM configuration mode (`AVST x8`) | Loading the **periphery image** into the FPGA before PCIe link training |

This document focuses on the second role: using Avalon-ST x8 as the
configuration scheme that delivers the periphery (peripheral) image.

## When to use Avalon-ST for the periphery image

In CvP Initialization mode, the bitstream is split into:

1. **Periphery image** — I/O, SDM-related periphery, and the CvP PCIe
   Hard IP. Loaded first from local storage or an external configuration
   controller.
2. **Core image** — FPGA fabric. Loaded later by the host over PCIe
   (typically as `*.core.rbf` through `/dev/altera_cvp` or an equivalent
   driver).

Stratix 10 CvP Initialization supports periphery delivery through:

- **Active Serial x4 (Fast mode)** — recommended when AS flash and power
  ramp meet the PCIe 100 ms wake-up budget; or
- **Avalon-ST x8** — optional when the board does not support Active
  Serial, or when an external host/bridge already owns an Avalon-ST
  configuration path.

Choose Avalon-ST x8 when:

- the PCB has no usable AS/QSPI boot path for CvP periphery;
- an external microcontroller, CPLD, or host already drives SDM Avalon-ST
  configuration pins; or
- you are validating CvP on a development kit that exposes AVST x8 flash
  programming and you intentionally strap MSEL for Avalon-ST.

AS Fast mode remains the preferred choice when the PCIe enumeration
window is tight, because periphery configuration time dominates the
power-up-to-link-active path.

## Scope and device notes

Verified against public Stratix 10 CvP documentation:

- Device family focus: **Stratix 10** CvP Initialization with
  periphery via **AVST x8**.
- PCIe IP for the CvP Endpoint: instantiate the Avalon-ST Hard IP for
  PCI Express (bottom-left Hard IP block on Stratix 10).
- CvP setting in Quartus: **Initialization and Update**.
- Periphery programming file for AVST: **Programmer Object File**
  (`*.periph.pof` / periphery `.pof`), not the AS `.jic`.
- Core programming file: **Raw Binary File for CvP Core Configuration**
  (`*.core.rbf`).
- MSEL for Avalon-ST x8: **`110`**.

Agilex family CvP guides commonly document Active Serial x4 for
periphery delivery and Avalon-ST PCIe IP for the Endpoint. Do not assume
AVST x8 periphery support on Agilex unless your device-family CvP guide
explicitly lists it.

## End-to-end workflow

### 1. Instantiate Avalon-ST PCIe IP with CvP enabled

1. Open Quartus Prime Pro Edition and Platform Designer.
2. Add **Avalon-ST Intel Stratix 10 Hard IP for PCI Express** (or the
   Avalon-ST PCIe tile IP required by your device).
3. Configure the Endpoint variation for your lane rate and width.
4. Enable CvP / Intel VSEC support as required by the IP parameter
   editor for your Quartus version.
5. Generate synthesis HDL and complete pin assignments for the
   bottom-left CvP-capable Hard IP block.

Other PCIe Hard IP blocks on the device may be used for application
traffic, but only the CvP-capable block participates in periphery-first
CvP Initialization.

### 2. Select Avalon-ST x8 in Device and Pin Options

1. **Assignments → Device → Device and Pin Options**.
2. Category **Configuration**:
   - **Configuration scheme**: `AVST x8` (Avalon-ST x8).
   - Enable **USE CONF_DONE** and **USE CVP_CONFDONE** outputs.
3. Category **CvP Settings**:
   - **Configuration via Protocol**: `Initialization and Update`.
4. Click OK and compile the design to produce the `.sof`.

If you leave the scheme on Active Serial x4, Programming File Generator
will emit a periphery `.jic` path instead of the AVST periphery `.pof`
path described below.

### 3. Convert the SOF into periphery and core images

Use Programming File Generator after a successful compile:

1. **File → Programming File Generator**.
2. Device family: **Stratix 10**.
3. Configuration mode: **AVST x8**.
4. Output files:
   - enable **Raw Binary File for CvP Core Configuration (`.rbf`)**;
   - enable **Programmer Object File for Periphery Configuration
     (`.pof`)** for Avalon-ST mode;
   - optionally enable `.map` / `.rpd` for third-party flash tools.
5. Input Files: add the compiled `.sof`.
6. Configuration Device: add the flash or CFI device used by your AVST
   path, create a partition starting at the address required by the
   board (development-kit AVST examples often use a non-zero start
   address—follow the board user guide).
7. Generate.

Expected artifacts:

```text
<design>.periph.pof     # periphery image for Avalon-ST x8
<design>.core.rbf       # core image for PCIe CvP download
```

Contrast with Active Serial CvP:

```text
<design>.periph.jic     # periphery image for AS x4 flash
<design>.core.rbf       # same core-image role over PCIe
```

### 4. Strap MSEL for Avalon-ST x8

Set `MSEL[2:0] = 110` before power-up so the SDM selects Avalon-ST x8.

| Configuration scheme | MSEL[2:0] |
| --- | --- |
| AS Fast mode (typical CvP default) | `001` |
| Avalon-ST x8 | `110` |

On Stratix 10 development kits this is usually DIP switch SW1. Confirm
the ON/OFF polarity in the kit user guide; switch labels do not always
map 1:1 to logic `1`.

### 5. Program and load the periphery image over Avalon-ST

Avalon-ST is a **passive** scheme: an external agent presents the
periphery bitstream on the SDM Avalon-ST interface.

Typical bring-up on a development kit with AVST-capable flash:

1. Install the Quartus Programmer and FPGA Download Cable driver.
2. Power the board and ensure no other application owns the JTAG chain.
3. Program the periphery `.pof` into the AVST configuration flash with
   the Programmer (kit guides often require lowering JTAG TCK, for
   example to 16 MHz, for reliable large-flash writes).
4. Power-cycle the board with MSEL already set to Avalon-ST x8 so the
   SDM fetches the periphery image through the AVST path.
5. Confirm periphery completion with `CONF_DONE` (and board status LEDs
   if provided).

Custom boards replace the kit flash flow with their own configuration
controller. That controller must:

- hold a stable PCIe reference clock before periphery load begins;
- drive Avalon-ST x8 timing per the Stratix 10 Configuration User Guide;
- monitor `CONF_DONE` / error status before releasing the host to
  enumerate PCIe.

Do not start host CvP core download until periphery configuration has
finished and the CvP-capable Endpoint can train.

### 6. Establish PCIe link and download the core image

After periphery load:

1. The FPGA begins PCIe link training.
2. The link reaches LTSSM L0 and the host enumerates the Endpoint.
3. Install or load the CvP driver (open-source `altera_cvp` or your
   product driver).
4. Copy the core image to the CvP device node, for example:

```bash
cp design.core.rbf /dev/altera_cvp
```

5. Wait for successful completion (`CVP_CONFDONE` / driver status /
   `dmesg`).
6. Enter user mode and run application traffic on the Avalon-ST PCIe
   interface.

The periphery image stays resident. Subsequent **CvP Update** cycles may
replace only the core image, provided every updated core revision keeps
identical periphery connectivity.

## AS x4 versus Avalon-ST x8 for periphery

| Topic | AS x4 Fast mode | Avalon-ST x8 |
| --- | --- | --- |
| Who masters config | FPGA (active) from QSPI/AS flash | External host/bridge (passive) |
| Typical periphery file | `.periph.jic` | `.periph.pof` |
| Quartus configuration scheme | Active Serial x4 | AVST x8 |
| MSEL | `001` | `110` |
| PCIe 100 ms path | Preferred when power ramp meets Fast-mode rules | Use when AS is unavailable; budget carefully |
| Board requirement | AS flash + SDM AS pins | AVST x8 data/control to SDM + controller |

## Design checklist

- [ ] CvP-capable Avalon-ST PCIe Endpoint instantiated on the supported
      Hard IP location.
- [ ] Quartus CvP setting is **Initialization and Update**.
- [ ] Configuration scheme is **AVST x8**, not AS, when targeting this
      periphery path.
- [ ] Programming File Generator mode is **AVST x8** and emits periphery
      `.pof` plus core `.rbf`.
- [ ] Board MSEL strapped to `110` at power-up.
- [ ] PCIe REFCLK is free-running and stable before periphery
      configuration starts.
- [ ] `CONF_DONE` and `CVP_CONFDONE` are brought out for bring-up.
- [ ] Host CvP driver is installed before core `.rbf` download.
- [ ] Any later core update keeps the same periphery interface contract.

## Troubleshooting

| Symptom | Likely cause | What to check |
| --- | --- | --- |
| No PCIe device after power-up | Periphery never loaded or wrong MSEL | MSEL=`110`, AVST controller activity, `CONF_DONE` |
| Programmer generates `.jic` only | Configuration mode left on AS x4 | Set Device and Pin Options and PFG mode to AVST x8 |
| Link trains but CvP core load fails | Driver, Device ID, or VSEC/CvP enablement | `/dev/altera_cvp`, CvP status bits, IP CvP option |
| Enumeration misses 100 ms window | Periphery path too slow or REFCLK late | Start REFCLK earlier; measure periphery time; consider AS Fast mode if available |
| Core update breaks I/O or PCIe | Periphery changed between revisions | Keep periphery static; reflash periphery only when intentionally revised |
| Flash program verifies but boot fails | Wrong partition address or stale MSEL | Match board AVST start address; power-cycle after MSEL change |

## References

- [Stratix 10 Configuration via Protocol (CvP) Implementation User Guide](https://docs.altera.com/r/docs/683704/22.4/stratix-10-configuration-via-protocol-cvp-implementation-user-guide)
- [Stratix 10 Configuration User Guide — Configuration via Protocol](https://docs.altera.com/r/docs/683762/26.1/stratix-10-configuration-user-guide/configuration-via-protocol)
- [Stratix 10 DX FPGA Development Kit — Avalon-ST x8 Configuration Guideline](https://docs.altera.com/r/docs/683561/current/intel-stratix-10-dx-fpga-development-kit-user-guide/avalon-streaming-interface-x8-configuration-guideline)
- Device-family Avalon-ST PCIe IP user guide for your Hard IP tile
- Open-source Linux CvP driver package for `/dev/altera_cvp`
