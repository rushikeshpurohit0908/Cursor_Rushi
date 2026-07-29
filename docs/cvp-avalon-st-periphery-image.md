# CvP, Avalon-ST, and the Periphery Image

## Short answer

Do not select the passive Avalon Streaming (Avalon-ST) configuration scheme to
load a CvP periphery image in a current Stratix 10 or Agilex CvP
initialization design.

The supported flow documented for these devices is:

```text
QSPI flash
  └─ Active Serial x4 (Fast mode) ─> static periphery image
                                         │
                                         └─ PCIe link trains and enumerates
                                                │
host memory ───────────── PCIe CvP ─────────────┘
  └─ core image
```

An Avalon-ST PCIe IP can still be used. In that case, Avalon-ST is the
application-facing TLP interface of the PCIe IP; it is not the interface that
loads the periphery image. The official term is **periphery image**, not
“peripheral image.”

This distinction matters because “Avalon-ST” can refer to two unrelated
interfaces:

| Name | Purpose | Role in the current CvP initialization flow |
| --- | --- | --- |
| Avalon-ST PCIe application interface | Transfers application TLPs between the PCIe Hard IP and FPGA fabric | The CvP-capable Endpoint IP is included in the periphery; enable its Intel VSEC |
| Avalon-ST FPGA configuration scheme | A passive pin-level interface driven by an external configuration host | Not the documented periphery-image boot scheme; use AS x4 Fast mode |

## Scope

The concrete settings below are based on the current online implementation
guides for:

- Stratix 10 with Quartus Prime Pro Edition 22.4; and
- Agilex 7 with the P-Tile, R-Tile, or F-Tile Avalon Streaming IP for PCI
  Express.

Other families and older Quartus releases have different CvP restrictions,
eligible PCIe Hard IP locations, register maps, and host drivers. Confirm the
device-family CvP guide before applying these settings. In particular, the
Stratix 10 CvP guide's revision history records that Avalon-ST x8
configuration support was removed. Do not recover an archived Avalon-ST
periphery flow unless the exact device, Quartus release, and archived guide
all require it.

## Configure the design

### 1. Configure the PCIe Endpoint

1. Instantiate a PCIe **Endpoint**, not a Root Port.
2. Select the supported PCIe Hard IP and location for the target device.
3. Enable **CVP (Intel VSEC)** in the PCIe IP parameters:
   - P-Tile and R-Tile: enable it under **Top-Level Settings**.
   - F-Tile: enable it under
     **PCIe0 Settings → PCIe0 PCI Express/PCI Capabilities → PCIe0 VSEC**.
4. Generate the synthesis design and make the target-specific PCIe pin
   assignments.

Choosing an Avalon Streaming PCIe IP here does not create an Avalon-ST
configuration-data path in fabric. CvP traffic is handled by the PCIe
Hard IP/VSEC and the device configuration circuitry. The fabric-side
Avalon-ST application interface is not available until the core image has
been configured and the device reaches user mode.

### 2. Select CvP and the boot scheme

In **Assignments → Device → Device and Pin Options**:

1. Under **Configuration**, select **Active Serial x4 (can use Configuration
   Device)** and choose the board's supported QSPI configuration device.
2. In **Configuration Pin Options**, enable `CONF_DONE`; enable
   `CVP_CONFDONE` when the board exposes or monitors it.
3. Under **CvP Settings**, select **Initialization and update**.

Use the device pin-connection guide and board schematic for QSPI, MSEL,
PCIe reference-clock, reset, and optional status-signal wiring. The PCIe
reference clock must be stable before the periphery image is sent.

### 3. Compile and split the image

Compile the design to a `.sof`, then open
**File → Programming File Generator**:

1. Select the target family and **Active Serial x4** configuration mode.
2. Add the `.sof` as the input bitstream.
3. Select both output types:
   - **JTAG Indirect Configuration File for Periphery Configuration
     (`.jic`)**; and
   - **Raw Binary File for CvP Core Configuration (`.rbf`)**.
4. Add the board's configuration flash device and partition.
5. Generate the files.

The expected outputs are:

```text
<name>.periph.jic  # static image programmed into local QSPI flash
<name>.core.rbf    # core image retained by the PCIe host
```

Generate both files from the same successful compile. Do not combine images
from different builds or Quartus versions.

## Program and boot

1. Program `<name>.periph.jic` into the QSPI configuration device with the
   Quartus Programmer. Programming the FPGA directly over JTAG is not a test
   of the CvP power-up path.
