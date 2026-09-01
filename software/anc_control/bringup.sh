#!/usr/bin/env bash
# On-board bring-up sequence (run on Agilex 5 HPS Linux).
set -euo pipefail
MODE="${1:-hybrid}"
CODEC="${2:-ssm2518}"

echo "1. Codec init ($CODEC)"
python3 -m anc_control.anc_tuner --codec "$CODEC" --bypass --no-dry-run

if [[ -f secondary_path_coeffs.hex ]]; then
  echo "2. Load secondary-path FIR"
  python3 -m anc_control.load_coeffs --secondary secondary_path_coeffs.hex --no-dry-run
else
  echo "2. No secondary_path_coeffs.hex — using default impulse Ŝ"
fi

echo "3. Enable ANC mode=$MODE"
exec python3 -m anc_control.anc_tuner --mode "$MODE" --codec none --no-dry-run --monitor
