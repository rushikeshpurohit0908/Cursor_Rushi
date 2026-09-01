#!/usr/bin/env python3
"""Load pre-computed FIR coefficients into FPGA BRAM via CSR."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from anc_control.fpga_bridge import AncFpgaBridge


def load_hex(path: Path) -> list[int]:
    coeffs = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            coeffs.append(int(line, 16))
    return coeffs


def main() -> int:
    parser = argparse.ArgumentParser(description="Load FIR coefficients to FPGA")
    parser.add_argument("--secondary", type=Path, help="Secondary-path .hex")
    parser.add_argument("--primary", type=Path, help="Primary-path .hex (virtual error)")
    parser.add_argument("--adaptive", type=Path, help="Adaptive weights .hex")
    parser.add_argument("--no-dry-run", action="store_true")
    args = parser.parse_args()

    if not any([args.secondary, args.primary, args.adaptive]):
        parser.error("Provide --secondary, --primary, and/or --adaptive")

    with AncFpgaBridge(dry_run=not args.no_dry_run) as bridge:
        bridge.bypass(True)
        if args.secondary:
            coeffs = load_hex(args.secondary)
            bridge.load_secondary_path(coeffs)
            print(f"Loaded {len(coeffs)} secondary-path coefficients")
        if args.primary:
            coeffs = load_hex(args.primary)
            bridge.load_primary_path(coeffs)
            print(f"Loaded {len(coeffs)} primary-path coefficients")
        if args.adaptive:
            coeffs = load_hex(args.adaptive)
            bridge.load_adaptive_weights(coeffs)
            print(f"Loaded {len(coeffs)} adaptive weight coefficients")

    return 0


if __name__ == "__main__":
    sys.exit(main())
