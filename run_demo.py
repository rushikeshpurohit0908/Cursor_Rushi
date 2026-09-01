"""Headless CLI runner for the ANC demo."""

from __future__ import annotations

import argparse

from anc.processor import ANCProcessor
from anc.signals import NOISE_PROFILES


def main() -> None:
    parser = argparse.ArgumentParser(description="AI-based Adaptive Noise Cancellation demo")
    parser.add_argument("--profile", choices=list(NOISE_PROFILES.keys()), default="Engine rumble (80 Hz)")
    parser.add_argument("--snr", type=float, default=5.0)
    parser.add_argument("--duration", type=float, default=3.0)
    parser.add_argument("--no-ai", action="store_true")
    args = parser.parse_args()

    proc = ANCProcessor()
    baseline = proc.process(args.profile, args.snr, args.duration, use_ai=False)
    result = proc.process(args.profile, args.snr, args.duration, use_ai=not args.no_ai)

    print(f"Noise profile:     {args.profile}")
    print(f"Input SNR:         {args.snr:.1f} dB")
    print(f"Fixed NLMS:        {baseline.snr_improvement_db:.2f} dB reduction")
    print(f"AI-Adaptive NLMS:  {result.snr_improvement_db:.2f} dB reduction")
    print(f"AI advantage:      {result.snr_improvement_db - baseline.snr_improvement_db:+.2f} dB")
    if result.ai_history:
        mus = [h["step_size"] for h in result.ai_history]
        print(f"AI step size range: {min(mus):.4f} – {max(mus):.4f}")


if __name__ == "__main__":
    main()
