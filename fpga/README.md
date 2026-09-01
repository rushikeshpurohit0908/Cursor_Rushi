# AI-Based Adaptive Noise Cancellation — FPGA Implementation

Fixed-point RTL targeting **Intel Cyclone V / Cyclone 10 / Agilex** and other FPGAs. Implements the same AI-adaptive NLMS algorithm as the Python demo, mapped to streaming Q1.15 arithmetic.

## Architecture

```
                    ┌──────────────────────────────────────────────────────┐
  reference_in ────►│  Feature Extractor (512-block)                       │
                    │    RMS, ZCR, 3-band energy → 8 features              │
                    └────────────────────────┬─────────────────────────────┘
                                             │ every 512 samples
                                             ▼
                    ┌──────────────────────────────────────────────────────┐
                    │  AI μ Selector (band classifier + tuned LUT)           │
                    │    OR mlp_controller.v (full 8→16→2 MLP, optional)   │
                    └────────────────────────┬─────────────────────────────┘
                                             │
  reference_in ────►│  NLMS Adaptive Filter (32 taps, Q1.15)               │
  primary_in ──────►│    e(n) = d(n) − wᵀx(n)                              │──► anc_out
                    └──────────────────────────────────────────────────────┘
```

## Resource estimate (Cyclone V, 16-bit Q1.15)

| Module | DSP | Logic (ALMs) | M10K |
|--------|-----|--------------|------|
| NLMS filter (32 taps) | 2–4 | ~800 | 2 |
| Feature extractor | 4 | ~600 | 1 |
| AI μ selector (default) | 0 | ~120 | 0 |
| MLP controller (optional) | 8 | ~1200 | 4 |
| **Total (default)** | **~6** | **~1520** | **~3** |

At **50 MHz** internal clock, the NLMS state machine processes one 16 kHz sample in ~35 cycles → **~560 kHz max sample rate** (headroom above 16 kHz audio).

## Fixed-point format

| Signal | Format | Range |
|--------|--------|-------|
| Audio samples | Q1.15 | −1.0 … +1.0 |
| Filter weights | Q1.15 | −1.0 … +1.0 |
| Step size μ | Q1.15 | 0.001 … 0.200 |
| Accumulators | 40-bit | MAC / norm |

## Directory layout

```
fpga/
  rtl/
    anc_top.v            Top-level with ready/valid
    nlms_filter.v        32-tap NLMS adaptive FIR
    feature_extractor.v  Block feature extraction (no FFT)
    ai_mu_selector.v     Band-classifier AI μ selector (default)
    mlp_controller.v     Full MLP neural network (optional)
    anc_math.v           Q1.15 mul, tanh/sigmoid LUTs
    mem/                 Pre-quantized MLP weights (.mem)
  tb/
    anc_tb.v             Icarus Verilog testbench
    vectors/             Hex test vectors from Python golden model
  scripts/
    fpga_model.py        Cycle-accurate fixed-point Python model
    quantize_weights.py  Float → Q1.15 weight export
  constraints/
    anc.sdc              Timing constraints (50 MHz)
  Makefile
```

## Build and simulate

```bash
cd fpga
pip install numpy          # from repo root requirements.txt

# Generate test vectors + quantize weights
make vectors quantize

# Run fixed-point Python model
make cosim

# RTL simulation (requires Icarus Verilog)
sudo apt install iverilog   # if needed
make sim
```

## Synthesis (Intel Quartus)

1. Create a new project targeting your device (e.g. **5CSEMA5F31C6** Cyclone V).
2. Add all files under `rtl/` as design files.
3. Set top entity: `anc_top`.
4. Add `constraints/anc.sdc`.
5. Assign clock to your board oscillator pin (default 50 MHz in SDC).
6. Map streaming inputs to I2S/PDM microphone interfaces via FIFO.

### I2S interface hookup

Connect your audio codec as follows:

| Port | Direction | Description |
|------|-----------|-------------|
| `reference_in` | Input | Reference mic (Q1.15 from I2S RX) |
| `primary_in` | Input | Primary mic (Q1.15 from I2S RX) |
| `sample_en` | Input | Strobe when `input_ready` high |
| `anc_out` | Output | Denoised audio → I2S TX |
| `output_valid` | Output | Result ready strobe |

## AI weight update flow

1. Train / export weights in Python (`anc/model_weights.json`).
2. Run `python scripts/quantize_weights.py` → `rtl/mem/*.mem`.
3. Re-synthesize; MLP BRAM initializes from `.mem` via `$readmemh`.

For on-chip retraining, replace `mlp_controller.v` with a soft-core (Nios II / RISC-V) or Intel AI Suite IP.

## Verification

Python `fpga_model.py` mirrors the RTL fixed-point behavior and exports hex vectors. The testbench compares RTL output against these vectors for 512 samples of engine-rumble ANC.

```bash
python scripts/fpga_model.py
# Exports tb/vectors/{reference,primary,expected_output}.hex
```

## Extending

| Goal | Suggestion |
|------|------------|
| More taps (64/128) | Increase `ANC_FILTER_TAPS` in `anc_pkg.v`; add BRAM |
| 48 kHz audio | Raise clock or pipeline NLMS MAC |
| On-chip FFT features | Replace `feature_extractor.v` with FFT IP |
| HLS path | Export NLMS loop to Intel HLS Compiler |
