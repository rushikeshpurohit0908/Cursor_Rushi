# Architecture

## Layering

```
                +-------------------------------------------------------+
                |                     ltpi_top.sv                       |
                |                                                       |
  gpio_ll_tx -->|--+                                       +----------->|--> gpio_ll_rx
  gpio_nl_tx -->|--|--> ltpi_link_ctrl.sv (training + GPIO) <--+        |--> gpio_nl_rx
                |  |         |            ^                    |        |
                |  v         v            |                    |        |
                | ltpi_frame_tx.sv   ltpi_frame_rx.sv           |        |
                |  |                      ^                    |        |
                |  v                      |                    |        |
                | ltpi_symbol_serializer  ltpi_symbol_align.sv  |        |
                |  |                      ^                    |        |
                +--|----------------------|--------------------+--------+
                   v                      |
              tx_bit (1 bit/clk)     rx_bit (1 bit/clk)
                   |                      ^
        +----------v----------------------|-----------+
        |     rtl/phy/cyclonev/ltpi_phy_cyclonev.sv    |   <- Cyclone V specific
        |   (registered I/O, packed into IOE by the    |
        |    Quartus fitter)                           |
        +-----------------------------------------------+
                   |                      ^
               LVDS TX pins          LVDS RX pins
```

`rtl/common/` (the 8b/10b codec and CRC-8) and `rtl/link/` (serializer,
aligner, frame tx/rx, link FSM) plus `ltpi_top.sv` contain no vendor
primitives at all - only `rtl/phy/cyclonev/` is Cyclone V specific.

## Frame format

Every LTPI frame is 16 bytes, transmitted as one 8b/10b symbol per byte:

| Byte | Content |
| --- | --- |
| 0 | Comma symbol: `K28.5` (Link Detect/Speed), `K28.6` (Advertise/Configure/Accept), or `K28.7` (Operational) |
| 1 | Frame subtype (meaning depends on the comma symbol) |
| 2..14 | Payload (13 bytes) |
| 15 | CRC-8 over bytes 1..14 |

In the RTL, bytes 1..14 (14 bytes = `FRAME_PAYLOAD_BYTES`) are carried as a
single packed bus `frame_bytes[FRAME_PAYLOAD_BITS-1:0]` where byte *i*
(`i = 0..13`, i.e. frame byte `i+1`) occupies bits `[i*8 +: 8]`. A packed bus
was used instead of an unpacked byte array at module boundaries because some
simulators (Icarus Verilog, notably) do not reliably connect unpacked array
ports across module instances - packed buses are unambiguous and also the
safer choice for real synthesis tool portability.

For the `Default I/O Frame` (Operational, subtype 0x00) used by the GPIO
channel:

| `frame_bytes` index | Frame byte | Content |
| --- | --- | --- |
| 0 | 1 | Frame subtype (`0x00`) |
| 1 | 2 | Frame counter |
| 2 | 3 | Low-Latency GPIO byte 0 (implemented: 8 LL GPIOs) |
| 3 | 4 | Low-Latency GPIO byte 1 (reserved, always 0) |
| 4 | 5 | Normal-Latency GPIO byte 0 (implemented: 8 NL GPIOs) |
| 5 | 6 | Normal-Latency GPIO byte 1 (reserved, always 0) |
| 6 | 7 | UART0/1 (reserved, always 0 - extension point) |
| 7..9 | 8..10 | I2C/SMBus0..5 (reserved, always 0 - extension point) |
| 10..13 | 11..14 | OEM (reserved, always 0) |

## 8b/10b codec

`rtl/common/encoder_8b10b.sv` / `decoder_8b10b.sv` implement the classic IBM
(Widmer & Franaszek) 8b/10b coding scheme for all 256 data characters plus
only the three control characters LTPI actually uses (K28.5/K28.6/K28.7).
The 5b/6b and 3b/4b sub-tables (and the documented x=7 / y=3 / K.x.5 / K.x.6
"looks-balanced-but-isn't" exceptions) are taken directly from the publicly
documented coding tables (see [`REFERENCES.md`](REFERENCES.md)); `tb_8b10b.sv`
cross-checks the K28.5/K28.6/K28.7 bit patterns this implementation produces
against independently published values, and round-trips all 256 byte values
at both running-disparity states.

## Bit/frame alignment strategy

`ltpi_symbol_align.sv` searches every bit position of the incoming serial
stream for any of the six known 10-bit comma patterns (K28.5/6/7 x 2
polarities). Once found, it **stops searching** and simply free-runs a
divide-by-10 counter to keep emitting aligned 10-bit symbols.

