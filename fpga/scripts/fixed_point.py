"""Fixed-point helpers mirroring the Verilog RTL."""

from __future__ import annotations

import numpy as np

from fpga_params import ACC_WIDTH, DATA_WIDTH, FRAC_BITS, EPS_NORM


def float_to_q15(value: float) -> int:
    scaled = int(round(float(value) * (1 << FRAC_BITS)))
    return int(np.clip(scaled, -(1 << (DATA_WIDTH - 1)), (1 << (DATA_WIDTH - 1)) - 1))


def q15_to_float(value: int) -> float:
    value = int(value)
    if value >= (1 << (DATA_WIDTH - 1)):
        value -= 1 << DATA_WIDTH
    return value / (1 << FRAC_BITS)


def q15_mul(a: int, b: int) -> int:
    return (int(a) * int(b)) >> FRAC_BITS


def q15_mac(acc: int, a: int, b: int) -> int:
    return acc + (int(a) * int(b))


def sat_q15(value: int) -> int:
    hi = (1 << (DATA_WIDTH - 1)) - 1
    lo = -(1 << (DATA_WIDTH - 1))
    return int(np.clip(int(value), lo, hi))


def tanh_lut(x_q15: int) -> int:
    x = q15_to_float(x_q15)
    return float_to_q15(float(np.tanh(x)))


def sigmoid_lut(x_q15: int) -> int:
    x = q15_to_float(x_q15)
    return float_to_q15(1.0 / (1.0 + np.exp(-x)))


def mu_from_sigmoid(out_q15: int) -> int:
    s = q15_to_float(out_q15)
    mu = 0.001 + 0.199 * s
    return float_to_q15(mu)


def gain_from_sigmoid(out_q15: int) -> int:
    s = q15_to_float(out_q15)
    gain = 0.90 + 0.20 * s
    return float_to_q15(gain)
