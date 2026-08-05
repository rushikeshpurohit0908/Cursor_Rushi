"""Thin register-level interface to a custom accelerator sitting on the
Intel Agilex 5 SoC's lightweight HPS-to-FPGA (LWH2F) bridge.

Per the Agilex 5 Hard Processor System Technical Reference Manual, the
LWH2F bridge is memory-mapped starting at physical address ``0x2000_0000``
and exposes a 2 MB window into the FPGA fabric's memory-mapped register
space. Custom soft peripherals built with Platform Designer/Quartus (e.g. a
frame classifier, an image filter, ...) show up as offsets within that
window, exactly like the ``sysid``/``led_pio``/``button_pio`` peripherals in
Intel's Golden System Reference Designs.

This module does **not** ship an FPGA bitstream -- that part is
hardware-design work done separately in Quartus/Platform Designer. What it
provides is the HPS-side software contract: a small, well-defined register
map (:class:`Registers`) plus a class (:class:`FpgaBridge`) that knows how
to talk to it, either for real via ``/dev/mem`` on the board, or via an
in-memory simulation (``dry_run=True``) so the rest of the pipeline can be
developed and tested off-hardware.
"""
from __future__ import annotations

import mmap
import os
import struct
import time
from dataclasses import dataclass
from enum import IntEnum
from types import TracebackType
from typing import Optional, Type


LWH2F_BASE_ADDRESS = 0x2000_0000
"""Physical base address of the lightweight HPS-to-FPGA bridge on Agilex 5."""

LWH2F_SPAN = 0x0020_0000
"""Size (2 MiB) of the LWH2F bridge address window."""


class Registers(IntEnum):
    """Byte offsets, relative to the peripheral's base offset within the
    LWH2F window, for the example frame-accelerator register map.

    This mirrors the kind of simple control/status register block generated
    by an Avalon-MM/AXI4-Lite PIO or custom component in Platform Designer.
    Adjust to match your actual FPGA IP core.
    """

    CONTROL = 0x00       # bit0: start (self-clearing on the FPGA side)
    STATUS = 0x04         # bit0: done, bit1: busy, bit2: error
    FRAME_WIDTH = 0x08
    FRAME_HEIGHT = 0x0C
    FRAME_ADDR_LO = 0x10  # low 32 bits of the frame buffer's bus address
    FRAME_ADDR_HI = 0x14  # high 32 bits (for >4GB addressable systems)
    FRAME_SIZE = 0x18     # frame buffer size in bytes
    FRAME_COUNTER = 0x1C  # incremented by the FPGA for every processed frame


class ControlBits(IntEnum):
    START = 1 << 0


class StatusBits(IntEnum):
    DONE = 1 << 0
    BUSY = 1 << 1
    ERROR = 1 << 2


class FpgaBridgeTimeout(RuntimeError):
    """Raised when the FPGA accelerator does not signal completion in time."""


