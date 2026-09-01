"""Python golden model of FxLMS — reference for RTL / offline tuning."""

from __future__ import annotations

from dataclasses import dataclass, field

import math


@dataclass
class FxLMS:
    taps: int = 256
    secondary_taps: int = 128
    mu: float = 0.01
    leak: float = 0.0
    mode: str = "hybrid"  # hybrid | ff_frozen | ff_virtual

    w: list[float] = field(default_factory=list)
    s_hat: list[float] = field(default_factory=list)
    p_hat: list[float] = field(default_factory=list)
    x_buf: list[float] = field(default_factory=list)
    xf_buf: list[float] = field(default_factory=list)
    y_buf: list[float] = field(default_factory=list)

    def __post_init__(self) -> None:
        self.w = [0.0] * self.taps
        self.s_hat = [1.0] + [0.0] * (self.secondary_taps - 1)
        self.p_hat = list(self.s_hat)
        self.x_buf = [0.0] * self.taps
        self.xf_buf = [0.0] * self.taps
        self.y_buf = [0.0] * self.secondary_taps

    def _dot(self, a: list[float], b: list[float], n: int) -> float:
        return sum(a[i] * b[i] for i in range(n))

    def _fir(self, taps: list[float], buf: list[float]) -> float:
        return self._dot(taps, buf, len(taps))

    def step(self, x: float, e_mic: float = 0.0) -> float:
        self.x_buf = [x] + self.x_buf[:-1]
        y = self._dot(self.w, self.x_buf, self.taps)
        self.y_buf = [y] + self.y_buf[:-1]

        xf = self._fir(self.s_hat, self.x_buf[: self.secondary_taps])
        self.xf_buf = [xf] + self.xf_buf[:-1]

        if self.mode == "hybrid":
            e = e_mic
        elif self.mode == "ff_frozen":
            e = 0.0
        else:
            px = self._fir(self.p_hat, self.x_buf[: self.secondary_taps])
            sy = self._fir(self.s_hat, self.y_buf)
            e = px + sy

        if self.mode != "ff_frozen":
            for i in range(self.taps):
                self.w[i] = (1.0 - self.leak) * self.w[i] + self.mu * e * self.xf_buf[i]

        return -y


def q131(x: float) -> int:
    return max(-0x80000000, min(0x7FFFFFFF, int(x * (1 << 31))))


def from_q131(v: int) -> float:
    if v >= 0x80000000:
        v -= 0x100000000
    return v / float(1 << 31)


def synth_tone(n: int, freq: float = 500.0, rate: float = 48000.0, amp: float = 0.5) -> list[float]:
    return [amp * math.sin(2.0 * math.pi * freq * i / rate) for i in range(n)]
