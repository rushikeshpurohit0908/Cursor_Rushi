"""Normalized Least Mean Squares (NLMS) adaptive filter for ANC."""

from __future__ import annotations

import numpy as np


class NLMSFilter:
    """Feed-forward adaptive filter using the NLMS algorithm."""

    def __init__(self, filter_length: int = 64, mu: float = 0.1, eps: float = 1e-6):
        self.filter_length = filter_length
        self.mu = mu
        self.eps = eps
        self.weights = np.zeros(filter_length, dtype=np.float64)
        self.input_buffer = np.zeros(filter_length, dtype=np.float64)

    def reset(self) -> None:
        self.weights.fill(0.0)
        self.input_buffer.fill(0.0)

    def set_step_size(self, mu: float) -> None:
        self.mu = float(np.clip(mu, 1e-4, 0.99))

    def process_block(
        self,
        reference: np.ndarray,
        primary: np.ndarray,
        step_sizes: np.ndarray | None = None,
    ) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        """
        Process a block of samples.

        Args:
            reference: Noise reference signal x(n).
            primary: Corrupted desired signal d(n) = s(n) + v(n).
            step_sizes: Optional per-sample step size from AI controller.

        Returns:
            Tuple of (error/output, cancelled noise estimate, weight history snapshot).
        """
        n = len(reference)
        output = np.zeros(n, dtype=np.float64)
        noise_estimate = np.zeros(n, dtype=np.float64)

        for i in range(n):
            self.input_buffer = np.roll(self.input_buffer, 1)
            self.input_buffer[0] = reference[i]

            y = float(np.dot(self.weights, self.input_buffer))
            noise_estimate[i] = y
            e = primary[i] - y
            output[i] = e

            norm = float(np.dot(self.input_buffer, self.input_buffer)) + self.eps
            mu = step_sizes[i] if step_sizes is not None else self.mu
            self.weights += (mu / norm) * e * self.input_buffer

        return output, noise_estimate, self.weights.copy()
