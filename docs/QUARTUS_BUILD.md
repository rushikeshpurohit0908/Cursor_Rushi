# Quartus Build Guide — ANC Agilex 5 (full design)

## Prerequisites

- **Quartus Prime Pro** 24.3 or later with Agilex 5 device support
- Platform Designer (included)

## Project files

| File | Role |
| --- | --- |
| `anc_agilex5/quartus/anc_agilex5.qpf` | Quartus project |
| `anc_agilex5/quartus/anc_agilex5.qsf` | Device, RTL list, pin assignments |
| `anc_agilex5/quartus/anc_agilex5.sdc` | Timing |
| `anc_agilex5/platform/anc_board_hw.tcl` | Custom Qsys component |
| `anc_agilex5/platform/anc_platform.tcl` | Generate `anc_platform.qsys` |

## Compile

```bash
cd anc_agilex5/quartus
quartus_sh --flow compile anc_agilex5.qpf
quartus_pgm -c 1 -m jtag -o "p;output_files/anc_agilex5.sof"
```

## Platform Designer

```bash
cd anc_agilex5/platform
qsys-script --script=anc_platform.tcl --quartus-project=../quartus/anc_agilex5.qpf
```

Then in the GUI:

1. Add **Agilex 5 HPS** IP (name varies by Quartus version).
2. Connect `lwh2f_axi_master` → `anc.s_axi` at offset `0x0`.
3. Export `audio` (I2S + I2C) and `leds` conduits to the board top.
4. Generate HDL; add the `.qsys` to the Quartus project.

`CODEC_SEL` on `anc_board`: `0` = SSM2518, `1` = WM8960, `2` = Pmod I2S2 (no I2C).

## Simulation

```bash
cd anc_agilex5/tb
make fxlms    # FxLMS engine
make i2s      # I2S loopback
make i2c      # SSM2518 init over I2C master
```

Requires Icarus Verilog (`iverilog` / `vvp`). File list: `tb/filelist.f`.

## Parameters

| Parameter | Default | File | Description |
| --- | --- | --- | --- |
| `FILTER_TAPS` | 256 | `fxlms_engine.v` | Adaptive FIR length |
| `SECONDARY_TAPS` | 128 | `fxlms_engine.v` | Ŝ / P̂ length |
| `CODEC_SEL` | 0 | `anc_board.v` | Codec init ROM |
| `GENERATE_CLOCKS` | 1 | `anc_top.v` | Internal MCLK/BCLK/LRCK |

## Device-tree overlay (HPS Linux)

```bash
dtc -@ -I dts -O dtb -o anc.dtbo software/dts/socfpga_agilex5_anc.dts
mkdir -p /sys/kernel/config/device-tree/overlays/anc
cat anc.dtbo > /sys/kernel/config/device-tree/overlays/anc/dtbo
```

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| No audio | Pins / codec power / I2C | Scope BCLK/LRCK; `STATUS.codec_ready` |
| Hiss / clip | Gain too high | Lower `OUTPUT_GAIN` |
| No convergence | Bad Ŝ or wrong mode | Recalibrate; use HYBRID with error mic |
| Feedforward does nothing | Empty `w` | Load pretrained weights or use `FF_VIRTUAL` |
| Timing fail | Long FIR at high Fmax | Reduce `FILTER_TAPS` |
