"""Memory-mapped register bridge to the ANC FPGA fabric via LWH2F.

Per the Agilex 5 SoC HPS Technical Reference Manual, the lightweight
HPS-to-FPGA (LWH2F) bridge is mapped at physical address 0x2000_0000.
"""

from __future__ import annotations

import mmap
import os
import struct
from dataclasses import dataclass
from enum import IntEnum, IntFlag
from typing import Optional


LWH2F_BASE = 0x2000_0000
LWH2F_SIZE = 2 * 1024 * 1024  # 2 MiB window


class Reg(IntEnum):
    CONTROL = 0x00
    STATUS = 0x04
    MU = 0x08
    SECONDARY_WR = 0x0C
    ADAPTIVE_WR = 0x10
    SAMPLE_COUNT = 0x14
    AI_OVERRIDE = 0x18
    OUTPUT_GAIN = 0x1C


class ControlFlag(IntFlag):
    ENABLE = 1 << 0
    BYPASS = 1 << 1
    RESET_ADAPT = 1 << 2


class NoiseClass(IntEnum):
    AUTO = 0
    TONAL = 1
    BROADBAND = 2
    TRANSIENT = 3


@dataclass
class AncStatus:
    running: bool
    clip: bool
    ai_class: int
    sample_count: int


class AncFpgaBridge:
    """Read/write ANC control registers in FPGA fabric."""

    def __init__(self, dry_run: bool = True, base: int = LWH2F_BASE) -> None:
        self._dry_run = dry_run
        self._base = base
        self._mem: Optional[mmap.mmap] = None
        self._buf = bytearray(LWH2F_SIZE)

        if not dry_run:
            fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
            self._mem = mmap.mmap(fd, LWH2F_SIZE, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=base)
            os.close(fd)

    def close(self) -> None:
        if self._mem is not None:
            self._mem.close()
            self._mem = None

    def _read32(self, offset: int) -> int:
        if self._mem is not None:
            self._mem.seek(offset)
            return struct.unpack("<I", self._mem.read(4))[0]
        return struct.unpack_from("<I", self._buf, offset)[0]

    def _write32(self, offset: int, value: int) -> None:
        if self._mem is not None:
            self._mem.seek(offset)
            self._mem.write(struct.pack("<I", value & 0xFFFFFFFF))
        else:
            struct.pack_into("<I", self._buf, offset, value & 0xFFFFFFFF)

    # --- High-level API ---

    def enable(self, on: bool = True) -> None:
        ctrl = self._read32(Reg.CONTROL)
        if on:
            ctrl |= ControlFlag.ENABLE
            ctrl &= ~ControlFlag.BYPASS
        else:
            ctrl &= ~ControlFlag.ENABLE
        self._write32(Reg.CONTROL, ctrl)

    def bypass(self, on: bool = True) -> None:
        ctrl = self._read32(Reg.CONTROL)
        if on:
            ctrl |= ControlFlag.BYPASS
        else:
            ctrl &= ~ControlFlag.BYPASS
        self._write32(Reg.CONTROL, ctrl)

    def reset_adaptation(self) -> None:
        ctrl = self._read32(Reg.CONTROL)
        self._write32(Reg.CONTROL, ctrl | ControlFlag.RESET_ADAPT)

    def set_mu(self, mu_q0_16: int) -> None:
        """Set LMS step size (Q0.16). Default 0x4000 = 0.25."""
        self._write32(Reg.MU, mu_q0_16 & 0xFFFF)

    def set_output_gain(self, gain_q1_15: int) -> None:
        """Set output gain (Q1.15). 0x7FFF ≈ unity."""
        self._write32(Reg.OUTPUT_GAIN, gain_q1_15 & 0xFFFF)

    def set_ai_override(self, noise_class: NoiseClass) -> None:
        if noise_class == NoiseClass.AUTO:
            self._write32(Reg.AI_OVERRIDE, 0)
        else:
            self._write32(Reg.AI_OVERRIDE, (1 << 31) | (int(noise_class) & 0x3))

    def read_status(self) -> AncStatus:
        raw = self._read32(Reg.STATUS)
        count = self._read32(Reg.SAMPLE_COUNT)
        return AncStatus(
            running=bool(raw & 0x1),
            clip=bool(raw & 0x2),
            ai_class=(raw >> 4) & 0x3,
            sample_count=count,
        )

    def load_secondary_path(self, coeffs: list[int], start_addr: int = 0) -> None:
        """Load secondary-path FIR coefficients (Q1.31 int32)."""
        for i, c in enumerate(coeffs):
            self._write32(Reg.SECONDARY_WR, ((start_addr + i) & 0x7F) | (c & 0xFFFFFFFF))

    def load_adaptive_weights(self, coeffs: list[int], start_addr: int = 0) -> None:
        """Pre-load adaptive filter weights (normally learned online)."""
        for i, c in enumerate(coeffs):
            self._write32(Reg.ADAPTIVE_WR, ((start_addr + i) & 0xFF) | (c & 0xFFFFFFFF))

    def __enter__(self) -> "AncFpgaBridge":
        return self

    def __exit__(self, *args: object) -> None:
        self.close()
