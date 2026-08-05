#!/usr/bin/env python3
"""Stream H.264-encoded video from an Intel/Luxonis OAK camera to a remote
receiver (e.g. the HPS side of an Intel Agilex 5 SoC FPGA board) over
RTSP/UDP.

The heavy lifting is done by:

  * ``depthai``  -- talks to the OAK camera and produces an H.264 bitstream
    directly on-device (using the camera's built-in video encoder, so the
    host CPU never has to encode video).
  * ``ffmpeg``   -- repackages the raw H.264 Annex-B bitstream coming from
    the camera into an RTSP stream that any standard client (ffplay, VLC,
    GStreamer, the ``agilex5_receiver`` package in this repo, ...) can
    consume.

The module is split into small, independently testable pieces:

  * :func:`build_ffmpeg_command` builds the ffmpeg argv list. Pure function,
    no I/O, easy to unit test.
  * :func:`build_pipeline` builds the DepthAI pipeline object. Requires the
    ``depthai`` package.
  * :func:`run` wires everything together and blocks forever, streaming
    frames until interrupted.
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from dataclasses import dataclass


@dataclass(frozen=True)
class StreamConfig:
    """Configuration for capturing on the OAK camera and streaming out."""

    target_ip: str = "127.0.0.1"
    target_port: int = 5000
    fps: int = 30
    bitrate_kbps: int = 4000
    width: int = 1920
    height: int = 1080
    protocol: str = "rtsp"  # "rtsp" or "udp"
    rtsp_path: str = "mystream"

    @property
    def output_url(self) -> str:
        if self.protocol == "udp":
            return f"udp://{self.target_ip}:{self.target_port}?pkt_size=1316"
        if self.protocol == "rtsp":
            return f"rtsp://{self.target_ip}:{self.target_port}/{self.rtsp_path}"
        raise ValueError(f"Unsupported protocol: {self.protocol!r}")


def build_ffmpeg_command(config: StreamConfig) -> list[str]:
    """Return the ffmpeg argv used to repackage the raw H.264 bitstream.

    ffmpeg reads the Annex-B H.264 elementary stream from stdin (written to
    by the caller as frames arrive from the camera) and remuxes it (no
    re-encoding, ``-c copy``) into the configured output protocol.
    """
    output_format = "rtsp" if config.protocol == "rtsp" else "mpegts"
    cmd = [
        "ffmpeg",
        "-loglevel", "warning",
        "-fflags", "nobuffer",
        "-flags", "low_delay",
        "-f", "h264",
        "-framerate", str(config.fps),
        "-i", "-",
        "-c", "copy",
        "-f", output_format,
    ]
    if config.protocol == "udp":
        cmd += ["-flush_packets", "1"]
    cmd.append(config.output_url)
    return cmd


def build_pipeline(config: StreamConfig):
    """Build the DepthAI pipeline: color camera -> on-device H.264 encoder.

    Imported lazily so the rest of this module (and its pure helpers) can be
    unit tested on machines without the ``depthai`` package / camera
    attached.
    """
    import depthai as dai  # noqa: WPS433 (intentional local import)

    pipeline = dai.Pipeline()

    cam = pipeline.create(dai.node.ColorCamera)
    cam.setBoardSocket(dai.CameraBoardSocket.CAM_A)
    cam.setInterleaved(False)
    cam.setFps(config.fps)
    cam.setVideoSize(config.width, config.height)

    encoder = pipeline.create(dai.node.VideoEncoder)
    encoder.setDefaultProfilePreset(config.fps, dai.VideoEncoderProperties.Profile.H264_MAIN)
    encoder.setBitrateKbps(config.bitrate_kbps)
    encoder.setNumBFrames(0)
    cam.video.link(encoder.input)

    xout = pipeline.create(dai.node.XLinkOut)
    xout.setStreamName("encoded")
    encoder.bitstream.link(xout.input)

    return pipeline


def run(config: StreamConfig) -> None:
    """Start capturing on the OAK camera and stream frames to ``ffmpeg``."""
    import depthai as dai  # noqa: WPS433

    ffmpeg_cmd = build_ffmpeg_command(config)
    print(f"Starting ffmpeg: {' '.join(ffmpeg_cmd)}", file=sys.stderr)
    process = subprocess.Popen(ffmpeg_cmd, stdin=subprocess.PIPE)

    pipeline = build_pipeline(config)

    try:
        with dai.Device(pipeline) as device:
            queue = device.getOutputQueue(name="encoded", maxSize=30, blocking=True)
            print(
                f"Streaming from OAK camera to {config.output_url} "
                f"({config.width}x{config.height}@{config.fps}fps, "
                f"{config.bitrate_kbps}kbps)",
                file=sys.stderr,
            )
            while device.isPipelineRunning():
                packet = queue.get()
                assert process.stdin is not None
                process.stdin.write(packet.getData())
                process.stdin.flush()
    except KeyboardInterrupt:
        print("Interrupted, shutting down...", file=sys.stderr)
    finally:
        if process.stdin is not None:
            process.stdin.close()
        process.wait()


def parse_args(argv: list[str] | None = None) -> StreamConfig:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--target-ip", default="127.0.0.1", help="IP of the Agilex 5 receiver")
    parser.add_argument("--target-port", type=int, default=5000, help="Destination port")
    parser.add_argument("--fps", type=int, default=30, help="Capture frame rate")
    parser.add_argument("--bitrate-kbps", type=int, default=4000, help="H.264 target bitrate")
    parser.add_argument("--width", type=int, default=1920, help="Capture width")
    parser.add_argument("--height", type=int, default=1080, help="Capture height")
    parser.add_argument(
        "--protocol", choices=["rtsp", "udp"], default="rtsp", help="Transport protocol"
    )
    parser.add_argument("--rtsp-path", default="mystream", help="RTSP mount path")
    args = parser.parse_args(argv)
    return StreamConfig(
        target_ip=args.target_ip,
        target_port=args.target_port,
        fps=args.fps,
        bitrate_kbps=args.bitrate_kbps,
        width=args.width,
        height=args.height,
        protocol=args.protocol,
        rtsp_path=args.rtsp_path,
    )


def main(argv: list[str] | None = None) -> None:
    config = parse_args(argv)
    run(config)


if __name__ == "__main__":
    main()
