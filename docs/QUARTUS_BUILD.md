# Quartus Build Guide — ANC Agilex 5

## Prerequisites

- **Quartus Prime Pro** 24.3 or later (Agilex 5 support)
- Agilex 5 E-Series device support files installed
- Platform Designer (included)

## Quick start

```bash
# 1. Create project (from Quartus GUI or CLI)
quartus_sh --flow compile anc_agilex5/quartus/anc_agilex5.qpf

# 2. Program device
quartus_pgm -c 1 -m jtag -o "p;anc_agilex5/quartus/output_files/anc_agilex5.sof"
```

## Adding RTL to Platform Designer

1. **Tools → Platform Designer** → open or create `anc_platform.qsys`.
2. Add **New Component** → import `anc_agilex5/rtl/anc_top.v` and supporting files.
3. Expose interfaces:
   - `axi4lite_ctrl` — connect to LWH2F master
   - `i2s_adc` / `i2s_dac` — export to top-level pins
   - `clk`, `reset_n` — connect to system clock bridge
4. Generate HDL; add generated `.qsys` to Quartus project.
5. Merge `constraints/anc_pins.qsf` into project QSF.

## Simulation (ModelSim / Questa / Verilator)

```bash
cd anc_agilex5/tb
# ModelSim
vlog ../rtl/*.v tb_fxlms_engine.v
vsim -c tb_fxlms_engine -do "run -all; quit"

# Icarus Verilog (open-source)
iverilog -o sim ../rtl/*.v tb/tb_fxlms_engine.v && vvp sim
```

## Key generics / parameters

| Parameter | Default | Location | Description |
| --- | --- | --- | --- |
| `FILTER_TAPS` | 256 | `fxlms_engine.v` | Adaptive FIR length |
| `SECONDARY_TAPS` | 128 | `fxlms_engine.v` | Secondary-path model length |
| `SAMPLE_RATE` | 48000 | `audio_clock_gen.v` | Audio sample rate (Hz) |
| `DATA_WIDTH` | 24 | `i2s_rx.v` | I2S sample width |
| `INTERNAL_WIDTH` | 32 | `fxlms_engine.v` | Fixed-point internal width (Q1.31) |
| `TDM_SLOTS` | 2 | `i2s_rx.v` | Number of TDM slots per frame |

## Timing constraints (excerpt)

See `constraints/anc_pins.qsf` for full pin assignments. Core SDC:

```tcl
create_clock -name sys_clk -period 10.0 [get_ports sys_clk]
set_clock_groups -asynchronous -group [get_clocks sys_clk] -group [get_clocks mclk]
set_false_path -from [get_ports i2s_adc_data]
```

## Troubleshooting

| Symptom | Likely cause | Fix |
| --- | --- | --- |
| No audio output | Wrong pin assignment / codec not powered | Check QSF, scope BCLK/LRCK |
| Hiss / clipping | Gain too high | Reduce `OUTPUT_GAIN` CSR |
| No convergence | Bad secondary-path model | Re-run calibration |
| `STATUS.clip` set | ADC saturation | Lower mic preamp gain |
| Timing failures in DSP | Filter too long at high Fmax | Reduce `FILTER_TAPS` or lower sys_clk |
