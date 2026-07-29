#!/usr/bin/env bash
# Generate CvP periphery (.periph.jic) and core (.core.rbf) images from a compiled SOF.
#
# Usage:
#   ./scripts/generate_cvp_images.sh <design.sof> [output_basename]
#
# Environment overrides (required unless using a saved .pfg file):
#   QSPI_DEVICE     QSPI flash part, e.g. MT25QU128
#   FLASH_LOADER    Flash loader prefix for your FPGA, e.g. AGFB014R24AR0
#   PFG_SETTINGS    Optional path to a saved Programming File Generator .pfg file
#
# Example:
#   QSPI_DEVICE=MT25QU128 FLASH_LOADER=AGFB014R24AR0 \
#     ./scripts/generate_cvp_images.sh output_files/top.sof output_files/top

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
  echo "Generating CvP images using settings: $PFG_SETTINGS"
  quartus_pfg -c "$PFG_SETTINGS"
else
  : "${QSPI_DEVICE:?Set QSPI_DEVICE (e.g. MT25QU128)}"
  : "${FLASH_LOADER:?Set FLASH_LOADER (e.g. AGFB014R24AR0)}"

  JIC_OUT="${OUT_BASE}.jic"
  echo "Generating CvP images from: $SOF"
  echo "  QSPI device:   $QSPI_DEVICE"
  echo "  Flash loader:  $FLASH_LOADER"
  echo "  Output prefix: $OUT_BASE"

  quartus_pfg -c "$SOF" "$JIC_OUT" \
    -o "device=${QSPI_DEVICE}" \
    -o "flash_loader=${FLASH_LOADER}" \
    -o mode=ASX4 \
    -o cvp=on
fi

echo ""
echo "Generated files (expected):"
ls -1 "${OUT_BASE}".periph.jic "${OUT_BASE}".core.rbf 2>/dev/null || {
  echo "  ${OUT_BASE}.periph.jic  (program to flash)"
  echo "  ${OUT_BASE}.core.rbf    (load over PCIe)"
}
