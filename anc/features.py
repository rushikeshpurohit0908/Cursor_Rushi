"""Spectral and temporal features for AI-driven ANC parameter control."""

from __future__ import annotations

import numpy as np


def extract_features(block: np.ndarray, sample_rate: int = 16000) -> np.ndarray:
    """
    Extract an 8-dimensional feature vector from an audio block.

    Features: RMS, zero-crossing rate, spectral centroid, spectral flatness,
    and energy in low / mid / high bands.
    """
    block = np.asarray(block, dtype=np.float64)
    if len(block) == 0:
        return np.zeros(8, dtype=np.float64)

    rms = float(np.sqrt(np.mean(block**2) + 1e-12))
    zcr = float(np.mean(np.abs(np.diff(np.signbit(block)))))

    spectrum = np.abs(np.fft.rfft(block))
    freqs = np.fft.rfftfreq(len(block), d=1.0 / sample_rate)
    power = spectrum**2 + 1e-12
    total_power = float(np.sum(power))

    centroid = float(np.sum(freqs * power) / total_power / (sample_rate / 2))
    flatness = float(np.exp(np.mean(np.log(power))) / (np.mean(power) + 1e-12))

    low = float(np.sum(power[freqs < 500]) / total_power)
    mid = float(np.sum(power[(freqs >= 500) & (freqs < 2000)]) / total_power)
    high = float(np.sum(power[freqs >= 2000]) / total_power)

    peak = float(np.max(spectrum) / (np.mean(spectrum) + 1e-12))
    crest = float(np.max(np.abs(block)) / (rms + 1e-12))

    return np.array([rms, zcr, centroid, flatness, low, mid, high, crest], dtype=np.float64)
