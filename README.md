# Cursor_Rushi — Intel OAK Stream + Agilex 5

This project streams live H.264 video from a **Luxonis OAK** camera (built
around Intel Movidius VPUs) over the network to an **Intel Agilex 5 SoC
FPGA** development board, where it is decoded on the HPS (Hard Processor
System / Linux) side and handed off to the FPGA fabric through the
lightweight HPS-to-FPGA (LWH2F) bridge for hardware-accelerated processing.

```
┌───────────────────────┐        H.264 / RTP over UDP        ┌───────────────────────────────┐
│   Host PC / Edge box   │ ─────────────────────────────────▶ │      Intel Agilex 5 SoC        │
│                        │                                     │                                │
│  OAK camera (DepthAI)  │                                     │  HPS (Linux) receives + decodes│
│  oak_streamer/         │                                     │  frames, then drives the FPGA  │
│                        │                                     │  fabric via the LWH2F bridge   │
└───────────────────────┘                                     │  agilex5_receiver/             │
                                                                 └───────────────────────────────┘
```

See [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full design,
hardware/network setup, and details on the HPS↔FPGA register interface.

## Repository layout

| Path                   | Description                                                                 |
|------------------------|-------------------------------------------------------------------------------|
| `oak_streamer/`        | Runs on the machine connected to the OAK camera. Captures + H.264-encodes video and streams it over UDP/RTSP to the Agilex 5 board. |
| `agilex5_receiver/`    | Runs on the Agilex 5 SoC's HPS (embedded Linux). Receives the stream, decodes frames, and forwards work to the FPGA fabric through the lightweight HPS-to-FPGA bridge. |
| `docs/`                | Architecture notes and setup guide.                                          |
| `tests/`               | Unit tests that exercise the pure-Python logic without requiring the camera or the FPGA board to be attached. |

## Quick start

### 1. On the OAK host

```bash
pip install -r oak_streamer/requirements.txt
python -m oak_streamer.stream_sender --target-ip 192.168.1.50 --target-port 5000
```

### 2. On the Agilex 5 SoC (HPS / Linux)

```bash
pip install -r agilex5_receiver/requirements.txt
python -m agilex5_receiver.receive_stream --listen-port 5000
```

By default the receiver runs with `--dry-run`, which simulates the
HPS-to-FPGA register interface instead of touching `/dev/mem`, so it can be
exercised on any Linux machine (including this repository's CI) without
Agilex 5 hardware present. Drop `--dry-run` when running on the actual
board.

## Running the tests

```bash
pip install -r oak_streamer/requirements.txt -r agilex5_receiver/requirements.txt
python -m pytest tests/ -v
```
