#!/usr/bin/env python3
"""Interactive ANC tuner — enable/disable ANC, adjust mu, monitor status."""

from __future__ import annotations

import argparse
import signal
import sys
import time

from anc_control.fpga_bridge import AncFpgaBridge, NoiseClass


def main() -> int:
    parser = argparse.ArgumentParser(description="Agilex 5 ANC control utility")
    parser.add_argument("--no-dry-run", action="store_true", help="Access real /dev/mem")
    parser.add_argument("--mu", type=lambda x: int(x, 0), default=0x4000, help="LMS step size Q0.16")
    parser.add_argument("--gain", type=lambda x: int(x, 0), default=0x7FFF, help="Output gain Q1.15")
    parser.add_argument("--bypass", action="store_true", help="Start in bypass mode")
    parser.add_argument("--ai-class", choices=["auto", "tonal", "broadband", "transient"], default="auto")
    parser.add_argument("--monitor", action="store_true", help="Print status every second")
    args = parser.parse_args()

    ai_map = {
        "auto": NoiseClass.AUTO,
        "tonal": NoiseClass.TONAL,
        "broadband": NoiseClass.BROADBAND,
        "transient": NoiseClass.TRANSIENT,
    }

    stop = False

    def _sigint(_sig: int, _frame: object) -> None:
        nonlocal stop
        stop = True

    signal.signal(signal.SIGINT, _sigint)

    with AncFpgaBridge(dry_run=not args.no_dry_run) as bridge:
        bridge.set_mu(args.mu)
        bridge.set_output_gain(args.gain)
        bridge.set_ai_override(ai_map[args.ai_class])

        if args.bypass:
            bridge.bypass(True)
            print("ANC bypass mode — audio passes through unprocessed")
        else:
            bridge.enable(True)
            print("ANC enabled — adaptive cancellation active")

        if args.monitor:
            print("Monitoring (Ctrl+C to stop)...")
            while not stop:
                st = bridge.read_status()
                classes = ["tonal", "broadband", "transient"]
                cls_name = classes[st.ai_class] if st.ai_class < 3 else "unknown"
                print(
                    f"  running={st.running} clip={st.clip} "
                    f"ai_class={cls_name} samples={st.sample_count}",
                    flush=True,
                )
                time.sleep(1.0)
        else:
            st = bridge.read_status()
            print(f"Status: running={st.running} samples={st.sample_count}")

        bridge.bypass(True)
        bridge.enable(False)
        print("ANC disabled, bypass enabled (safe shutdown)")

    return 0


if __name__ == "__main__":
    sys.exit(main())
