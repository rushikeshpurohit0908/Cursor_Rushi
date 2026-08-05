import pytest

from agilex5_receiver.fpga_bridge import (
    LWH2F_BASE_ADDRESS,
    ControlBits,
    FpgaBridge,
    FpgaBridgeTimeout,
    Registers,
    StatusBits,
)


def test_default_base_address_matches_agilex5_lwh2f():
    assert LWH2F_BASE_ADDRESS == 0x2000_0000


def test_dry_run_read_write_roundtrip():
    with FpgaBridge(dry_run=True) as bridge:
        bridge.write32(Registers.FRAME_WIDTH, 1920)
        bridge.write32(Registers.FRAME_HEIGHT, 1080)
        assert bridge.read32(Registers.FRAME_WIDTH) == 1920
        assert bridge.read32(Registers.FRAME_HEIGHT) == 1080


def test_dry_run_submit_frame_completes_and_increments_counter():
    with FpgaBridge(dry_run=True) as bridge:
        assert bridge.read32(Registers.FRAME_COUNTER) == 0

        bridge.submit_frame(width=640, height=480, buffer_addr=0xDEADBEEF, buffer_size=640 * 480 * 3)

        assert bridge.is_done()
        assert not bridge.is_error()
        assert bridge.read32(Registers.FRAME_WIDTH) == 640
        assert bridge.read32(Registers.FRAME_HEIGHT) == 480
        assert bridge.read32(Registers.FRAME_ADDR_LO) == 0xDEADBEEF
        assert bridge.read32(Registers.FRAME_SIZE) == 640 * 480 * 3

        counter = bridge.wait_done(timeout_s=0.5)
        assert counter == 1

        bridge.submit_frame(width=640, height=480, buffer_addr=0xDEADBEEF, buffer_size=640 * 480 * 3)
        counter = bridge.wait_done(timeout_s=0.5)
        assert counter == 2


def test_wait_done_times_out_when_never_started():
    with FpgaBridge(dry_run=True) as bridge:
        with pytest.raises(FpgaBridgeTimeout):
            bridge.wait_done(timeout_s=0.05, poll_interval_s=0.01)


def test_peripheral_offset_isolates_registers():
    with FpgaBridge(dry_run=True, peripheral_offset=0x1000, span=0x2000) as bridge:
        bridge.write32(Registers.FRAME_WIDTH, 42)
        assert bridge.read32(Registers.FRAME_WIDTH) == 42


def test_control_and_status_bit_values():
    assert ControlBits.START == 0b1
    assert StatusBits.DONE == 0b001
    assert StatusBits.BUSY == 0b010
    assert StatusBits.ERROR == 0b100
