"""Fixed-point constants shared by Python cosim and Verilog RTL."""

from __future__ import annotations

# Audio samples: Q1.15 signed 16-bit
DATA_WIDTH = 16
FRAC_BITS = 15

# NLMS filter
FILTER_TAPS = 32
BLOCK_SIZE = 512
SAMPLE_RATE = 16000

# Accumulator width for MAC / norm
ACC_WIDTH = 40

# MLP dimensions
NUM_FEATURES = 8
HIDDEN_SIZE = 16
NUM_OUTPUTS = 2

# mu range: 0.001 .. 0.200 mapped to Q0.16
MU_MIN = 0.001
MU_MAX = 0.200
GAIN_MIN = 0.90
GAIN_MAX = 1.10

# Weight update epsilon (Q1.15 squared scale)
EPS_NORM = 1 << 6  # small bias in fixed-point norm denominator
