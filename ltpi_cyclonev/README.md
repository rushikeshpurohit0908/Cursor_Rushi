# LTPI IP for Cyclone V FPGA

A from-scratch, MIT-licensed, synthesizable implementation of **LTPI**
(**L**VDS **T**unneling **P**rotocol & **I**nterface) targeting **Intel/Altera
Cyclone V** FPGAs, together with a self-checking Icarus Verilog simulation
suite and an example Quartus Prime project.

LTPI is the [Open Compute Project](https://www.opencompute.org/) standard
introduced in the **DC-SCM 2.x specification** for tunneling low-speed
management signals (GPIO, UART, I2C/SMBus, and a generic Data channel)
between a Host Processor Module (HPM) and a Secure Control Module (SCM) over
a small number of LVDS pairs, using 8b/10b line coding and 16-byte,
comma-delimited frames. See [`docs/REFERENCES.md`](docs/REFERENCES.md) for
links to the public specification and prior art.

> Cyclone V does not have a vendor-provided LTPI IP core (Intel only ships
> one for Agilex 3/5 and MAX 10). This project fills that gap with an
> independent, clean-room implementation written directly against the public
> OCP LTPI specification.

## What's implemented

| Area | Status |
| --- | --- |
| 8b/10b encoder/decoder | Full 256 D-codes + K28.5/K28.6/K28.7 comma symbols; verified against independently published bit patterns (see [`sim/tb_8b10b.sv`](sim/tb_8b10b.sv)) |
| CRC-8 (poly `x^8+x^2+x+1`, init 0) | Verified against the published CRC-8/SMBUS catalogue check value (see [`sim/tb_crc8.sv`](sim/tb_crc8.sv)) |
| Bit/symbol alignment | Comma-based, self-acquiring on an unknown initial phase; avoids the documented K28.7 false-comma pitfall (see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)) |
| 16-byte frame tx/rx | Comma + 14-byte payload + CRC-8, self-resynchronizing frame boundary detection |
| Link training FSM | Detect -> Speed -> Advertise -> Configure -> Accept -> Operational, with CRC-error-triggered Link Lost / retrain |
| GPIO channel | 8 Low-Latency + 8 Normal-Latency GPIOs tunneled in the Default I/O Frame |
| Cyclone V PHY | Registered I/O for the mandatory baseline rate (25MHz SDR) + `altpll`-based clock generation |
| Quartus project | Example `.qpf`/`.qsf`/`.sdc` targeting a Cyclone V SoC device |

### Scope simplifications (see [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for details and extension guidance)

This is a genuinely working implementation, not a stub, but it deliberately
narrows the full DC-SCM LTPI specification to keep the design auditable and
fully testable without vendor tooling:

- Only the specification's **mandatory baseline speed** (Base Frequency x1,
  25MHz, SDR) is implemented. DDR and higher multiplier rates are a
  documented extension point in the PHY layer.
- **GPIO channel only** end-to-end (8 LL + 8 NL GPIOs). UART, I2C/SMBus, Data
  Channel and OEM fields are framed as reserved/zeroed bytes with the byte
  positions already wired up in `ltpi_link_ctrl.sv`, ready for extension.
- Normal-Latency GPIOs use a direct 1:1 mapping rather than the
  specification's multi-frame "virtual GPIO" windowing scheme (needed only
  when there are more NL GPIOs than fit in one frame).
- Capabilities (Advertise/Configure/Accept) are fixed/hard-coded rather than
  dynamically negotiated - sufficient for two instances of this IP to link
  up with each other, but not a certification-grade capability negotiation
  engine.
- TX and RX are treated as a single shared clock domain (see
  `rtl/phy/cyclonev/ltpi_phy_cyclonev.sv` for the mesochronous-clocking
  assumption and how to extend to a fully asynchronous link partner).

None of this is hidden: every simplification above is called out at its
point of implementation in the RTL comments.

## Directory layout

```
ltpi_cyclonev/
  rtl/
    common/     8b/10b codec, CRC-8, shared package (ltpi_pkg.sv)      - vendor-agnostic
    link/       bit serializer/aligner, frame tx/rx, link training FSM - vendor-agnostic
    ltpi_top.sv top-level LTPI core (bit-serial in/out, GPIO in/out)   - vendor-agnostic
    phy/
      cyclonev/ Cyclone V clock generation (cv_pll.sv) + I/O wrapper   - Cyclone V specific
  quartus/      example Quartus Prime project (.qpf/.qsf/.sdc) + device-level top
  sim/          Icarus Verilog self-checking testbenches + run_all.sh
  docs/         architecture notes and references
```

Everything under `rtl/common/` and `rtl/link/` (plus `rtl/ltpi_top.sv`) is
plain, portable SystemVerilog with **no vendor primitives**, so it simulates
with any simulator and could be re-targeted to other FPGA families by
supplying a different `rtl/phy/<family>/` directory.

## Simulating (no Quartus required)

The protocol/link layer is fully simulatable with the open-source
[Icarus Verilog](https://steveicarus.github.io/iverilog/):

```bash
sudo apt-get install iverilog     # or your distro's equivalent
cd sim
./run_all.sh
```

This builds and runs five testbenches:

1. `tb_crc8.sv` - CRC-8 vs. a software model and a published catalogue vector.
2. `tb_8b10b.sv` - exhaustive 256-byte round-trip at both running-disparity
   states, plus known-good K28.5/K28.6/K28.7 bit patterns.
3. `tb_symbol_align.sv` - bit serializer -> aligner loopback from an unknown
   initial phase.
4. `tb_frame_loopback.sv` - full 16-byte frame tx/rx loopback, including a
   deliberately corrupted frame to confirm CRC failure detection.
5. `tb_ltpi_top_link.sv` - **two `ltpi_top` instances wired back-to-back**,
   verifying complete link bring-up from cold reset (Detect through
   Operational) and bidirectional GPIO tunneling, including a runtime GPIO
   change propagating across the link.

All five pass as of this writing.

## Building for Cyclone V hardware

1. Open `quartus/ltpi_cyclonev.qsf` and update:
   - `DEVICE` to your actual Cyclone V part.
   - The `REF_CLK`/`RESET_N` pin assignments and the LVDS TX/RX pin pair
     assignments (commented out by default - fill in real pin locations and
     confirm the chosen pins are in a true-LVDS-capable I/O bank).
2. Update `quartus/constraints/ltpi.sdc`'s `create_clock` period if your
   board's reference oscillator isn't 50MHz.
3. Regenerate `rtl/phy/cyclonev/cv_pll.sv`'s `altpll` instance via the
   Quartus IP Catalog for your exact device/speed grade (the hand-written
   parameters are a reasonable starting point, not a substitute for
   Quartus-verified PLL settings - see the comments in that file).
4. Open the project in Quartus Prime and compile as usual.

For quick bring-up/testing without a PLL license or IP regeneration step,
instantiate `cv_pll` with `SIM_BEHAVIORAL(1)` to fall back to a simple
integer clock divider (documented in `cv_pll.sv`).

## Extending

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the frame formats,
state machine, clocking assumptions, and a list of concrete next steps
(DDR/higher speed PHY, UART/I2C/SMBus/Data channel tunneling, full capability
negotiation, asynchronous dual-clock RX).

## License

MIT, see [`LICENSE`](LICENSE). This is an independent, clean-room
implementation written directly from the public
[OCP DC-SCM LTPI specification](https://www.opencompute.org/); it does not
reuse code from Intel's, Lattice's, Microchip's or the OCP reference
repository's LTPI IP implementations.
