#!/usr/bin/env python3
"""Receive the OAK camera stream (see ``oak_streamer``) on the HPS (Linux)
side of an Intel Agilex 5 SoC FPGA board, decode frames, and dispatch each
one to the FPGA fabric through the lightweight HPS-to-FPGA bridge.

Frame decoding uses OpenCV's FFmpeg backend (``cv2.VideoCapture``), which
transparently understands both the RTSP and UDP/MPEG-TS URLs produced by
``oak_streamer.stream_sender``.

Run with ``--dry-run`` (the default) to exercise the full receive loop
without requiring root access to ``/dev/mem`` or real Agilex 5 hardware --
useful for development and for this repository's automated tests.
"""
from __future__ import annotations

import argparse
import sys
import time
from dataclasses import dataclass

from agilex5_receiver.fpga_bridge import FpgaBridge, FpgaBridgeTimeout, LWH2F_BASE_ADDRESS


@dataclass(frozen=True)
class ReceiverConfig:
    listen_port: int = 5000
    protocol: str = "rtsp"  # "rtsp" or "udp"
    rtsp_path: str = "mystream"
    rtsp_host: str = "0.0.0.0"
    dry_run: bool = True
    fpga_base_address: int = LWH2F_BASE_ADDRESS
    fpga_peripheral_offset: int = 0x0
    max_frames: int = 0  # 0 = run forever

    @property
    def source_url(self) -> str:
        if self.protocol == "udp":
            return f"udp://0.0.0.0:{self.listen_port}"
        if self.protocol == "rtsp":
            return f"rtsp://{self.rtsp_host}:{self.listen_port}/{self.rtsp_path}"
        raise ValueError(f"Unsupported protocol: {self.protocol!r}")


def open_capture(config: ReceiverConfig):
    """Open the video source. Requires the ``opencv-python`` package."""
    import cv2  # noqa: WPS433

    capture = cv2.VideoCapture(config.source_url, cv2.CAP_FFMPEG)
    if not capture.isOpened():
        raise RuntimeError(f"Could not open video source: {config.source_url}")
    return capture


def run(config: ReceiverConfig) -> None:
    capture = open_capture(config)

    bridge = FpgaBridge(
        peripheral_offset=config.fpga_peripheral_offset,
        base_address=config.fpga_base_address,
        dry_run=config.dry_run,
    )

    frames_processed = 0
    try:
        with bridge:
            print(
                f"Receiving from {config.source_url} "
                f"(dry_run={config.dry_run}, fpga_base=0x{config.fpga_base_address:08X})",
                file=sys.stderr,
            )
            while True:
                ok, frame = capture.read()
                if not ok:
                    print("Stream ended or frame drop, retrying...", file=sys.stderr)
                    time.sleep(0.1)
                    continue

                height, width = frame.shape[:2]
                buffer_size = frame.nbytes
                buffer_addr = frame.ctypes.data  # HPS virtual address of the decoded frame

                bridge.submit_frame(width, height, buffer_addr, buffer_size)
                try:
                    counter = bridge.wait_done(timeout_s=1.0)
                except FpgaBridgeTimeout as exc:
                    print(f"Warning: {exc}", file=sys.stderr)
                    continue

                frames_processed += 1
                if frames_processed % 30 == 0:
                    print(
                        f"Processed {frames_processed} frames "
                        f"({width}x{height}), fpga frame counter={counter}",
                        file=sys.stderr,
                    )

                if config.max_frames and frames_processed >= config.max_frames:
                    break
    except KeyboardInterrupt:
        print("Interrupted, shutting down...", file=sys.stderr)
    finally:
        capture.release()


def parse_args(argv: list[str] | None = None) -> ReceiverConfig:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--listen-port", type=int, default=5000)
    parser.add_argument("--protocol", choices=["rtsp", "udp"], default="rtsp")
    parser.add_argument("--rtsp-path", default="mystream")
    parser.add_argument("--rtsp-host", default="0.0.0.0")
    parser.add_argument(
        "--dry-run",
        dest="dry_run",
        action="store_true",
        default=True,
        help="Simulate the FPGA bridge instead of touching /dev/mem (default).",
    )
    parser.add_argument(
        "--no-dry-run",
        dest="dry_run",
        action="store_false",
        help="Talk to real Agilex 5 hardware via /dev/mem (requires root).",
    )
    parser.add_argument(
        "--fpga-base-address",
        type=lambda v: int(v, 0),
        default=LWH2F_BASE_ADDRESS,
        help="Physical base address of the LWH2F bridge (default: Agilex 5's 0x20000000).",
    )
    parser.add_argument(
        "--fpga-peripheral-offset",
        type=lambda v: int(v, 0),
        default=0x0,
        help="Offset of the target peripheral within the LWH2F window.",
    )
    parser.add_argument(
        "--max-frames",
        type=int,
        default=0,
        help="Stop after processing this many frames (0 = run forever).",
    )
    args = parser.parse_args(argv)
    return ReceiverConfig(
        listen_port=args.listen_port,
        protocol=args.protocol,
        rtsp_path=args.rtsp_path,
        rtsp_host=args.rtsp_host,
        dry_run=args.dry_run,
        fpga_base_address=args.fpga_base_address,
        fpga_peripheral_offset=args.fpga_peripheral_offset,
        max_frames=args.max_frames,
    )


def main(argv: list[str] | None = None) -> None:
    config = parse_args(argv)
    run(config)


if __name__ == "__main__":
    main()
