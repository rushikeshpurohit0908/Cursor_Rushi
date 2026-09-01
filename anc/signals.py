"""Synthetic signal generation for ANC demonstration."""

from __future__ import annotations

import numpy as np


SAMPLE_RATE = 16000


def _envelope(length: int, sample_rate: int) -> np.ndarray:
    """Simple speech-like amplitude envelope."""
    t = np.arange(length) / sample_rate
    syllables = np.zeros(length)
    for start in np.arange(0, t[-1], 0.35):
        idx = int(start * sample_rate)
        width = int(0.18 * sample_rate)
        if idx + width < length:
            window = np.hanning(width)
            syllables[idx : idx + width] += window
    return np.clip(syllables, 0, 1)


def generate_speech_like(duration: float, sample_rate: int = SAMPLE_RATE) -> np.ndarray:
    """Generate a speech-like tonal signal (formant synthesis)."""
    n = int(duration * sample_rate)
    t = np.arange(n) / sample_rate
    env = _envelope(n, sample_rate)

    f0 = 120 + 15 * np.sin(2 * np.pi * 3 * t)
    phase = np.cumsum(2 * np.pi * f0 / sample_rate)
    source = 0.6 * np.sin(phase) + 0.25 * np.sin(2 * phase)

    formants = (
        0.35 * np.sin(2 * np.pi * 500 * t + 0.3 * np.sin(2 * np.pi * 5 * t))
        + 0.2 * np.sin(2 * np.pi * 1500 * t)
        + 0.1 * np.sin(2 * np.pi * 2500 * t)
    )
    speech = 0.15 * env * (source + formants)
    return speech.astype(np.float64)


NOISE_PROFILES: dict[str, dict] = {
    "Engine rumble (80 Hz)": {
        "description": "Low-frequency engine / HVAC rumble",
        "generator": lambda t, rng: 0.8 * np.sin(2 * np.pi * 80 * t) + 0.2 * np.sin(2 * np.pi * 160 * t),
    },
    "Fan hum (300 Hz)": {
        "description": "Mid-frequency fan or transformer hum",
        "generator": lambda t, rng: 0.7 * np.sin(2 * np.pi * 300 * t) + 0.3 * np.sin(2 * np.pi * 600 * t),
    },
    "Office broadband": {
        "description": "Mixed broadband office noise",
        "generator": lambda t, rng: 0.6 * rng.normal(0, 1, len(t)),
    },
    "High-frequency hiss": {
        "description": "Air conditioning / electronic hiss",
        "generator": lambda t, rng: np.diff(rng.normal(0, 0.8, len(t) + 1), prepend=0.0),
    },
    "Construction drill": {
        "description": "Impulsive tonal construction noise",
        "generator": lambda t, rng: 0.5 * np.sin(2 * np.pi * 120 * t) * (1 + 0.8 * np.sin(2 * np.pi * 8 * t))
        + 0.3 * rng.normal(0, 1, len(t)),
    },
}


def generate_noise(
    profile: str,
    duration: float,
    sample_rate: int = SAMPLE_RATE,
    seed: int = 0,
) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n = int(duration * sample_rate)
    t = np.arange(n) / sample_rate
    meta = NOISE_PROFILES[profile]
    noise = meta["generator"](t, rng)
    noise /= np.max(np.abs(noise)) + 1e-9
    return noise.astype(np.float64)


def mix_signals(
    speech: np.ndarray,
    noise: np.ndarray,
    snr_db: float,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Mix speech and noise at a given SNR.

    Returns:
        primary (speech + noise), reference (scaled noise copy), clean speech
    """
    length = min(len(speech), len(noise))
    speech = speech[:length]
    noise = noise[:length]

    speech_power = np.mean(speech**2) + 1e-12
    noise_power = np.mean(noise**2) + 1e-12
    target_noise_power = speech_power / (10 ** (snr_db / 10))
    scale = np.sqrt(target_noise_power / noise_power)
    scaled_noise = noise * scale

    # Reference mic captures a correlated copy of the noise source (with small delay).
    reference = scaled_noise.copy()
    primary = speech + scaled_noise
    return primary, reference, speech
