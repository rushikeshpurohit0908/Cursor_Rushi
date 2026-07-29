# CvP: Using Avalon-ST Mode for the Peripheral (Periphery) Image

This guide explains how to configure Intel FPGA **Configuration via Protocol
(CvP)** so that the *periphery image* loads through the **Avalon Streaming
(Avalon-ST, "AVST x8")** configuration scheme instead of Active Serial (AS)
x4. It is an implementation guide for the Quartus Prime Pro Edition CvP flow
(Stratix 10 / Agilex device families with the Secure Device Manager) and
assumes you already have a working PCIe Hard IP + CvP design targeting
Active Serial. It does not replace the Intel/Altera CvP Implementation User
Guide for your specific device family.

## 1. Background: periphery image vs. core image

CvP splits a single design into two separately-generated images:

| Image | Contents | Where it lives | How it loads |
| --- | --- | --- | --- |
| **Periphery image** | The static CvP/PCIe Hard IP periphery only. Cannot be partially reconfigured. | Local configuration device (flash) *or* streamed by an external controller | Active Serial x4 (fast mode) **or** Avalon-ST x8 |
| **Core image** | Everything else in the design (the reconfigurable fabric). | Host memory | PCIe link, after the periphery is up |

Sequence for CvP Initialization mode, independent of which scheme loads the
periphery image:

1. FPGA powers up and loads the periphery image (AS x4 or Avalon-ST x8).
2. `CONF_DONE` goes high once the periphery image finishes loading.
3. The PCIe Hard IP in the periphery trains the PCIe link (REFCLK must
   already be running).
4. The link reaches L0 and the host enumerates the device.
5. The host (via the CvP driver) pushes the core image over the PCIe link.
6. `CVP_CONFDONE` goes high; if `INIT_DONE` is enabled it also asserts, and
   the FPGA enters user mode with the PCIe link available for normal
   application traffic.

Only step 1 changes between AS x4 and Avalon-ST x8 — everything else in the
CvP sequence is identical.

## 2. Why choose Avalon-ST x8 for the periphery image

Use Avalon-ST x8 instead of AS x4 when any of the following apply:

- Your board has **no local configuration flash** for the periphery image
  (or you want to remove it from the BOM) and instead have a
  microcontroller, CPLD, or other FPGA that can actively drive configuration
  data into the target device.
- Your system **cannot meet the Active Serial timing/voltage requirements**
  (e.g., the AS x4 fast-mode power ramp and clock requirements are hard to
  satisfy on your board).
- You want an **external configuration controller** to own and update the
  periphery bitstream (for example, downloading it over a management
  network) rather than programming an on-board QSPI device.

Avalon-ST x8 is a *passive* configuration scheme: the FPGA is the target and
an external controller drives the data and clock into the device. Active
Serial is *active*: the FPGA itself drives the SPI clock and pulls data out
of flash. This is the key practical trade-off — with Avalon-ST you must
provide (and control the timing of) an external configuration master.

## 3. Prerequisites

- Quartus Prime Pro Edition with support for your device family (Stratix 10
  or Agilex).
- An existing design that already instantiates the Avalon-ST Hard IP for PCI
  Express with CvP enabled ("Enable CVP (Intel VSEC)" on the IP's Top-Level
  Settings / PCIe VSEC tab, depending on tile type).
- An external configuration controller capable of driving the Avalon-ST x8
  configuration interface (SDM dedicated I/O pins) at the required data
  rate, since the device cannot source its own configuration clock in this
  scheme.
- Board wiring for the CvP status pins (`CONF_DONE`, `INIT_DONE`,
  `CVP_CONFDONE`) connected to your external configuration controller so it
  can sequence the load and the host can observe completion.

## 4. Quartus Prime settings

### 4.1. Device and Pin Options

1. **Assignments → Device → Device and Pin Options.**
2. Under **Category → Configuration**:
   - **Configuration scheme**: select **AVST x8** (instead of *Active Serial
     x4 (can use Configuration Device)*).
   - **Configuration pin**: open **Configuration Pin Options** and enable
     **USE CONF_DONE output** and **USE CVP_CONFDONE output**.
3. Under **Category → CvP Settings**:
   - **Configuration via Protocol**: select **Initialization and update**
     (or **Initialization only**, depending on whether you also need CvP
     Update mode).
4. Click **OK** and recompile.

