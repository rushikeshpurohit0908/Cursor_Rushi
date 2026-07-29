# Cursor_Rushi

FPGA design notes and reference guides.

## Guides

- [CvP with Avalon-ST: Peripheral Image Guide](docs/cvp-avalon-st-peripheral-image.md) —
  Configure CvP using the Avalon® Streaming PCIe IP, generate the static `.periph.jic`
  periphery image, and load `.core.rbf` over PCIe.

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/generate_cvp_images.sh` | Split a compiled `.sof` into `.periph.jic` and `.core.rbf` |
| `scripts/load_cvp_core.sh` | Load a `.core.rbf` on Linux after the periphery image is in flash |
