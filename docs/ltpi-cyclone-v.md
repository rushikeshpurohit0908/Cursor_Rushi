# LTPI on Cyclone V

## Support status

Cyclone V is **not a supported target** for Altera's LVDS Tunneling
Protocol and Interface (LTPI) IP. The Quartus IP Catalog core cannot be
generated for a Cyclone V part.

As of the Quartus 26.1 LTPI IP User Guide, the supported families are:

| Device family | Official LTPI IP support |
| --- | --- |
| Agilex 3 | Yes |
| Agilex 5 | Yes |
| MAX 10 | Yes |
| Cyclone V | **No** |

This is a device-support restriction, not just a missing Quartus project
setting. The delivered core includes family-specific clocking and LVDS PHY
integration. Selecting a Cyclone V device or editing generated metadata does
not produce a supported or validated implementation.

## Recommended solution

Use a supported MAX 10, Agilex 3, or Agilex 5 device for the LTPI endpoint.
MAX 10 is usually the closest replacement when the endpoint is intended to be
a small SCM-side FPGA/CPLD and the rest of the design uses Quartus Prime
Standard Edition.

If Cyclone V is a fixed requirement, choose one of these paths:

1. Ask the Altera LTPI IP owner for a supported Cyclone V deliverable.
2. Put the LTPI endpoint in a supported companion device and connect that
   device to Cyclone V through a local GPIO, I2C, SPI, or Avalon interface.
3. Develop a new OCP DC-SCM 2.0 LTPI 1.0 implementation, including a Cyclone V
   PHY. This is a protocol implementation project, not a port of the encrypted
   Altera core.

Do not plan a product around retargeting generated LTPI files from MAX 10 or
Agilex. Such a build is unsupported, and its PHY, PLL, reset, and timing
assumptions are device-specific.

## What LTPI must implement

LTPI tunnels low-speed platform interfaces between the Host Platform Module
(HPM) and Secure Control Module (SCM) over source-synchronous LVDS links.

```text
 HPM endpoint                                      SCM endpoint
┌───────────────┐     TX clock pair ───────────>  ┌───────────────┐
│ LTPI          │     TX data pair  ───────────>  │ LTPI          │
│ controller or │                                  │ controller or │
│ target        │  <──────────── RX clock pair     │ target        │
│               │  <──────────── RX data pair      │               │
└───────────────┘                                  └───────────────┘
```

The protocol requirements include:

- four differential links: forwarded clock and data in each direction;
- independent local transmit and receive clocks;
- 8b/10b encoding and decoding with running-disparity checks;
- fixed 16-symbol frames (160 serial bits after 8b/10b encoding);
- comma detection, symbol alignment, CRC-8 generation, and CRC checking;
- link detect, speed negotiation, capabilities exchange, configuration,
  acceptance, operational, and fault-recovery states;
- an SDR base link clock of 25 MHz and negotiation of common speed
  capabilities;
- time-division multiplexing of enabled GPIO, I2C/SMBus, UART, data, and OEM
  channels; and
- control/status registers and robust clock-domain crossings.

Consult the OCP specification for normative bit assignments, reset behavior,
timeouts, CRC parameters, channel semantics, and state transitions. A summary
is not sufficient to create an interoperable endpoint.

## Cyclone V custom implementation architecture

A clean-room implementation should separate the protocol from the device PHY.

```text
                    System/application clock domain
┌──────────────────────────────────────────────────────────────────┐
│ Channel adapters                                                  │
│ GPIO sampling | I2C event relay | UART sampling | Data | OEM     │
├──────────────────────────────────────────────────────────────────┤
│ Capability/CSR registers | link state machine | frame scheduler   │
├──────────────────────────────────────────────────────────────────┤
│ Frame builder/parser | CRC-8 | 8b/10b encoder/decoder             │
└──────────────────────────────┬───────────────────────────────────┘
                               │ asynchronous FIFOs / CDC
                    Receive and transmit clock domains
┌──────────────────────────────┴───────────────────────────────────┐
│ Symbol aligner | bitslip control | serializer/deserializer        │
├──────────────────────────────────────────────────────────────────┤
│ Cyclone V ALTLVDS_TX / ALTLVDS_RX and PLL wrappers               │
└──────────────────────────────────────────────────────────────────┘
```

Recommended source boundaries:

```text
rtl/
  common/
    ltpi_8b10b_encoder.sv
    ltpi_8b10b_decoder.sv
    ltpi_crc8.sv
    ltpi_frame_tx.sv
    ltpi_frame_rx.sv
    ltpi_link_fsm.sv
    ltpi_csr.sv
  channels/
    ltpi_gpio_channel.sv
    ltpi_i2c_channel.sv
    ltpi_uart_channel.sv
    ltpi_data_channel.sv
    ltpi_oem_channel.sv
  cyclone_v/
    ltpi_cyclone_v_phy.sv
    ltpi_cyclone_v_pll.ip
    ltpi_cyclone_v_lvds_tx.ip
    ltpi_cyclone_v_lvds_rx.ip
  ltpi_endpoint.sv
```

