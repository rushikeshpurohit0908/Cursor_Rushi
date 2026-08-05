from oak_streamer.stream_sender import StreamConfig, build_ffmpeg_command, parse_args


def test_output_url_rtsp():
    config = StreamConfig(target_ip="192.168.1.50", target_port=8554, rtsp_path="mystream")
    assert config.output_url == "rtsp://192.168.1.50:8554/mystream"


def test_output_url_udp():
    config = StreamConfig(target_ip="192.168.1.50", target_port=5000, protocol="udp")
    assert config.output_url == "udp://192.168.1.50:5000?pkt_size=1316"


def test_output_url_invalid_protocol():
    config = StreamConfig(protocol="rtmp")
    try:
        config.output_url
    except ValueError:
        pass
    else:
        raise AssertionError("Expected ValueError for unsupported protocol")


def test_build_ffmpeg_command_rtsp_contains_output_url():
    config = StreamConfig(target_ip="10.0.0.5", target_port=8554, protocol="rtsp", rtsp_path="live")
    cmd = build_ffmpeg_command(config)
    assert cmd[0] == "ffmpeg"
    assert cmd[-1] == "rtsp://10.0.0.5:8554/live"
    assert "-f" in cmd and "rtsp" in cmd


def test_build_ffmpeg_command_udp_uses_mpegts_and_flush():
    config = StreamConfig(target_ip="10.0.0.5", target_port=5000, protocol="udp")
    cmd = build_ffmpeg_command(config)
    assert "mpegts" in cmd
    assert "-flush_packets" in cmd
    assert cmd[-1] == "udp://10.0.0.5:5000?pkt_size=1316"


def test_build_ffmpeg_command_uses_configured_fps():
    config = StreamConfig(fps=60)
    cmd = build_ffmpeg_command(config)
    fps_index = cmd.index("-framerate") + 1
    assert cmd[fps_index] == "60"


def test_parse_args_defaults():
    config = parse_args([])
    assert config.target_ip == "127.0.0.1"
    assert config.target_port == 5000
    assert config.protocol == "rtsp"


def test_parse_args_overrides():
    config = parse_args(
        [
            "--target-ip", "192.168.1.50",
            "--target-port", "9000",
            "--fps", "60",
            "--bitrate-kbps", "8000",
            "--width", "1280",
            "--height", "720",
            "--protocol", "udp",
        ]
    )
    assert config.target_ip == "192.168.1.50"
    assert config.target_port == 9000
    assert config.fps == 60
    assert config.bitrate_kbps == 8000
    assert config.width == 1280
    assert config.height == 720
    assert config.protocol == "udp"
