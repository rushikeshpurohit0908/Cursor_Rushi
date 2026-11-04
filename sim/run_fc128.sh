#!/usr/bin/env bash
# One-command simulation for the FC128 PoC datapath.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
INC=(-I "$ROOT/rtl/fc128" -g2012)

compile_run() {
  local name="$1"
  shift
  echo "== $name =="
  iverilog "${INC[@]}" -o "/tmp/${name}" "$@"
  vvp "/tmp/${name}"
}

compile_run tb_fc_scrambler \
  rtl/fc128/fc_scrambler.sv \
  tb/fc128/tb_fc_scrambler.sv

compile_run tb_fc_async_fifo \
  rtl/fc128/fc_async_fifo.sv \
  tb/fc128/tb_fc_async_fifo.sv

compile_run tb_fc_rs_fec \
  rtl/fc128/fc_rs_fec.sv \
  tb/fc128/tb_fc_rs_fec.sv

compile_run tb_fc_rs544 \
  rtl/fc128/fc_rs544.sv \
  tb/fc128/tb_fc_rs544.sv

compile_run tb_fc_rs544_stream \
  rtl/fc128/fc_rs544.sv \
  rtl/fc128/fc_rs544_stream.sv \
  tb/fc128/tb_fc_rs544_stream.sv

compile_run tb_fc_link \
  rtl/fc128/fc_link_sm.sv \
  tb/fc128/tb_fc_link.sv

compile_run tb_fc_xcode \
  rtl/fc128/fc_xcode_stream.sv \
  tb/fc128/tb_fc_xcode.sv

compile_run tb_fc_cmis \
  rtl/fc128/fc_i2c_master.sv \
  rtl/fc128/fc_cmis_host.sv \
  tb/fc128/cmis_sfp_slave.sv \
  tb/fc128/tb_fc_cmis.sv

compile_run tb_fc_rate \
  rtl/fc128/fc_rate.sv \
  rtl/fc128/fc_scrambler.sv \
  rtl/fc128/fc_async_fifo.sv \
  rtl/fc128/fc_rx_front.sv \
  rtl/fc128/fc_rs_fec.sv \
  rtl/fc128/fc_rs544.sv \
  rtl/fc128/fc_rs544_stream.sv \
  rtl/fc128/fc_lane_pair.sv \
  rtl/fc128/fc_link_sm.sv \
  rtl/fc128/fc_xcode_stream.sv \
  rtl/fc128/fc_pipe.sv \
  rtl/fc128/fc_port.sv \
  tb/fc128/tb_fc_rate.sv

compile_run tb_fc_rs544_port \
  rtl/fc128/fc_rate.sv \
  rtl/fc128/fc_scrambler.sv \
  rtl/fc128/fc_async_fifo.sv \
  rtl/fc128/fc_rx_front.sv \
  rtl/fc128/fc_rs_fec.sv \
  rtl/fc128/fc_rs544.sv \
  rtl/fc128/fc_rs544_stream.sv \
  rtl/fc128/fc_lane_pair.sv \
  rtl/fc128/fc_link_sm.sv \
  rtl/fc128/fc_xcode_stream.sv \
  rtl/fc128/fc_pipe.sv \
  rtl/fc128/fc_port.sv \
  tb/fc128/tb_fc_rs544_port.sv

compile_run tb_fc128_bridge \
  rtl/fc128/fc_rate.sv \
  rtl/fc128/fc_scrambler.sv \
  rtl/fc128/fc_async_fifo.sv \
  rtl/fc128/fc_rx_front.sv \
  rtl/fc128/fc_rs_fec.sv \
  rtl/fc128/fc_rs544.sv \
  rtl/fc128/fc_rs544_stream.sv \
  rtl/fc128/fc_lane_pair.sv \
  rtl/fc128/fc_link_sm.sv \
  rtl/fc128/fc_xcode_stream.sv \
  rtl/fc128/fc_i2c_master.sv \
  rtl/fc128/fc_cmis_host.sv \
  rtl/fc128/fc_pipe.sv \
  rtl/fc128/fc_port.sv \
  rtl/fc128/fc128_bridge_top.sv \
  tb/fc128/cmis_sfp_slave.sv \
  tb/fc128/tb_fc128_bridge.sv
