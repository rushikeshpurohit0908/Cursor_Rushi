# Real-Time ANC on Intel Agilex 5 FPGA

Full Active Noise Cancellation design for the **Intel/Altera Agilex 5 SoC FPGA**:
microphone → FxLMS (hybrid / feedforward) → headphone/speaker, plus on-fabric
AI classification and I2C codec bring-up.

## Features

- **Real-time I2S** — 48 kHz / 24-bit soft master (Agilex 5 has no hard I2S)
- **FxLMS engine** — 256-tap adaptive FIR, 128-tap Ŝ and P̂, leaky LMS
- **Four modes** — hybrid (error mic), feedforward-frozen, feedforward-virtual, calib
- **AI classifier** — 8-band Goertzel + quantized MLP (tonal / broadband / transient)
- **Tonal notch** — biquad assist when AI reports tonal noise
- **Codec I2C** — SSM2518 and WM8960 init ROM; Pmod I2S2 needs no I2C
- **Quartus + Qsys** — project, SDC, `_hw.tcl`, platform generate script
- **HPS software** — Python CSR/tuner, C header + demo, device-tree overlay
- **~3.8 µs** fabric latency at 100 MHz

## Quick start

### Software tests (no FPGA)

```bash
python3 -m pytest tests/ -v
python -m anc_control.anc_tuner --mode ff-virtual --codec ssm2518 --monitor
```

### Simulation

```bash
cd anc_agilex5/tb && make fxlms && make i2s
```

### On-board

1. Wire codec — [docs/BOARD_INTEGRATION.md](docs/BOARD_INTEGRATION.md)
2. Build — [docs/QUARTUS_BUILD.md](docs/QUARTUS_BUILD.md)
3. Hybrid (ref + error mic):
   ```bash
   python -m anc_control.calibrate_secondary --impulse sweep.wav --response error.wav
   python -m anc_control.load_coeffs --secondary secondary_path_coeffs.hex --no-dry-run
   python -m anc_control.anc_tuner --mode hybrid --codec ssm2518 --no-dry-run --monitor
   ```
4. Feedforward only (no error mic):
   ```bash
   python -m anc_control.load_coeffs --adaptive w.hex --no-dry-run
   python -m anc_control.anc_tuner --mode ff-frozen --no-dry-run --monitor
   ```

## Architecture

[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — signal flow, modes, register map.

## Layout

```
anc_agilex5/rtl/          Verilog (board top = anc_board.v)
anc_agilex5/quartus/      Quartus Prime Pro 24.3 project
anc_agilex5/platform/     Platform Designer component + generate TCL
anc_agilex5/tb/           Icarus testbenches
software/anc_control/     Python control + golden FxLMS
software/baremetal/       C registers + demo
software/dts/             Device-tree overlay
```

## Target

- Agilex 5 E-Series 065B Modular Development Kit (`A5ED065BB32AE4S`)
- Audio: Pmod I2S2, SSM2518 Class-D, or WM8960 headphone codec
- Quartus Prime Pro 24.3+
