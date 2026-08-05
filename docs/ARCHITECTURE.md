# Architecture: Intel OAK stream → Intel Agilex 5 SoC FPGA

## Goal

Capture live video from an Intel-powered Luxonis **OAK** camera and pipe it
to an **Intel Agilex 5 SoC FPGA** board so the frames can be handed off to
custom logic implemented in the FPGA fabric (e.g. an image filter, a CNN
accelerator, a frame-differencing core, ...).

## Data path

```
 OAK camera            Host PC / edge box              Network            Agilex 5 SoC (HPS, Linux)                 Agilex 5 FPGA fabric
┌───────────┐   USB3   ┌─────────────────────┐   H.264   ┌───────────┐   ┌───────────────────────────┐  LWH2F AXI  ┌───────────────────┐
│  Sensor + │ ───────▶ │ oak_streamer         │ ────────▶ │  RTSP/UDP │─▶│ agilex5_receiver           │ ──────────▶ │ Custom accelerator │
│  Movidius │          │  - DepthAI pipeline  │  over IP  │           │  │  - cv2.VideoCapture decode │  0x2000_0000 │ (Platform Designer/│
│  VPU      │          │  - on-device H.264   │           │           │  │  - FpgaBridge register I/O │             │  Quartus, built    │
└───────────┘          │  - ffmpeg remux      │           │           │  └───────────────────────────┘             │  separately)       │
                        └─────────────────────┘           └───────────┘                                            └───────────────────┘
```

1. **Capture & encode (`oak_streamer/stream_sender.py`)** — The OAK
   camera's on-board video encoder produces an H.264 Annex-B elementary
   stream directly (no host-side CPU encoding). An `ffmpeg` subprocess
   remuxes (`-c copy`, zero re-encode) that stream into RTSP (via a
   [MediaMTX](https://github.com/bluenviron/mediamtx) relay) or raw UDP/MPEG-TS,
   whichever fits your network setup.

2. **Transport** — Plain IP transport (RTSP or UDP) between the OAK host
   and the Agilex 5 board's HPS Ethernet interface. No custom protocol —
   any standard tool (`ffplay`, VLC, GStreamer) can also tap the same
   stream for debugging.

3. **Decode & dispatch (`agilex5_receiver/receive_stream.py`)** — Running on
   the Agilex 5's Hard Processor System (Cortex-A Linux), this decodes the
   incoming stream with OpenCV's FFmpeg backend and, for every decoded
   frame, calls into `agilex5_receiver/fpga_bridge.py` to describe the frame
   (width, height, buffer address/size) to the FPGA fabric and trigger
   processing.

4. **HPS↔FPGA register interface (`agilex5_receiver/fpga_bridge.py`)** — Per
   the *Agilex 5 SoC Hard Processor System Technical Reference Manual*, the
   lightweight HPS-to-FPGA (LWH2F) bridge is memory-mapped at physical
   address `0x2000_0000` with a 2 MiB window, exposing memory-mapped
   control/status registers implemented in the FPGA fabric (this is the
   same bridge Intel's own Golden System Reference Designs use for
   `sysid`/`led_pio`/`button_pio`-style peripherals). `FpgaBridge` `mmap`s
   `/dev/mem` at that address and provides a small register map:

   | Offset | Register        | Meaning                                   |
   |--------|-----------------|---------------------------------------------|
   | 0x00   | `CONTROL`       | bit0 = start (write to kick off processing)  |
   | 0x04   | `STATUS`        | bit0 = done, bit1 = busy, bit2 = error        |
   | 0x08   | `FRAME_WIDTH`   | frame width in pixels                         |
   | 0x0C   | `FRAME_HEIGHT`  | frame height in pixels                        |
   | 0x10   | `FRAME_ADDR_LO` | frame buffer address, low 32 bits              |
   | 0x14   | `FRAME_ADDR_HI` | frame buffer address, high 32 bits             |
   | 0x18   | `FRAME_SIZE`    | frame buffer size in bytes                    |
   | 0x1C   | `FRAME_COUNTER` | incremented by the FPGA per processed frame   |

   This register map is a *contract*, not a bitstream: you still need to
   implement a matching Avalon-MM/AXI4-Lite peripheral for your accelerator
   in Platform Designer/Quartus and wire it onto the LWH2F bridge. Adjust
   `Registers`/offsets in `fpga_bridge.py` to match whatever you actually
   build.

## Development without hardware

Both ends of the pipeline can be exercised without physical hardware:

* `agilex5_receiver` defaults to `--dry-run`, which swaps the `/dev/mem`
  `mmap` for an in-process byte buffer and simulates the accelerator
  completing instantly. This lets you develop/test the receive loop (and
  its unit tests) on a laptop or in CI.
* `oak_streamer`'s pure helpers (`build_ffmpeg_command`, `StreamConfig`,
  CLI parsing) have no dependency on the camera and are unit tested
  directly; only `run()`/`build_pipeline()` require the physical camera and
  the `depthai` package.

## Physical / network setup checklist

1. Connect the OAK camera to the host PC via USB3 (or use a PoE OAK camera
   directly on the same network as the Agilex 5 board).
2. Connect the Agilex 5 SoC development kit's HPS Ethernet port to the same
   network/switch as the OAK host.
3. If using RTSP, run a [MediaMTX](https://github.com/bluenviron/mediamtx)
   instance reachable by both sides (it can run on either machine, or a
   third one) and point `--target-ip`/`--target-port` and
   `--rtsp-host`/`--listen-port` at it. If using UDP, point
   `oak_streamer` directly at the Agilex 5 board's IP.
4. On the Agilex 5 board, build/load your custom accelerator's FPGA
   bitstream and matching device tree overlay (if any) so that the LWH2F
   window is safe to `mmap` from Linux, then run `agilex5_receiver` with
   `--no-dry-run`.