2. Power-cycle the board so the device loads the periphery image from QSPI
   using AS x4 Fast mode.
3. Check that:
   - `CONF_DONE` asserts;
   - the PCIe link reaches L0 at the expected width and rate; and
   - the host enumerates the Endpoint and discovers the CvP VSEC.
4. Make `<name>.core.rbf` available to the host's supported CvP driver.
5. For the upstream Linux FPGA Manager flow documented by the Stratix 10
   guide, place the image in `/lib/firmware` and request it by filename:

   ```sh
   echo <name>.core.rbf \
     > /sys/kernel/debug/fpga_manager/fpga0/firmware_name
   ```

   Run this with the required administrative privileges. The exact sysfs or
   debugfs path and command can differ with the kernel and device family, so
   follow the matching driver's documentation rather than substituting a
   command from another CvP generation.
6. Check that `CVP_CONFDONE` and then `INIT_DONE` assert when those signals
   are enabled, and verify the driver log reports successful completion.
7. Only after the device reaches user mode should application logic consume
   or produce TLPs through the PCIe IP's fabric-side Avalon-ST interface.

## Acceptance checklist

- [ ] The target family and Quartus version have been recorded.
- [ ] A supported PCIe Endpoint and Hard IP location are used.
- [ ] **Enable CVP (Intel VSEC)** is selected.
- [ ] CvP is set to **Initialization and update**.
- [ ] The periphery boot scheme is **Active Serial x4 (Fast mode)**.
- [ ] The `.periph.jic` and `.core.rbf` come from the same compile.
- [ ] A power cycle loads the periphery image from QSPI.
- [ ] PCIe reaches L0 and enumerates before the core transfer starts.
- [ ] The matching family driver loads `.core.rbf` through PCIe CvP.
- [ ] User logic remains reset or quiescent until user mode.

## If passive Avalon-ST configuration is a hard requirement

Treat that as a different system architecture, not as a drop-in transport
change for the flow above. Passive Avalon-ST configuration is a standalone
configuration scheme in which an external controller drives `AVST_DATA`,
`AVST_VALID`, and a continuous `AVST_CLK`, while honoring `AVST_READY`
backpressure. It normally transfers a tool-generated configuration stream
through dedicated or dual-purpose configuration pins.

Before using it, obtain an explicit statement of support for the combination
of:

- exact FPGA ordering code;
- exact Quartus Prime version;
- CvP initialization mode;
- Avalon-ST width; and
- required PCIe wake-up timing.

Without that family-and-release-specific support, choose one of these
documented architectures:

1. **CvP initialization:** AS x4 Fast mode for the periphery image, then PCIe
   for the core image.
2. **Standalone passive configuration:** Avalon-ST for a full configuration,
   without assuming the CvP image split applies.

## References

- Altera, [Stratix 10 CvP: CvP Initialization
  Mode](https://docs.altera.com/r/docs/683704/22.4/stratix-10-configuration-via-protocol-cvp-implementation-user-guide/cvp-initialization-mode)
- Altera, [Stratix 10 CvP: Setting up the CvP Parameters in Device and Pin
  Options](https://docs.altera.com/r/docs/683704/22.4/stratix-10-configuration-via-protocol-cvp-implementation-user-guide/setting-up-the-cvp-parameters-in-device-and-pin-options)
- Altera, [Stratix 10 CvP: Converting the SOF
  File](https://docs.altera.com/r/docs/683704/22.4/stratix-10-configuration-via-protocol-cvp-implementation-user-guide/converting-the-sof-file)
- Altera, [Stratix 10 CvP: Programming CvP
  Images](https://docs.altera.com/r/docs/683704/22.4/stratix-10-configuration-via-protocol-cvp-implementation-user-guide/programming-cvp-images)
- Altera, [Stratix 10 CvP: Document Revision
  History](https://docs.altera.com/r/docs/683704/22.4/stratix-10-configuration-via-protocol-cvp-implementation-user-guide/document-revision-history)
- Altera, [Stratix 10 Configuration: Avalon-ST
  Configuration](https://docs.altera.com/r/docs/683762/26.1/stratix-10-configuration-user-guide/avalon-st-configuration)
- Altera, [Agilex 7 CvP: Generating the Synthesis HDL
  Files](https://docs.altera.com/r/docs/683763/23.1/agilextm-7-device-configuration-via-protocol-cvp-implementation-user-guide/generating-the-synthesis-hdl-files)