Because Avalon-ST x8 does not use a QSPI configuration device, you do not
need to set "Use configuration device" the way you would for AS x4 — that
option is specific to Active Serial.

### 4.2. MSEL / configuration-scheme selection

The device samples `MSEL[2:0]` at power-up to determine which configuration
scheme to use. Set the board's MSEL strapping (DIP switch, resistor straps,
etc.) to match Avalon-ST x8:

| Configuration scheme | `MSEL[2:0]` |
| --- | --- |
| AS (fast mode — for CvP) | `001` |
| **Avalon-ST x8 (for CvP)** | **`110`** |

Confirm the exact encoding against your device family's configuration user
guide — the values above are for Stratix 10; verify Agilex/Arria 10 tables
before wiring a new board, as MSEL encodings are device-family specific.

### 4.3. Generating the periphery programming file

1. After compiling and generating the `.sof`, open **File → Programming
   File Generator**.
2. Set **Device family** to your target device.
3. Set **Configuration mode** to **AVST x8**.
4. On the **Output Files** tab:
   - Select **Raw Binary File for CvP Core Configuration (.rbf)** — this is
     still how the *core* image is produced, unchanged from the AS flow.
   - For the periphery image, select **Programmer Object File for Periphery
     Configuration (.pof)**. (Use *JTAG Indirect Configuration File (.jic)*
     only for Active Serial; `.pof` is the Avalon-ST periphery output.)
5. On the **Input Files** tab, add the `.sof` you just generated.
6. Generate the files. Deliver the resulting `.pof` to your external
   configuration controller's storage/loader rather than to an on-board
   flash programmer.

## 5. Bring-up sequence with an external controller

Because Avalon-ST x8 is passive, your external configuration controller (not
the FPGA) drives the load:

1. Power up the board; hold the FPGA in its reset/config-idle state until
   the controller is ready.
2. Have the controller stream the periphery `.pof` contents into the FPGA
   over the Avalon-ST x8 configuration interface.
3. Monitor `CONF_DONE` (wired to the controller, and optionally to a host
   GPIO) to detect periphery-load completion.
4. Ensure the PCIe REFCLK is already free-running before/while the periphery
   loads, since the PCIe Hard IP begins link training immediately after
   `CONF_DONE` asserts.
5. Let PCIe link training and enumeration proceed; the CvP driver on the
   host then loads the `.core.rbf` image over the PCIe link exactly as it
   would in the AS x4 flow.
6. Confirm `CVP_CONFDONE` (and `INIT_DONE`, if used) assert, indicating full
   configuration and user-mode entry.

## 6. Common pitfalls

| Symptom | Likely cause |
| --- | --- |
| `CONF_DONE` never asserts | External controller isn't actually driving the Avalon-ST x8 interface, or MSEL isn't strapped to the Avalon-ST encoding |
| PCIe link never trains | REFCLK not running/stable before or during periphery load |
| PCIe enumerates but core image load fails/times out | `.core.rbf` was built from a `.sof` that doesn't match the currently loaded periphery image |
| Works with AS x4 in the lab but not on the new board | Board MSEL straps, or CvP status pin wiring (`CONF_DONE`/`CVP_CONFDONE`/`INIT_DONE`) to the external controller, weren't updated for the new scheme |
| Periphery loads but very slowly / intermittently | External controller's Avalon-ST clocking/timing doesn't meet the interface's required data rate |

## 7. Switching back to Active Serial

Avalon-ST x8 and AS x4 are alternative periphery-load mechanisms for the
same CvP Initialization mode; they are not mutually exclusive at the design
level. To revert, change the **Configuration scheme** back to *Active Serial
x4 (can use Configuration Device)* in Device and Pin Options, re-strap MSEL
to `001`, regenerate the `.jic` (instead of `.pof`) periphery file, and
reprogram your on-board configuration device.

## References

- Intel/Altera *Stratix 10 Configuration via Protocol (CvP) Implementation
  User Guide* — periphery/core image split, `AVST x8` configuration scheme,
  MSEL table, Programming File Generator steps for `.pof` vs `.jic`.
- Intel/Altera *Agilex 7 Device Configuration via Protocol (CvP)
  Implementation User Guide* — Avalon-ST (AVST) interface notes, external
  configuration controller wiring for `CONF_DONE`.
- Intel/Altera *Stratix 10 Configuration User Guide* — Avalon-ST configuration
  scheme description (passive, x8/x16/x32 modes) and CvP mode overview.
