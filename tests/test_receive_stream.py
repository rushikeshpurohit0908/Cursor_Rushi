from agilex5_receiver.fpga_bridge import LWH2F_BASE_ADDRESS
from agilex5_receiver.receive_stream import ReceiverConfig, parse_args


def test_source_url_rtsp():
    config = ReceiverConfig(listen_port=8554, protocol="rtsp", rtsp_host="0.0.0.0", rtsp_path="mystream")
    assert config.source_url == "rtsp://0.0.0.0:8554/mystream"


def test_source_url_udp():
    config = ReceiverConfig(listen_port=5000, protocol="udp")
    assert config.source_url == "udp://0.0.0.0:5000"


def test_parse_args_defaults_are_dry_run_and_agilex5_base_address():
    config = parse_args([])
    assert config.dry_run is True
    assert config.fpga_base_address == LWH2F_BASE_ADDRESS
    assert config.listen_port == 5000
    assert config.protocol == "rtsp"


def test_parse_args_no_dry_run_flag():
    config = parse_args(["--no-dry-run"])
    assert config.dry_run is False


def test_parse_args_custom_fpga_base_address_hex():
    config = parse_args(["--fpga-base-address", "0xFF200000"])
    assert config.fpga_base_address == 0xFF200000


def test_parse_args_max_frames():
    config = parse_args(["--max-frames", "10"])
    assert config.max_frames == 10
