"""Neural network controller that adapts NLMS step size from noise features."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from .adaptive_filter import NLMSFilter
from .features import extract_features
from .signals import NOISE_PROFILES, SAMPLE_RATE, generate_noise, mix_signals, generate_speech_like

WEIGHTS_PATH = Path(__file__).parent / "model_weights.json"
_controller_instance: "MLPController | None" = None


class MLPController:
    """Two-layer MLP mapping noise features to NLMS step size and filter gain."""

    def __init__(self, weights_path: Path | None = None):
        path = weights_path or WEIGHTS_PATH
        if path.exists():
            self._load_weights(path)
        else:
            self._init_random_weights()
            self._bootstrap_train()
            self.save_weights(path)

    def _init_random_weights(self) -> None:
        rng = np.random.default_rng(42)
        self.w1 = rng.normal(0, 0.35, (8, 16))
        self.b1 = np.zeros(16)
        self.w2 = rng.normal(0, 0.35, (16, 2))
        self.b2 = np.zeros(2)

    def _forward(self, x: np.ndarray) -> np.ndarray:
        h = np.tanh(x @ self.w1 + self.b1)
        return h @ self.w2 + self.b2

    def predict(self, features: np.ndarray) -> tuple[float, float]:
        """Return (step_size, filter_gain) for the given feature vector."""
        out = self._forward(features.reshape(1, -1))[0]
        step_size = 0.001 + 0.199 * (1 / (1 + np.exp(-out[0])))
        filter_gain = 0.90 + 0.20 * (1 / (1 + np.exp(-out[1])))
        return float(step_size), float(filter_gain)

    @staticmethod
    def _to_logit(value: float, lo: float, hi: float) -> float:
        norm = float(np.clip((value - lo) / (hi - lo), 1e-4, 1 - 1e-4))
        return float(np.log(norm / (1 - norm)))

    def _measure_improvement(
        self,
        profile: str,
        mu: float,
        filter_length: int = 128,
        duration: float = 2.0,
    ) -> float:
        speech = generate_speech_like(duration, SAMPLE_RATE)
        noise = generate_noise(profile, duration, SAMPLE_RATE, seed=0)
        primary, reference, clean = mix_signals(speech, noise, 5.0)
        filt = NLMSFilter(filter_length=filter_length, mu=mu)
        output, _, _ = filt.process_block(reference, primary)
        input_noise = np.mean((primary - clean) ** 2) + 1e-12
        residual = np.mean((output - clean) ** 2) + 1e-12
        return float(10 * np.log10(input_noise / residual))

    def _find_optimal_mu(self, profile: str) -> float:
        candidates = [0.001, 0.002, 0.005, 0.01, 0.02, 0.03, 0.05, 0.08, 0.1, 0.15, 0.2]
        best_mu, best_score = 0.02, -999.0
        for mu in candidates:
            score = self._measure_improvement(profile, mu)
            if score > best_score:
                best_score = score
                best_mu = mu
        return best_mu

    def _bootstrap_train(self, epochs: int = 600) -> None:
        """Train on real demo noise profiles with empirically optimal step sizes."""
        x_data: list[np.ndarray] = []
        y_data: list[np.ndarray] = []

        for profile in NOISE_PROFILES:
            optimal_mu = self._find_optimal_mu(profile)
            for seed in range(6):
                noise = generate_noise(profile, 2.0, SAMPLE_RATE, seed=seed)
                for start in range(0, len(noise) - 512, 256):
                    block = noise[start : start + 512]
                    features = extract_features(block, SAMPLE_RATE)
                    x_data.append(features)
                    y_data.append(
                        np.array(
                            [
                                self._to_logit(optimal_mu, 0.001, 0.200),
                                self._to_logit(1.0, 0.90, 1.10),
                            ]
                        )
                    )

        x = np.array(x_data)
        y = np.array(y_data)
        lr = 0.06

        for _ in range(epochs):
            h = np.tanh(x @ self.w1 + self.b1)
            pred = h @ self.w2 + self.b2
            error = pred - y
            grad_w2 = h.T @ error / len(x)
            grad_b2 = np.mean(error, axis=0)
            grad_h = error @ self.w2.T * (1 - h**2)
            grad_w1 = x.T @ grad_h / len(x)
            grad_b1 = np.mean(grad_h, axis=0)
            self.w2 -= lr * grad_w2
            self.b2 -= lr * grad_b2
            self.w1 -= lr * grad_w1
            self.b1 -= lr * grad_b1

    def save_weights(self, path: Path) -> None:
        payload = {
            "w1": self.w1.tolist(),
            "b1": self.b1.tolist(),
            "w2": self.w2.tolist(),
            "b2": self.b2.tolist(),
        }
        path.write_text(json.dumps(payload))

    def _load_weights(self, path: Path) -> None:
        payload = json.loads(path.read_text())
        self.w1 = np.array(payload["w1"])
        self.b1 = np.array(payload["b1"])
        self.w2 = np.array(payload["w2"])
        self.b2 = np.array(payload["b2"])


class AIAdaptiveController:
    """Maps streaming reference audio to per-block NLMS parameters."""

    def __init__(self, block_size: int = 512, sample_rate: int = SAMPLE_RATE):
        global _controller_instance
        self.block_size = block_size
        self.sample_rate = sample_rate
        if _controller_instance is None:
            _controller_instance = MLPController()
        self.mlp = _controller_instance
        self.history: list[dict] = []

    def compute_step_sizes(self, reference: np.ndarray, n_samples: int) -> np.ndarray:
        step_sizes = np.full(n_samples, 0.02, dtype=np.float64)
        self.history.clear()

        for start in range(0, n_samples, self.block_size):
            end = min(start + self.block_size, n_samples)
            block = reference[start:end]
            features = extract_features(block, self.sample_rate)
            mu, gain = self.mlp.predict(features)
            self.history.append(
                {
                    "start": start,
                    "end": end,
                    "step_size": mu,
                    "filter_gain": gain,
                    "features": features.tolist(),
                }
            )
            step_sizes[start:end] = mu * gain

        return step_sizes
