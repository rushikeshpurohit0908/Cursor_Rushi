"""Select optimal NLMS mu from hardware features — mirrors ai_mu_selector.v"""

from __future__ import annotations

from fixed_point import float_to_q15, q15_to_float

MU_RUMBLE = float_to_q15(0.001)
MU_HUM = float_to_q15(0.005)
MU_BROAD = float_to_q15(0.020)
MU_HISS = float_to_q15(0.050)
MU_DRILL = float_to_q15(0.002)
GAIN_ONE = float_to_q15(1.0)


def select_mu(features_q15: list[int]) -> tuple[int, int]:
    low, mid, high, crest = features_q15[4], features_q15[5], features_q15[6], features_q15[7]
    if crest > float_to_q15(0.85) and low > mid:
        mu = MU_DRILL
    elif low > mid and low > high:
        mu = MU_RUMBLE
    elif mid >= low and mid >= high:
        mu = MU_HUM
    elif high > mid and high > low:
        mu = MU_HISS
    else:
        mu = MU_BROAD
    return mu, GAIN_ONE
