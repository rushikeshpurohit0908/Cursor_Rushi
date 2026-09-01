"""I2C init tables for SSM2518 and WM8960 (mirrored in rtl/codec_init.v)."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class CodecProfile:
    name: str
    i2c_addr: int
    init: tuple[tuple[int, int], ...]


SSM2518 = CodecProfile(
    name="SSM2518",
    i2c_addr=0x34,
    init=(
        (0x00, 0x80),  # software reset
        (0x01, 0x00),  # power up
        (0x02, 0x02),  # clock: 256fs slave
        (0x03, 0x02),  # I2S 24-bit
        (0x04, 0x00),  # default mapping
        (0x06, 0x00),  # left 0 dB
        (0x07, 0x00),  # right 0 dB
        (0x08, 0x00),  # unmute
    ),
)

WM8960 = CodecProfile(
    name="WM8960",
    i2c_addr=0x1A,
    init=(
        (0x0F, 0x00),  # reset
        (0x19, 0x16),  # VMID / VREF
        (0x1A, 0x00),  # power mgmt 2
        (0x04, 0x00),  # clocking
        (0x07, 0x02),  # I2S 24-bit
        (0x02, 0x7F),  # LOUT1
        (0x03, 0x7F),  # ROUT1
        (0x2F, 0x00),  # mixer
        (0x22, 0x01),  # LOUT2 mixer
    ),
)

CODECS = {"ssm2518": SSM2518, "wm8960": WM8960}


def program_codec(bridge, profile: CodecProfile) -> None:
    """Write the init table through the fabric I2C master."""
    for reg, val in profile.init:
        bridge.i2c_write(profile.i2c_addr, reg, val)
