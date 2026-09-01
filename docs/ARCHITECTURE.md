# Real-Time ANC on Intel Agilex 5 FPGA

Active Noise Cancellation (ANC) reference design for the **Agilex 5 SoC FPGA**
(E-Series 065B Modular Development Kit or a custom carrier with external audio
codec). The design captures noise from a reference microphone, synthesizes
anti-noise through an adaptive **Filtered-x LMS (FxLMS)** filter, and drives
headphones or a speaker in real time.

## Signal flow

```
 Reference mic          Error mic (optional)
      │                        │
      ▼                        ▼
 ┌─────────┐              ┌─────────┐
 │ I2S RX  │              │ I2S RX  │
 │  ch0    │              │  ch1    │
 └────┬────┘              └────┬────┘
      │ x(n)                   │ e_raw(n)
      ▼                        │
 ┌──────────────────────────────────────────┐
 │           FxLMS ANC Engine               │
 │  ┌─────────────┐    ┌─────────────────┐  │
 │  │ Secondary   │    │ Adaptive FIR    │  │
 │  │ Path Model  │───▶│ (256 taps)      │  │
 │  │ (128 taps)  │    │ LMS update      │  │
 │  └─────────────┘    └────────┬────────┘  │
 │                              │ y(n)       │
 └──────────────────────────────┼────────────┘
                                │
      ┌─────────────────────────┘
      ▼
 ┌─────────────┐     ┌──────────────┐     ┌─────────┐
 │ AI Noise    │────▶│ Gain / bypass│────▶│ I2S TX  │──▶ Headphone / speaker
 │ Classifier  │     │  mixer       │     │  DAC    │
 └─────────────┘     └──────────────┘     └─────────┘
      ▲
      │ spectral features (every 512 samples)
      │
 Reference tap
```

## Block descriptions

| Block | File | Function |
| --- | --- | --- |
| Audio clocks | `rtl/audio_clock_gen.v` | Divides system clock to MCLK/BCLK/LRCK for 48 kHz I2S |
| I2S receiver | `rtl/i2s_rx.v` | Deserializes 24-bit stereo/multichannel I2S |
| I2S transmitter | `rtl/i2s_tx.v` | Serializes anti-noise to DAC |
| FxLMS engine | `rtl/fxlms_engine.v` | Adaptive filter + secondary-path model + LMS update |
| FIR MAC | `rtl/fir_mac_engine.v` | Time-multiplexed dot-product for filter taps |
| AI classifier | `rtl/ai_noise_classifier.v` | Band-energy MLP → noise class → step-size scaling |
| Control regs | `rtl/anc_control_regs.v` | AXI4-Lite CSR (bypass, mu, thresholds, status) |
| Top | `rtl/anc_top.v` | Integrates audio, DSP, AI, and HPS-facing CSR |

## Algorithm: Filtered-x LMS

The **FxLMS** algorithm is the industry-standard adaptive filter for ANC
because it accounts for the acoustic secondary path (speaker → air → ear/error
mic):

1. **Reference** signal `x(n)` from the feedforward microphone enters a delay
   line (FIR tap buffer).
2. Each sample, the **adaptive filter** produces anti-noise `y(n) = w^T x`.
3. The **secondary-path model** `Ŝ` (128-tap FIR, trained offline or loaded from
   HPS) filters `x(n)` to produce `x̂(n)` — the predicted signal at the error
   microphone if the adaptive filter were ideal.
4. The **error** signal `e(n)` comes from the error microphone (or is forced to
   zero in feedforward-only mode).
5. **Coefficient update** (one tap per clock cycle, round-robin):
   `w_i ← w_i + μ · e(n) · x̂_i(n)`

Convergence time depends on `μ`, filter length, and secondary-path accuracy.
The AI block adjusts `μ` dynamically based on detected noise class.

## AI processing block

`ai_noise_classifier.v` runs at **1/512 of the audio rate** (~94 Hz at 48 kHz)
to stay off the critical path:

- Computes 8 band-energy features via a lightweight Goertzel bank (125 Hz – 8 kHz).
- Feeds features into a **3-layer quantized MLP** (8→16→4→3) stored as BRAM
  lookup tables — no external DRAM, no HPS involvement during inference.
- Outputs one of three noise classes:

| Class | Typical source | Action |
| --- | --- | --- |
| Tonal | Engine hum, fan whine | Lower μ, narrow-band notch assist |
| Broadband | HVAC, road noise | Standard μ, full-band cancellation |
| Transient | Impacts, speech bursts | Freeze adaptation, fast decay |

The HPS can override the AI decision or load custom MLP weights through the
CSR window.

## Audio I/O interface

Agilex 5 has **no dedicated I2S hard IP**; this design implements a soft I2S
master in fabric. Supported external codecs:

| Codec | Interface | Typical use |
| --- | --- | --- |
| CS5343 + CS4344 | I2S (Pmod I2S2) | Lab prototyping on 065B kit + PMOD |
| SSM2518 | I2S + I2C | Integrated Class-D speaker amp |
| WM8960 | I2S + I2C | Headphone/mic combo |

Default timing: **48 kHz**, **64× BCLK**, **256× MCLK**, Philips I2S format,
24-bit samples, 2–4 TDM slots (ref mic, error mic, aux, loopback).

Pin assignments are in `constraints/anc_pins.qsf` (template — adjust for your
carrier board).

## HPS ↔ FPGA control

Register map (AXI4-Lite, base `0x2000_0000` on LWH2F bridge):

| Offset | Register | R/W | Description |
| --- | --- | --- | --- |
| 0x00 | CONTROL | W | bit0=enable, bit1=bypass, bit2=reset_adapt |
| 0x04 | STATUS | R | bit0=running, bit1=clip, bits[7:4]=AI class |
| 0x08 | MU | RW | LMS step size (Q0.16) |
| 0x0C | SECONDARY_PATH_BASE | RW | BRAM port for Ŝ coefficients |
| 0x10 | ADAPTIVE_W_BASE | RW | BRAM port for w coefficients |
| 0x14 | SAMPLE_COUNT | R | Monotonic processed-sample counter |
| 0x18 | AI_OVERRIDE | RW | Force noise class (0=auto) |
| 0x1C | OUTPUT_GAIN | RW | Q1.15 output gain |

Python helpers live in `software/anc_control/`.

## Latency budget

| Stage | Cycles @ 100 MHz | Time |
| --- | --- | --- |
| I2S RX deserialize | 64 | 640 ns |
| FxLMS filter output | 256 | 2.56 µs |
| I2S TX serialize | 64 | 640 ns |
| **Total end-to-end** | ~384 | **~3.8 µs** |

Well within the ~1 ms acoustic latency budget for headphone ANC.

## Resource estimate (A5ED065, 256-tap adaptive + 128-tap secondary)

| Resource | Estimate |
| --- | --- |
| ALMs | ~4,500 |
| M20K | ~32 |
| DSP (FP mode) | ~48 |
| Fmax (fabric) | >200 MHz with 100 MHz audio clock |

## Directory layout

```
anc_agilex5/
├── rtl/                  SystemVerilog/Verilog sources
├── tb/                   Simulation testbenches
├── constraints/          Quartus pin/timing templates
├── software/anc_control/ HPS Python control utilities
└── docs/                 This file + board integration guide
```

## References

- Altera, *Agilex 5 FPGA and SoC FPGA Overview*: https://www.altera.com/products/fpga/agilex/5
- Kuo & Morgan, *Active Noise Control Systems* (FxLMS foundation)
- Altera Community, *Audio interface with Agilex 5* (I2S soft-IP guidance)
