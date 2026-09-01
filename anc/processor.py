"""End-to-end AI-based ANC processing pipeline."""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from .adaptive_filter import NLMSFilter
from .ai_controller import AIAdaptiveController
from .signals import SAMPLE_RATE, generate_noise, generate_speech_like, mix_signals


@dataclass
class ANCResult:
    clean: np.ndarray
    primary: np.ndarray
    reference: np.ndarray
    output: np.ndarray
    noise_estimate: np.ndarray
    noise_profile: str
    snr_db: float
    snr_improvement_db: float
    ai_history: list[dict]
    sample_rate: int = SAMPLE_RATE


class ANCProcessor:
    """Runs classical NLMS ANC with AI-tuned adaptation parameters."""

    def __init__(self, filter_length: int = 128, block_size: int = 512):
        self.filter_length = filter_length
        self.block_size = block_size
        self.sample_rate = SAMPLE_RATE

    def process(
        self,
        noise_profile: str,
        snr_db: float = 5.0,
        duration: float = 3.0,
        use_ai: bool = True,
        fixed_mu: float = 0.02,
        seed: int = 42,
    ) -> ANCResult:
        speech = generate_speech_like(duration, self.sample_rate)
        noise = generate_noise(noise_profile, duration, self.sample_rate, seed=seed)
        primary, reference, clean = mix_signals(speech, noise, snr_db)

        filt = NLMSFilter(filter_length=self.filter_length, mu=fixed_mu)
        ai = AIAdaptiveController(block_size=self.block_size, sample_rate=self.sample_rate)

        if use_ai:
            step_sizes = ai.compute_step_sizes(reference, len(primary))
        else:
            step_sizes = np.full(len(primary), fixed_mu)
            ai.history = []

        output, noise_est, _ = filt.process_block(reference, primary, step_sizes)

        input_noise_power = np.mean((primary - clean) ** 2) + 1e-12
        residual_power = np.mean((output - clean) ** 2) + 1e-12
        improvement = 10 * np.log10(input_noise_power / residual_power)

        return ANCResult(
            clean=clean,
            primary=primary,
            reference=reference,
            output=output,
            noise_estimate=noise_est,
            noise_profile=noise_profile,
            snr_db=snr_db,
            snr_improvement_db=float(improvement),
            ai_history=ai.history,
            sample_rate=self.sample_rate,
        )

    def process_custom(
        self,
        primary: np.ndarray,
        reference: np.ndarray,
        clean: np.ndarray | None = None,
        use_ai: bool = True,
        fixed_mu: float = 0.02,
    ) -> ANCResult:
        primary = np.asarray(primary, dtype=np.float64)
        reference = np.asarray(reference, dtype=np.float64)
        length = min(len(primary), len(reference))
        primary = primary[:length]
        reference = reference[:length]
        clean_arr = primary.copy() if clean is None else np.asarray(clean[:length], dtype=np.float64)

        filt = NLMSFilter(filter_length=self.filter_length, mu=fixed_mu)
        ai = AIAdaptiveController(block_size=self.block_size, sample_rate=self.sample_rate)
        step_sizes = ai.compute_step_sizes(reference, length) if use_ai else np.full(length, fixed_mu)
        output, noise_est, _ = filt.process_block(reference, primary, step_sizes)

        improvement = 0.0
        if clean is not None:
            input_noise_power = np.mean((primary - clean_arr) ** 2) + 1e-12
            residual_power = np.mean((output - clean_arr) ** 2) + 1e-12
            improvement = float(10 * np.log10(input_noise_power / residual_power))

        return ANCResult(
            clean=clean_arr,
            primary=primary,
            reference=reference,
            output=output,
            noise_estimate=noise_est,
            noise_profile="Custom",
            snr_db=0.0,
            snr_improvement_db=improvement,
            ai_history=ai.history,
            sample_rate=self.sample_rate,
        )
