"""Visualization helpers for the ANC demo."""

from __future__ import annotations

import io

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

from .processor import ANCResult


def _normalize(audio: np.ndarray) -> np.ndarray:
    peak = np.max(np.abs(audio)) + 1e-9
    return (audio / peak * 0.95).astype(np.float32)


def to_gradio_audio(audio: np.ndarray, sample_rate: int) -> tuple[int, np.ndarray]:
    return sample_rate, _normalize(audio)


def plot_waveforms(result: ANCResult) -> np.ndarray:
    fig, axes = plt.subplots(4, 1, figsize=(10, 8), sharex=True)
    t = np.arange(len(result.clean)) / result.sample_rate
    labels = [
        ("Clean speech (target)", result.clean, "#2ecc71"),
        ("Primary (speech + noise)", result.primary, "#e74c3c"),
        ("AI-ANC output", result.output, "#3498db"),
        ("Estimated noise", result.noise_estimate, "#9b59b6"),
    ]
    for ax, (title, signal, color) in zip(axes, labels):
        ax.plot(t, signal, color=color, linewidth=0.6)
        ax.set_ylabel(title, fontsize=8)
        ax.grid(True, alpha=0.3)
    axes[-1].set_xlabel("Time (s)")
    fig.suptitle(f"Waveforms — {result.noise_profile}", fontsize=11, fontweight="bold")
    fig.tight_layout()
    return _fig_to_array(fig)


def plot_spectrograms(result: ANCResult) -> np.ndarray:
    fig, axes = plt.subplots(1, 3, figsize=(12, 4))
    signals = [
        ("Primary (noisy)", result.primary),
        ("AI-ANC output", result.output),
        ("Clean reference", result.clean),
    ]
    for ax, (title, signal) in zip(axes, signals):
        ax.specgram(signal, NFFT=256, Fs=result.sample_rate, noverlap=128, cmap="magma")
        ax.set_title(title, fontsize=9)
        ax.set_xlabel("Time (s)")
        ax.set_ylabel("Freq (Hz)")
    fig.suptitle("Spectrogram comparison", fontsize=11, fontweight="bold")
    fig.tight_layout()
    return _fig_to_array(fig)


def plot_ai_parameters(result: ANCResult) -> np.ndarray:
    fig, axes = plt.subplots(2, 1, figsize=(10, 5), sharex=True)
    if not result.ai_history:
        axes[0].text(0.5, 0.5, "AI controller disabled (fixed NLMS μ)", ha="center", va="center")
        axes[1].axis("off")
    else:
        starts = [h["start"] / result.sample_rate for h in result.ai_history]
        mus = [h["step_size"] for h in result.ai_history]
        gains = [h["filter_gain"] for h in result.ai_history]
        axes[0].step(starts, mus, where="post", color="#e67e22", linewidth=2)
        axes[0].set_ylabel("Step size (μ)")
        axes[0].set_title("AI-predicted NLMS step size over time")
        axes[0].grid(True, alpha=0.3)
        axes[1].step(starts, gains, where="post", color="#1abc9c", linewidth=2)
        axes[1].set_ylabel("Filter gain")
        axes[1].set_xlabel("Time (s)")
        axes[1].set_title("AI-predicted filter gain over time")
        axes[1].grid(True, alpha=0.3)
    fig.tight_layout()
    return _fig_to_array(fig)


def plot_metrics_bar(result: ANCResult, baseline_improvement: float) -> np.ndarray:
    fig, ax = plt.subplots(figsize=(6, 4))
    modes = ["Fixed NLMS", "AI-Adaptive NLMS"]
    values = [baseline_improvement, result.snr_improvement_db]
    colors = ["#95a5a6", "#3498db"]
    bars = ax.bar(modes, values, color=colors, width=0.5)
    ax.set_ylabel("Noise reduction (dB)")
    ax.set_title("ANC performance comparison")
    ax.axhline(0, color="black", linewidth=0.5)
    for bar, val in zip(bars, values):
        ax.text(bar.get_x() + bar.get_width() / 2, bar.get_height() + 0.3, f"{val:.1f} dB", ha="center")
    fig.tight_layout()
    return _fig_to_array(fig)


def _fig_to_array(fig: plt.Figure) -> np.ndarray:
    buf = io.BytesIO()
    fig.savefig(buf, format="png", dpi=120, bbox_inches="tight")
    plt.close(fig)
    buf.seek(0)
    import PIL.Image

    return np.array(PIL.Image.open(buf))