Keep family-specific primitives below `ltpi_cyclone_v_phy`. The protocol
testbench should use a behavioral symbol transport so most verification does
not depend on generated Quartus simulation libraries.

## Cyclone V PHY considerations

Cyclone V has dedicated LVDS SERDES circuitry, but the custom PHY must be
characterized for the selected part, speed grade, package, I/O bank, and board.

- Use `ALTLVDS_TX` and `ALTLVDS_RX` generated for the exact Cyclone V part.
- Start with source-synchronous, non-DPA receive mode. Center the forwarded
  receive clock in the incoming data eye using the receiver clock phase setting.
- Use the lowest mandatory LTPI rate first. Add negotiated rates only after
  static timing and hardware margin testing pass.
- Verify that the chosen LVDS pins share a legal bank and clock network.
- Use a PLL and clock source whose frequency, jitter, and duty cycle meet both
  Cyclone V LVDS requirements and the LTPI electrical requirements.
- Implement deterministic reset sequencing and wait for PLL lock before
  releasing serializers, deserializers, symbol alignment, and the link FSM.
- Treat receive data and receive forwarded clock as an independent domain.
  Cross decoded frames or channel updates through explicit CDC structures.
- Constrain the source-synchronous input and forwarded-clock output paths in
  SDC. Do not rely on default timing analysis.

The legal LVDS data rate and serialization factor must be confirmed in the
Quartus parameter editor and Cyclone V device datasheet. They vary by part and
speed grade; a family-level maximum is not a design guarantee.

## Bring-up sequence

For a custom Cyclone V endpoint, use this order:

1. Loop back the Cyclone V LVDS TX/RX PHY and prove stable symbol transfer at
   the mandatory base rate.
2. Verify all legal K and D characters, 8b/10b disparity errors, comma lock,
   bitslip recovery, and loss-of-clock behavior.
3. Verify frame formation and parsing with injected bit, symbol, comma, and CRC
   faults.
4. Connect controller and target behavioral models and complete link detect,
   speed selection, advertise, configure/accept, and operational transitions.
5. Enable only one channel, preferably GPIO, and test it end to end.
6. Add I2C/SMBus, UART, data, and OEM channels independently.
7. Run mixed-channel saturation and fault-recovery tests.
8. Connect to a known-compliant LTPI endpoint and perform interoperability
   tests across voltage, temperature, and clock tolerance.
9. Run board-level eye and jitter measurements at every advertised link speed.

## Verification gates

A Cyclone V implementation should not be called LTPI-compatible until it
passes all of the following:

- protocol assertions and frame-field checks against OCP DC-SCM 2.0 LTPI 1.0;
- 8b/10b exhaustive symbol tests and running-disparity error injection;
- CRC known-answer tests and single/multiple-bit corruption tests;
- all link-state transitions, timeout paths, retraining, and reset cases;
- capability negotiation with unequal endpoint capabilities;
- CDC analysis with no unconstrained crossings;
- clean Quartus compilation with no critical warnings;
- timing closure for every supported operating condition and link rate;
- hardware interoperability with a supported LTPI implementation; and
- channel-specific tests, especially I2C clock stretching and contention.

## Information required before starting RTL

The following choices materially affect the implementation:

- exact Cyclone V ordering code and speed grade;
- HPM or SCM endpoint and controller or target role;
- required LTPI version and conformance profile;
- required GPIO counts and low-latency assignments;
- I2C/SMBus bus count and rates;
- UART count and baud rates;
- data and OEM channel requirements;
- mandatory and optional LTPI link rates;
- board voltage, pinout, reference clocks, and PCB channel constraints; and
- the compliant peer used for interoperability testing.

Without these inputs, only a generic protocol core can be designed; the
Cyclone V PHY and timing constraints cannot be completed.

## References

- [Altera LTPI IP User Guide, current version][ltpi-guide]
- [Altera LTPI device-family support][device-support]
- [Altera LTPI clock topology][clock-topology]
- [Altera LTPI frame format][frame-format]
- [OCP DC-SCM 2.0 LTPI 1.0 specification][ocp-spec]
- [Cyclone V Device Handbook][cyclone-v]

[ltpi-guide]: https://docs.altera.com/r/docs/844310/current
[device-support]: https://docs.altera.com/r/docs/844310/26.1/lvds-tunneling-protocol-and-interface-ltpi-ip-user-guide/device-family-support
[clock-topology]: https://docs.altera.com/r/docs/844310/26.1/lvds-tunneling-protocol-and-interface-ltpi-ip-user-guide/clock-topology
[frame-format]: https://docs.altera.com/r/docs/844310/26.1/lvds-tunneling-protocol-and-interface-ltpi-ip-user-guide/ltpi-frame
[ocp-spec]: https://www.opencompute.org/documents/ocp-dc-scm-2-0-ltpi-ver-1-0-pdf
[cyclone-v]: https://docs.altera.com/r/docs/683375/current/cyclone-v-device-handbook-volume-1-device-interfaces-and-integration/lvds-serdes-circuitry
