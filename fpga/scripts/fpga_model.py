"""Fixed-point FPGA-accurate ANC model for vector generation and cosim."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from ai_mu_selector import select_mu
from fixed_point import float_to_q15, q15_to_float, q15_mul, sat_q15
from fpga_params import (
    BLOCK_SIZE,
    FILTER_TAPS,
    FRAC_BITS,
    GAIN_MAX,
    GAIN_MIN,
    HIDDEN_SIZE,
    MU_MAX,
    MU_MIN,
    NUM_FEATURES,
    NUM_OUTPUTS,
    SAMPLE_RATE,
)


class FixedPointNLMS:
    def __init__(self, filter_taps: int = FILTER_TAPS):
        self.filter_taps = filter_taps
        self.weights = [0] * filter_taps
        self.delay_line = [0] * filter_taps

    def reset(self) -> None:
        self.weights = [0] * self.filter_taps
        self.delay_line = [0] * self.filter_taps

    def process_sample(self, reference_q15: int, primary_q15: int, mu_q15: int) -> tuple[int, int]:
        self.delay_line = [reference_q15] + self.delay_line[:-1]

        y_acc = 0
        for w, x in zip(self.weights, self.delay_line):
            y_acc += int(w) * int(x)
        y = sat_q15(y_acc >> FRAC_BITS)
        e = sat_q15(primary_q15 - y)

        norm = 0
        for x in self.delay_line:
            norm += (int(x) * int(x)) >> FRAC_BITS
        norm = max(norm, 1)

        for i in range(self.filter_taps):
            num = int(mu_q15) * int(e) * int(self.delay_line[i])
            delta = num // (norm << FRAC_BITS)
            self.weights[i] = sat_q15(self.weights[i] + delta)

        return e, y


class FixedPointFeatureExtractor:
    """Hardware-friendly block feature extractor (no FFT)."""

    def __init__(self, block_size: int = BLOCK_SIZE):
        self.block_size = block_size
        self.reset_block()

    def reset_block(self) -> None:
        self.count = 0
        self.sum_sq = 0
        self.zc = 0
        self.prev_sign = 0
        self.peak = 0
        self.low_energy = 0
        self.mid_energy = 0
        self.high_energy = 0
        self.lp_y = 0
        self.bp_y = 0

    def _filter_sample(self, x: int) -> None:
        # One-pole low-pass (~500 Hz at 16 kHz): y = y + mu_lp*(x-y)
        mu_lp = float_to_q15(0.08)
        self.lp_y = sat_q15(self.lp_y + q15_mul(mu_lp, x - self.lp_y))
        low = self.lp_y
        high = sat_q15(x - self.lp_y)
        self.bp_y = sat_q15(self.bp_y + q15_mul(float_to_q15(0.15), high - self.bp_y))
        mid = self.bp_y

        self.low_energy += q15_mul(low, low)
        self.mid_energy += q15_mul(mid, mid)
        self.high_energy += q15_mul(high, high)

    def push_sample(self, x_q15: int) -> list[int] | None:
        sign = 1 if x_q15 >= 0 else 0
        if self.count > 0 and sign != self.prev_sign:
            self.zc += 1
        self.prev_sign = sign

        self.sum_sq += q15_mul(x_q15, x_q15)
        abs_x = abs(int(x_q15))
        if abs_x > self.peak:
            self.peak = abs_x
        self._filter_sample(x_q15)
        self.count += 1

        if self.count < self.block_size:
            return None
        return self.finish_block()

    def finish_block(self) -> list[int]:
        n = self.block_size
        rms = int(np.sqrt(self.sum_sq / max(n, 1)))
        zcr = (self.zc << FRAC_BITS) // max(n, 1)
        total_e = self.low_energy + self.mid_energy + self.high_energy + 1
        low = (self.low_energy << FRAC_BITS) // total_e
        mid = (self.mid_energy << FRAC_BITS) // total_e
        high = (self.high_energy << FRAC_BITS) // total_e
        centroid = (low // 4 + mid // 2 + high) // 2
        flatness = (low + mid + high) // 3
        crest = (self.peak << FRAC_BITS) // max(int(np.sqrt(self.sum_sq / max(n, 1))), 1)

        features = [rms, zcr, centroid, flatness, low, mid, high, crest]
        self.reset_block()
        return [sat_q15(f) for f in features]


class FixedPointMLP:
    def __init__(self, weights_path: Path):
        fpga_weights = weights_path.parent / "mem" / "model_weights_fpga.json"
        path = fpga_weights if fpga_weights.exists() else weights_path
        payload = json.loads(path.read_text())
        self.w1 = np.array(payload["w1"], dtype=np.float64)
        self.b1 = np.array(payload["b1"], dtype=np.float64)
        self.w2 = np.array(payload["w2"], dtype=np.float64)
        self.b2 = np.array(payload["b2"], dtype=np.float64)
        self.w1_q = [[float_to_q15(v) for v in row] for row in self.w1]
        self.b1_q = [float_to_q15(v) for v in self.b1]
        self.w2_q = [[float_to_q15(v) for v in row] for row in self.w2]
        self.b2_q = [float_to_q15(v) for v in self.b2]

    def predict(self, features_q15: list[int]) -> tuple[int, int]:
        hidden = []
        for j in range(HIDDEN_SIZE):
            acc = self.b1_q[j] << FRAC_BITS
            for i in range(NUM_FEATURES):
                acc = q15_mac(acc, features_q15[i], self.w1_q[i][j])
            hidden.append(tanh_lut(sat_q15(acc >> FRAC_BITS)))

        out = []
        for k in range(NUM_OUTPUTS):
            acc = self.b2_q[k] << FRAC_BITS
            for j in range(HIDDEN_SIZE):
                acc = q15_mac(acc, hidden[j], self.w2_q[j][k])
            out.append(sigmoid_lut(sat_q15(acc >> FRAC_BITS)))

        mu = mu_from_sigmoid(out[0])
        gain = gain_from_sigmoid(out[1])
        return mu, gain


class FixedPointANC:
    def __init__(self, weights_path: Path | None = None):
        self.nlms = FixedPointNLMS()
        self.features = FixedPointFeatureExtractor()
        self.mu_q15 = float_to_q15(0.02)

    def process_arrays(self, reference: np.ndarray, primary: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        ref_q = [float_to_q15(v) for v in reference]
        pri_q = [float_to_q15(v) for v in primary]
        outputs = []
        noise_est = []

        for r, p in zip(ref_q, pri_q):
            feat = self.features.push_sample(r)
            if feat is not None:
                self.mu_q15, _ = select_mu(feat)
            out, y = self.nlms.process_sample(r, p, self.mu_q15)
            outputs.append(q15_to_float(out))
            noise_est.append(q15_to_float(y))

        return np.array(outputs), np.array(noise_est)


def export_vectors(weights_path: Path, out_dir: Path, num_samples: int = 2048) -> None:
    import sys

    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
    from anc.processor import ANCProcessor

    proc = ANCProcessor(filter_length=FILTER_TAPS)
    result = proc.process("Engine rumble (80 Hz)", 5.0, num_samples / SAMPLE_RATE, use_ai=True)
    reference = result.reference[:num_samples]
    primary = result.primary[:num_samples]

    fp = FixedPointANC()
    fp_out, _ = fp.process_arrays(reference, primary)

    out_dir.mkdir(parents=True, exist_ok=True)

    def write_hex(name: str, arr: np.ndarray) -> None:
        path = out_dir / name
        with path.open("w") as f:
            for v in arr:
                q = float_to_q15(float(v))
                if q < 0:
                    q += 1 << 16
                f.write(f"{q:04x}\n")

    write_hex("reference.hex", reference)
    write_hex("primary.hex", primary)
    write_hex("expected_output.hex", fp_out)

    print(f"Exported {num_samples} samples to {out_dir}")


if __name__ == "__main__":
    repo = Path(__file__).resolve().parents[2]
    weights = repo / "anc" / "model_weights.json"
    export_vectors(weights, repo / "fpga" / "tb" / "vectors")
