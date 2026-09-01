#!/usr/bin/env python3
"""Offline secondary-path calibration from captured WAV files.

Usage:
    python -m anc_control.calibrate_secondary --impulse sweep.wav --response error.wav
"""

from __future__ import annotations

import argparse
import struct
import wave
from pathlib import Path


def read_wav_mono(path: Path) -> tuple[list[float], int]:
    with wave.open(str(path), "rb") as wf:
        rate = wf.getframerate()
        n_frames = wf.getnframes()
        raw = wf.readframes(n_frames)
        width = wf.getsampwidth()
        if width == 2:
            samples = [s / 32768.0 for s in struct.unpack(f"<{n_frames}h", raw)]
        elif width == 3:
            samples = []
            for i in range(n_frames):
                b = raw[i * 3 : i * 3 + 3]
                val = b[0] | (b[1] << 8) | (b[2] << 16)
                if val & 0x800000:
                    val -= 0x1000000
                samples.append(val / 8388608.0)
        else:
            raise ValueError(f"Unsupported sample width: {width}")
    return samples, rate


def lms_identify(impulse: list[float], response: list[float], taps: int = 128, mu: float = 0.01) -> list[int]:
    """Identify secondary-path FIR via simple LMS system identification."""
    w = [0.0] * taps
    x_buf = [0.0] * taps
    n = min(len(impulse), len(response))

    for i in range(n):
        x_buf = [impulse[i]] + x_buf[:-1]
        y = sum(w[j] * x_buf[j] for j in range(taps))
        e = response[i] - y
        for j in range(taps):
            w[j] += mu * e * x_buf[j]

    # Convert to Q1.31 fixed-point
    return [max(-0x80000000, min(0x7FFFFFFF, int(c * (1 << 31)))) for c in w]


def main() -> int:
    parser = argparse.ArgumentParser(description="Secondary-path FIR calibration")
    parser.add_argument("--impulse", type=Path, required=True, help="Sweep/impulse WAV played through speaker")
    parser.add_argument("--response", type=Path, required=True, help="Error-mic capture WAV")
    parser.add_argument("--taps", type=int, default=128)
    parser.add_argument("--output", type=Path, default=Path("secondary_path_coeffs.hex"))
    args = parser.parse_args()

    impulse, rate_i = read_wav_mono(args.impulse)
    response, rate_r = read_wav_mono(args.response)
    if rate_i != rate_r:
        raise SystemExit(f"Sample rate mismatch: {rate_i} vs {rate_r}")

    coeffs = lms_identify(impulse, response, taps=args.taps)

    with open(args.output, "w") as f:
        for c in coeffs:
            f.write(f"{c & 0xFFFFFFFF:08x}\n")

    print(f"Wrote {len(coeffs)} Q1.31 coefficients to {args.output}")
    print("Load into FPGA with:")
    print(f"  python -m anc_control.load_coeffs --secondary {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