This is a deliberate design choice, not a simplification for its own sake:
K28.7 (used by every Operational frame) does not have the same
"cannot appear at a misaligned bit offset" guarantee that K28.5/K28.1 have -
combined with certain neighbouring symbols it can form a false comma pattern
straddling a real symbol boundary (a documented property of 8b/10b; see
`ltpi_symbol_align.sv`'s header comment and `REFERENCES.md`). Continuously
re-triggering resync on every comma sighting (which was the first, naive
implementation attempted here) causes exactly this failure mode once real
K28.7 Operational traffic starts flowing, as confirmed by
`sim/tb_symbol_align.sv` during development. Locking once (during the
K28.5-based Link Detect/Speed stage, before any K28.7 traffic exists) and
then trusting the established phase avoids the issue entirely; a lost lock
(e.g. after a cable disconnect) is recovered by resetting `ltpi_symbol_align`
- current wiring does this by regenerating a full reset via the link FSM's
Link Lost -> retrain path together with an upstream reset, since the
simplified single-clock design shares one reset domain end to end. A
production integration with an independent RX PLL should route that PLL's
own lock/reset into `ltpi_symbol_align`'s reset directly.

## Link training state machine

`ltpi_link_ctrl.sv` implements Detect -> Speed -> Advertise -> Configure ->
Accept -> Operational. Both link partners run the identical FSM; each stage
requires `TRAIN_GOOD_FRAMES` (3) consecutive, CRC-correct received frames
matching the *local* current stage before advancing. This assumes both sides
begin training at roughly the same time (the normal LTPI bring-up scenario).
A peer that is already further ahead when the local side starts is **not**
specially fast-forwarded to in this implementation - a real capability
negotiation engine would need to reconcile "my stage" vs. "peer's observed
stage" explicitly; this is called out in `ltpi_link_ctrl.sv`'s header comment
as a known extension point.

Once Operational, `LINK_LOST_CRC_ERRORS` (3) consecutive CRC failures trigger
a return to the Detect stage (link retrain), matching the spirit of the
specification's Link Lost handling (simplified: the full specification
distinguishes IO-frame-only vs. all-operational-frame CRC error counters).

## Clock domain simplification (single shared `clk`)

`ltpi_top.sv` is written as a single-clock-domain design: the same `clk`
(the LTPI link/bit clock, generated by `cv_pll.sv`) drives both the TX and RX
protocol logic. This is valid and simple when:

- The link partners share a common reference clock (common in DC-SCM
  designs, and always true in `sim/tb_ltpi_top_link.sv`'s back-to-back test),
  or
- The RX bit is re-timed into the local `clk` domain by a receiver PLL that
  locks to the incoming forwarded clock and is frequency-identical (a
  "mesochronous" link) - `ltpi_phy_cyclonev.sv`'s header comment describes
  this option and its 2-flop-synchronizer fallback in more detail.

For a link where the partner's clock is **not** frequency-locked to the
local reference (a genuinely plesiochronous/asynchronous link), the receiver
needs its own independently-generated `clk_link_rx` (from a second PLL locked
to the incoming LVDS clock pin), and `ltpi_frame_rx.sv`'s per-frame outputs
(`frame_valid`, `comma_byte`, `crc_ok`, `frame_bytes`) would need to cross
into the TX/control clock domain. Because these outputs only change once per
~160-bit frame period (far slower than either clock), a simple toggle-based
handshake synchronizer (register the data, toggle a flag, 2-flop-synchronize
the toggle flag, pulse a "new data" indication on the synchronized edge) is
sufficient - no high-throughput FIFO is required. This CDC block is not
included in the current deliverable; adding it is a self-contained,
low-risk follow-up (see `ltpi_frame_rx.sv` for the exact signals to bridge).

## Extension points

- **Higher link speeds / DDR**: replace `ltpi_phy_cyclonev.sv`'s plain I/O
  registers with `altddio_in`/`altddio_out` (2 bits per `clk_link` edge) and
  double `ltpi_symbol_serializer.sv`/`ltpi_symbol_align.sv`'s bit width
  accordingly; `cv_pll.sv` already parameterizes the target link frequency.
- **UART / I2C / SMBus / Data channel tunneling**: the byte positions are
  already reserved in `ltpi_link_ctrl.sv`'s Default I/O Frame packing; add
  channel modules similar in spirit to `ltpi_link_ctrl.sv`'s GPIO handling
  and wire their bytes into the same `tx_frame_bytes`/`rx_frame_bytes` bus.
- **Full NL GPIO virtual-GPIO windowing** (more NL GPIOs than fit in one
  frame, using the Frame Counter to time-multiplex - see the specification's
  section 2.2.1.1) if more than 8 Normal-Latency GPIOs are needed.
- **Real capability negotiation** (Advertise content actually parsed rather
  than assumed) if interoperating with a third-party LTPI implementation
  whose capabilities may differ from this IP's fixed GPIO-only feature set.
