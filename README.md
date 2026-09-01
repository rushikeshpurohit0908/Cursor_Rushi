# Real-Time ANC on Intel Agilex 5 FPGA

Active Noise Cancellation reference design for the **Intel/Altera Agilex 5 SoC
FPGA**, with microphone input, headphone/speaker output, **FxLMS adaptive DSP**,
and an on-fabric **AI noise classifier**.

## Features

- **Real-time audio I/O** — soft I2S master (48 kHz, 24-bit) for external codecs
  (CS5343/CS4344, SSM2518, WM8960)
- **FxLMS ANC engine** — 256-tap adaptive FIR + 128-tap secondary-path model
- **AI processing** — 8-band Goertzel features + quantized MLP classifies noise
  (tonal / broadband / transient) and adjusts LMS step size
- **HPS control** — Python utilities for enable/bypass, coefficient loading,
  secondary-path calibration, and status monitoring via LWH2F register map
- **Low latency** — ~3.8 µs end-to-end at 100 MHz fabric clock

## Quick start

### Simulation

```bash
cd anc_agilex5/tb
iverilog -o sim ../rtl/fxlms_engine.v ../rtl/secondary_path_fir.v tb_fxlms_engine.v
vvp sim
```

### HPS software (dry-run, no hardware)

```bash
pip install pytest
pytest tests/
python -m anc_control.anc_tuner --monitor
```

### On-board bring-up

1. Wire audio codec per [docs/BOARD_INTEGRATION.md](docs/BOARD_INTEGRATION.md)
2. Build bitstream per [docs/QUARTUS_BUILD.md](docs/QUARTUS_BUILD.md)
3. Calibrate secondary path:
   ```bash
   python -m anc_control.calibrate_secondary --impulse sweep.wav --response error.wav
   python -m anc_control.load_coeffs --secondary secondary_path_coeffs.hex --no-dry-run
   ```
4. Enable ANC:
   ```bash
   python -m anc_control.anc_tuner --no-dry-run --monitor
   ```

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for signal flow, algorithm
details, register map, and resource estimates.

## Directory layout

```
anc_agilex5/
├── rtl/           Verilog sources (I2S, FxLMS, AI classifier, top)
├── tb/            Simulation testbenches
├── constraints/   Quartus pin/timing templates
└── platform/      Platform Designer integration notes
software/anc_control/   HPS Python control utilities
docs/                     Architecture and integration guides
tests/                      Software unit tests
```

## Target hardware

- **Primary:** Agilex 5 E-Series 065B Modular Development Kit (A5ED065BB32AE4S)
- **Audio:** Digilent Pmod I2S2 or custom carrier with SSM2518 / WM8960
- **Toolchain:** Quartus Prime Pro 24.3+

## License

Reference design for evaluation and prototyping.
