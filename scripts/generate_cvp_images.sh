#!/usr/bin/env bash
# Generate Agilex 7 CvP periphery (.periph.jic) and core (.core.rbf) images from a SOF.
#
# Usage:
#   ./scripts/generate_cvp_images.sh <design.sof> [output_basename]
#
# Environment:
#   QSPI_DEVICE     QSPI flash part (default: MT25QU128 — 128 Mb recommended for periphery)
#   FLASH_LOADER    Agilex 7 FPGA part prefix for the JIC helper image (required unless .pfg)
#   PFG_SETTINGS    Optional path to a saved Programming File Generator .pfg file
#
# Example (Agilex 7 F-Series):
#   FLASH_LOADER=AGFB014R24AR0 \
#     ./scripts/generate_cvp_images.sh output_files/top.sof output_files/top
#
# Discover FLASH_LOADER: Programming File Generator → Configuration device → Select →
# Device family Agilex → Device name matching your OPN.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <design.sof> [output_basename]" >&2
  exit 1
fi

SOF="$1"
if [[ ! -f "$SOF" ]]; then
  echo "Error: SOF not found: $SOF" >&2
  exit 1
fi

OUT_BASE="${2:-${SOF%.sof}}"
OUT_DIR="$(dirname "$OUT_BASE")"
mkdir -p "$OUT_DIR"

if ! command -v quartus_pfg >/dev/null 2>&1; then
  echo "Error: quartus_pfg not found. Source your Quartus Prime Pro environment." >&2
  exit 1
fi

if [[ -n "${PFG_SETTINGS:-}" ]]; then
  echo "Generating Agilex 7 CvP images using settings: $PFG_SETTINGS"
  quartus_pfg -c "$PFG_SETTINGS"
else
  QSPI_DEVICE="${QSPI_DEVICE:-MT25QU128}"
  : "${FLASH_LOADER:?Set FLASH_LOADER to your Agilex 7 OPN prefix (e.g. AGFB014R24AR0)}"

  JIC_OUT="${OUT_BASE}.jic"
  echo "Generating Agilex 7 CvP images from: $SOF"
  echo "  QSPI device:   $QSPI_DEVICE"
  echo "  Flash loader:  $FLASH_LOADER"
  echo "  Mode:          ASX4 (cvp=on)"
  echo "  Output prefix: $OUT_BASE"

  quartus_pfg -c "$SOF" "$JIC_OUT" \
    -o "device=${QSPI_DEVICE}" \
    -o "flash_loader=${FLASH_LOADER}" \
    -o mode=ASX4 \
    -o cvp=on
fi

echo ""
echo "Generated files (expected):"
if ls -1 "${OUT_BASE}".periph.jic "${OUT_BASE}".core.rbf 2>/dev/null; then
  :
else
  echo "  ${OUT_BASE}.periph.jic  (program to Agilex 7 QSPI flash)"
  echo "  ${OUT_BASE}.core.rbf    (load over PCIe after link up)"
fi
