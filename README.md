# AI-Based Adaptive Noise Cancellation (ANC) Demo

An interactive demonstration of **feed-forward Active Noise Cancellation** enhanced with a **neural network controller** that dynamically adapts filter parameters based on real-time noise characteristics.

## Overview

Active Noise Cancellation (ANC) uses a reference microphone to capture ambient noise, learns the acoustic path with an adaptive filter, and subtracts the estimated noise from the primary audio signal. This demo implements the industry-standard **NLMS (Normalized Least Mean Squares)** algorithm and adds an **AI layer** that predicts optimal step size and filter gain from spectral features — enabling faster convergence and better noise suppression across varying noise types.

```
  Reference mic ──► [Feature extraction] ──► [MLP Neural Network] ──► μ, gain
        │                                              │
        └──────────► [NLMS Adaptive Filter] ◄──────────┘
                              │
  Primary mic ───────────────►⊖──► Clean output
```

## Quick start

```bash
pip install -r requirements.txt

# Headless CLI demo
python run_demo.py
python run_demo.py --profile "Fan hum (300 Hz)" --snr 3

# Interactive web UI
python app.py
```

Open **http://localhost:7860** for the Gradio interface.

## Features

- **5 synthetic noise profiles** — engine rumble, fan hum, broadband office noise, high-frequency hiss, construction drill
- **Speech-like target signal** — formant-synthesized speech mixed at configurable SNR
- **AI-adaptive NLMS** — 2-layer MLP (8→16→2) maps noise features to step size and gain
- **Side-by-side comparison** — AI-adaptive vs fixed-parameter NLMS
- **Rich visualizations** — waveforms, spectrograms, AI parameter timeline, performance metrics

## Project structure

```
anc/
  adaptive_filter.py   # NLMS adaptive FIR filter
  ai_controller.py     # MLP neural network for parameter control
  features.py          # Spectral/temporal feature extraction
  signals.py           # Synthetic speech and noise generation
  processor.py         # End-to-end ANC pipeline
  visualize.py         # Matplotlib plots for the UI
app.py                 # Gradio web demo
run_demo.py            # CLI runner
```

## How the AI controller works

Every 512-sample block, the system extracts 8 features from the reference noise:

| Feature | Description |
|---------|-------------|
| RMS energy | Overall noise loudness |
| Zero-crossing rate | Noisiness vs tonality |
| Spectral centroid | Frequency center of mass |
| Spectral flatness | Tonal vs broadband character |
| Low / mid / high band energy | Frequency distribution |
| Crest factor | Peakiness of the signal |

The MLP outputs:
- **Step size (μ)** — controls NLMS convergence speed (0.001–0.5)
- **Filter gain** — scales cancellation strength (0.5–1.5)

The network is bootstrapped at startup with synthetic training data representing common noise profiles, so the demo works immediately without external model files.

## Algorithm reference

- **NLMS update:** `w(n+1) = w(n) + (μ / ||x||²) · e(n) · x(n)`
- **ANC principle:** `e(n) = d(n) - wᵀx(n)` where `d(n)` is the primary signal and `x(n)` is the reference noise

## License

MIT