class FpgaBridge:
    """Read/write registers of a peripheral behind the LWH2F bridge.

    Parameters
    ----------
    peripheral_offset:
        Offset of the target peripheral within the LWH2F window (i.e. the
        value you'd add to ``LWH2F_BASE_ADDRESS`` to get its physical
        address). Defaults to ``0x0`` -- override to match your design.
    base_address:
        Physical base address of the LWH2F bridge. Defaults to the Agilex 5
        value (``0x2000_0000``); override for other SoC FPGA families
        (e.g. Cyclone V / Arria 10 use ``0xFF20_0000``).
    span:
        Size, in bytes, of the mmap'd window.
    dry_run:
        When ``True`` (the default in this repo's CLI unless overridden),
        no real ``/dev/mem`` access happens. Instead, register reads/writes
        operate on an in-process byte buffer and :meth:`wait_done`
        immediately reports completion. This lets the receiver pipeline run
        end-to-end on any Linux machine for development/testing.
    """

    def __init__(
        self,
        peripheral_offset: int = 0x0,
        base_address: int = LWH2F_BASE_ADDRESS,
        span: int = LWH2F_SPAN,
        dry_run: bool = False,
    ) -> None:
        self.peripheral_offset = peripheral_offset
        self.base_address = base_address
        self.span = span
        self.dry_run = dry_run
        self._mem: Optional[mmap.mmap] = None
        self._fd: Optional[int] = None
        self._sim_buffer = bytearray(span) if dry_run else None

    def open(self) -> "FpgaBridge":
        if self.dry_run:
            return self
        self._fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
        self._mem = mmap.mmap(
            self._fd,
            self.span,
            mmap.MAP_SHARED,
            mmap.PROT_READ | mmap.PROT_WRITE,
            offset=self.base_address,
        )
        return self

    def close(self) -> None:
        if self.dry_run:
            return
        if self._mem is not None:
            self._mem.close()
            self._mem = None
        if self._fd is not None:
            os.close(self._fd)
            self._fd = None

    def __enter__(self) -> "FpgaBridge":
        return self.open()

    def __exit__(
        self,
        exc_type: Optional[Type[BaseException]],
        exc: Optional[BaseException],
        tb: Optional[TracebackType],
    ) -> None:
        self.close()

    def read32(self, offset: int) -> int:
        address = self.peripheral_offset + offset
        if self.dry_run:
            assert self._sim_buffer is not None
            return struct.unpack_from("<I", self._sim_buffer, address)[0]
        assert self._mem is not None, "FpgaBridge must be opened before use"
        return struct.unpack_from("<I", self._mem, address)[0]

    def write32(self, offset: int, value: int) -> None:
        address = self.peripheral_offset + offset
        packed = struct.pack("<I", value & 0xFFFFFFFF)
        if self.dry_run:
            assert self._sim_buffer is not None
            self._sim_buffer[address : address + 4] = packed
            # In dry-run mode, simulate the accelerator finishing instantly.
            if offset == Registers.CONTROL and value & ControlBits.START:
                struct.pack_into("<I", self._sim_buffer, self.peripheral_offset + Registers.STATUS, StatusBits.DONE)
                counter = struct.unpack_from("<I", self._sim_buffer, self.peripheral_offset + Registers.FRAME_COUNTER)[0]
                struct.pack_into("<I", self._sim_buffer, self.peripheral_offset + Registers.FRAME_COUNTER, counter + 1)
            return
        assert self._mem is not None, "FpgaBridge must be opened before use"
        self._mem[address : address + 4] = packed

    def submit_frame(self, width: int, height: int, buffer_addr: int, buffer_size: int) -> None:
        """Describe a decoded frame to the FPGA accelerator and kick it off."""
        self.write32(Registers.FRAME_WIDTH, width)
        self.write32(Registers.FRAME_HEIGHT, height)
        self.write32(Registers.FRAME_ADDR_LO, buffer_addr & 0xFFFFFFFF)
        self.write32(Registers.FRAME_ADDR_HI, (buffer_addr >> 32) & 0xFFFFFFFF)
        self.write32(Registers.FRAME_SIZE, buffer_size)
        self.write32(Registers.CONTROL, ControlBits.START)

    def is_done(self) -> bool:
        return bool(self.read32(Registers.STATUS) & StatusBits.DONE)

    def is_error(self) -> bool:
        return bool(self.read32(Registers.STATUS) & StatusBits.ERROR)

    def wait_done(self, timeout_s: float = 1.0, poll_interval_s: float = 0.001) -> int:
        """Block until the accelerator signals completion.

        Returns the current frame counter value on success, raises
        :class:`FpgaBridgeTimeout` if ``timeout_s`` elapses first.
        """
        deadline = time.monotonic() + timeout_s
        while not self.is_done():
            if time.monotonic() >= deadline:
                raise FpgaBridgeTimeout(
                    f"FPGA accelerator did not complete within {timeout_s}s"
                )
            time.sleep(poll_interval_s)
        return self.read32(Registers.FRAME_COUNTER)


@dataclass(frozen=True)
class FrameDescriptor:
    """Metadata describing a decoded video frame ready to hand to the FPGA."""

    width: int
    height: int
    buffer_addr: int
    buffer_size: int
