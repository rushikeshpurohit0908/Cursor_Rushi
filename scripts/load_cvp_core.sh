#!/usr/bin/env bash
# Load a CvP core image (.core.rbf) over PCIe on Linux.
#
# Usage:
#   sudo ./scripts/load_cvp_core.sh <design.core.rbf>
#
# Tries the FPGA manager interface first, then the legacy altera_cvp device node.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <design.core.rbf>" >&2
  exit 1
fi

RBF="$(readlink -f "$1")"
NAME="$(basename "$RBF")"

if [[ ! -f "$RBF" ]]; then
  echo "Error: core image not found: $RBF" >&2
  exit 1
fi

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Error: run as root (sudo) to load the core image." >&2
  exit 1
fi

FW_DIR="/lib/firmware"
mkdir -p "$FW_DIR"
cp -f "$RBF" "${FW_DIR}/${NAME}"

FPGA_MGR="/sys/kernel/debug/fpga_manager/fpga0/firmware_name"
if [[ -e "$FPGA_MGR" ]]; then
  echo "Loading via FPGA manager: $NAME"
  echo "$NAME" > "$FPGA_MGR"
elif [[ -e /dev/altera_cvp ]]; then
  echo "Loading via /dev/altera_cvp: $NAME"
  echo "$NAME" > /dev/altera_cvp
else
  echo "Error: no CvP load interface found (fpga_manager or /dev/altera_cvp)." >&2
  exit 1
fi

echo "Core load requested. Check dmesg for CvP status:"
dmesg | tail -20
