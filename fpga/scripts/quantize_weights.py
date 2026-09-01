"""Quantize floating-point MLP weights to Q1.15 .mem files for FPGA BRAM init."""

from __future__ import annotations

import json
from pathlib import Path

import numpy as np

FRAC_BITS = 15


def float_to_q15(value: float) -> int:
    scaled = int(round(float(value) * (1 << FRAC_BITS)))
    return int(np.clip(scaled, -(1 << 15), (1 << 15) - 1))


def to_hex(value: int) -> str:
    if value < 0:
        value += 1 << 16
    return f"{value:04x}"


def write_mem(path: Path, values: list[int]) -> None:
    path.write_text("\n".join(to_hex(v) for v in values) + "\n")


def main() -> None:
    repo = Path(__file__).resolve().parents[2]
    fpga_json = repo / "fpga" / "rtl" / "mem" / "model_weights_fpga.json"
    weights_path = fpga_json if fpga_json.exists() else repo / "anc" / "model_weights.json"
    out_dir = repo / "fpga" / "rtl" / "mem"
    out_dir.mkdir(parents=True, exist_ok=True)

    payload = json.loads(weights_path.read_text())
    w1 = np.array(payload["w1"])
    b1 = np.array(payload["b1"])
    w2 = np.array(payload["w2"])
    b2 = np.array(payload["b2"])

    w1_flat = [float_to_q15(w1[i, j]) for j in range(w1.shape[1]) for i in range(w1.shape[0])]
    b1_q = [float_to_q15(v) for v in b1]
    w2_flat = [float_to_q15(w2[j, k]) for k in range(w2.shape[1]) for j in range(w2.shape[0])]
    b2_q = [float_to_q15(v) for v in b2]

    write_mem(out_dir / "w1.mem", w1_flat)
    write_mem(out_dir / "b1.mem", b1_q)
    write_mem(out_dir / "w2.mem", w2_flat)
    write_mem(out_dir / "b2.mem", b2_q)
    print(f"Quantized weights written to {out_dir}")


if __name__ == "__main__":
    main()
