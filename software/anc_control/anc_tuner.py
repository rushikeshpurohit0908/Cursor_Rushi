#!/usr/bin/env python3
"""Interactive ANC tuner — mode, mu, codec init, status monitor."""

from __future__ import annotations

import argparse
import signal
import sys
import time

from anc_control.codecs import CODECS, program_codec
from anc_control.fpga_bridge import AncFpgaBridge, AncMode, NoiseClass


def main() -> int:
    parser = argparse.ArgumentParser(description="Agilex 5 ANC control utility")
    parser.add_argument("--no-dry-run", action="store_true")
    parser.add_argument("--mu", type=lambda x: int(x, 0), default=0x4000)
    parser.add_argument("--leak", type=lambda x: int(x, 0), default=0x0008)
    parser.add_argument("--gain", type=lambda x: int(x, 0), default=0x7FFF)
    parser.add_argument("--bypass", action="store_true")
    parser.add_argument(
        "--mode",
        choices=["hybrid", "ff-frozen", "ff-virtual", "calib"],
        default="hybrid",
        help="hybrid=error mic, ff-frozen=no error mic (pretrained w), "
        "ff-virtual=internal-model error, calib=tone passthrough",
    )
    parser.add_argument("--ai-class", choices=["auto", "tonal", "broadband", "transient"], default="auto")
    parser.add_argument("--codec", choices=["none", "ssm2518", "wm8960"], default="none")
    parser.add_argument("--notch", action="store_true")
    parser.add_argument("--monitor", action="store_true")
    args = parser.parse_args()

    mode_map = {
        "hybrid": AncMode.HYBRID,
        "ff-frozen": AncMode.FF_FROZEN,
        "ff-virtual": AncMode.FF_VIRTUAL,
        "calib": AncMode.CALIB,
    }
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
        if args.codec != "none":
            if args.no_dry_run:
                bridge.start_codec_init()
            else:
                program_codec(bridge, CODECS[args.codec])
            print(f"Codec init ({args.codec}) issued")

        bridge.set_mu(args.mu)
        bridge.set_leak(args.leak)
        bridge.set_output_gain(args.gain)
        bridge.set_mode(mode_map[args.mode])
        bridge.set_ai_override(ai_map[args.ai_class])
        bridge.set_notch(args.notch)

        if args.bypass:
            bridge.bypass(True)
            print("ANC bypass — audio unprocessed")
        else:
            bridge.enable(True)
            print(f"ANC enabled  mode={args.mode}")

        if args.monitor:
            print("Monitoring (Ctrl+C to stop)...")
            while not stop:
                st = bridge.read_status()
                classes = ["tonal", "broadband", "transient"]
                cls_name = classes[st.ai_class] if st.ai_class < 3 else "unknown"
                print(
                    f"  run={st.running} clip={st.clip} codec={st.codec_ready} "
                    f"ai={cls_name} n={st.sample_count}",
                    flush=True,
                )
                time.sleep(1.0)
        else:
            st = bridge.read_status()
            print(f"Status: running={st.running} samples={st.sample_count}")

        bridge.bypass(True)
        bridge.enable(False)
        print("ANC disabled, bypass enabled")

    return 0


if __name__ == "__main__":
    sys.exit(main())
