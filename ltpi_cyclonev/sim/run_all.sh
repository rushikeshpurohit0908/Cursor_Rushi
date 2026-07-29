#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# LTPI IP for Cyclone V FPGA - SPDX-License-Identifier: MIT
#
# run_all.sh - compiles and runs every vendor-agnostic testbench with Icarus
# Verilog (https://steveicarus.github.io/iverilog/). These cover the
# protocol/link layer only (rtl/common + rtl/link + rtl/ltpi_top.sv); the
# Cyclone V PHY files under rtl/phy/cyclonev use Quartus megafunctions
# (altpll) and must be simulated/synthesized with Quartus + its simulation
# libraries instead.
#
# Usage: ./run_all.sh   (run from anywhere; paths are relative to this file)
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$SCRIPT_DIR/.."
RTL_COMMON="$ROOT/rtl/common"
RTL_LINK="$ROOT/rtl/link"
RTL_TOP="$ROOT/rtl/ltpi_top.sv"
BUILD_DIR="${TMPDIR:-/tmp}/ltpi_cyclonev_sim"
mkdir -p "$BUILD_DIR"

CORE_SOURCES=(
    "$RTL_COMMON/ltpi_pkg.sv"
    "$RTL_COMMON/crc8.sv"
    "$RTL_COMMON/encoder_8b10b.sv"
    "$RTL_COMMON/decoder_8b10b.sv"
    "$RTL_LINK/ltpi_symbol_serializer.sv"
    "$RTL_LINK/ltpi_symbol_align.sv"
    "$RTL_LINK/ltpi_frame_tx.sv"
    "$RTL_LINK/ltpi_frame_rx.sv"
    "$RTL_LINK/ltpi_link_ctrl.sv"
    "$RTL_TOP"
)

run_tb() {
    local name="$1"; shift
    local out="$BUILD_DIR/$name.vvp"
    echo "==> $name"
    iverilog -g2012 -o "$out" "$@"
    vvp "$out"
    echo
}

run_tb tb_crc8            "$RTL_COMMON/crc8.sv" "$SCRIPT_DIR/tb_crc8.sv"
run_tb tb_8b10b           "$RTL_COMMON/encoder_8b10b.sv" "$RTL_COMMON/decoder_8b10b.sv" "$SCRIPT_DIR/tb_8b10b.sv"
run_tb tb_symbol_align    "$RTL_COMMON/encoder_8b10b.sv" "$RTL_LINK/ltpi_symbol_serializer.sv" "$RTL_LINK/ltpi_symbol_align.sv" "$SCRIPT_DIR/tb_symbol_align.sv"
run_tb tb_frame_loopback  "${CORE_SOURCES[@]:0:9}" "$SCRIPT_DIR/tb_frame_loopback.sv"
run_tb tb_ltpi_top_link   "${CORE_SOURCES[@]}" "$SCRIPT_DIR/tb_ltpi_top_link.sv"

echo "All testbenches passed."
