"""Train MLP on hardware-friendly features for FPGA deployment."""

from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "fpga" / "scripts"))

from fixed_point import float_to_q15, q15_to_float
from fpga_model import FixedPointFeatureExtractor, FixedPointNLMS
from fpga_params import BLOCK_SIZE, FILTER_TAPS, SAMPLE_RATE

sys.path.insert(0, str(REPO))
from anc.adaptive_filter import NLMSFilter
from anc.signals import NOISE_PROFILES, generate_noise, generate_speech_like, mix_signals


def hw_features(block: np.ndarray) -> np.ndarray:
    ext = FixedPointFeatureExtractor()
    for sample in block:
        q = float_to_q15(float(sample))
        feat = ext.push_sample(q)
        if feat is not None:
            return np.array([q15_to_float(f) for f in feat])
    return np.zeros(8)


def best_mu(profile: str) -> float:
    candidates = [0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.08, 0.1, 0.15, 0.2]
    best, score = 0.02, -999.0
    speech = generate_speech_like(2.0, SAMPLE_RATE)
    noise = generate_noise(profile, 2.0, SAMPLE_RATE, seed=0)
    primary, reference, clean = mix_signals(speech, noise, 5.0)
    for mu in candidates:
        filt = NLMSFilter(filter_length=FILTER_TAPS, mu=mu)
        out, _, _ = filt.process_block(reference, primary)
        inp = np.mean((primary - clean) ** 2)
        res = np.mean((out - clean) ** 2)
        s = 10 * np.log10(inp / res)
        if s > score:
            score = s
            best = mu
    return best


def main() -> None:
    rng = np.random.default_rng(42)
    x_list, y_list = [], []

    for profile in NOISE_PROFILES:
        mu = best_mu(profile)
        print(f"{profile}: optimal mu = {mu:.4f}")
        for seed in range(10):
            noise = generate_noise(profile, 2.0, SAMPLE_RATE, seed=seed)
            for start in range(0, len(noise) - BLOCK_SIZE, BLOCK_SIZE // 2):
                block = noise[start : start + BLOCK_SIZE]
                feat = hw_features(block)
                x_list.append(feat)
                y_list.append([mu, 1.0])

    x = np.array(x_list)
    y = np.array(y_list)

    w1 = rng.normal(0, 0.3, (8, 16))
    b1 = np.zeros(16)
    w2 = rng.normal(0, 0.3, (16, 2))
    b2 = np.zeros(2)
    lr = 0.05

    def to_logit(val, lo, hi):
        n = np.clip((val - lo) / (hi - lo), 1e-4, 1 - 1e-4)
        return np.log(n / (1 - n))

    y_train = np.column_stack([
        [to_logit(row[0], 0.001, 0.200) for row in y],
        [to_logit(row[1], 0.90, 1.10) for row in y],
    ])

    for _ in range(800):
        h = np.tanh(x @ w1 + b1)
        pred = h @ w2 + b2
        err = pred - y_train
        w2 -= lr * h.T @ err / len(x)
        b2 -= lr * np.mean(err, axis=0)
        dh = err @ w2.T * (1 - h**2)
        w1 -= lr * x.T @ dh / len(x)
        b1 -= lr * np.mean(dh, axis=0)

    out_path = REPO / "fpga" / "rtl" / "mem" / "model_weights_fpga.json"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"w1": w1.tolist(), "b1": b1.tolist(), "w2": w2.tolist(), "b2": b2.tolist()}
    out_path.write_text(json.dumps(payload, indent=2))
    print(f"Saved FPGA-trained weights to {out_path}")


if __name__ == "__main__":
    main()
