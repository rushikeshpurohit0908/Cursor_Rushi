# Cursor_Rushi

FPGA design notes and reference guides.

## Guides

- [Agilex 7 CvP: Avalon-ST Peripheral Image Guide](docs/cvp-avalon-st-peripheral-image.md) —
  Use P/R/F-Tile Avalon® Streaming PCIe IP for CvP Initialization: generate the static
  `.periph.jic` periphery image, program QSPI (AS x4 Fast), then load `.core.rbf` over PCIe.

## Scripts

| Script | Purpose |
| --- | --- |
| `scripts/generate_cvp_images.sh` | Split an Agilex 7 `.sof` into `.periph.jic` + `.core.rbf` (`quartus_pfg`, `cvp=on`) |
| `scripts/load_cvp_core.sh` | Load a `.core.rbf` on Linux after the periphery image is in flash |

### Quick start (Agilex 7)

```bash
# After compiling with CvP Init + Avalon-ST PCIe (Enable CVP Intel VSEC):
FLASH_LOADER=<your-agilex7-opn-prefix> \
  ./scripts/generate_cvp_images.sh output_files/top.sof output_files/top

# After programming top.periph.jic to QSPI and power-cycling:
sudo ./scripts/load_cvp_core.sh output_files/top.core.rbf
```
