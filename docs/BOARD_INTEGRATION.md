# Board Integration — Agilex 5 ANC

## Supported hardware

### Option A: Agilex 5 E-Series 065B Modular Dev Kit + Digilent Pmod I2S2

The 065B kit exposes **HVIO headers** (2×20). Wire the Pmod I2S2 (CS5343 ADC +
CS4344 DAC) as follows:

| Pmod I2S2 pin | Signal | 065B HVIO (example) | Direction |
| --- | --- | --- | --- |
| J1-1 | I2S RX (ADC data) | GPIO_20 | FPGA → fabric input |
| J1-2 | I2S TX (DAC data) | GPIO_21 | fabric output → |
| J1-3 | LRCK / WS | GPIO_22 | fabric output → |
| J1-4 | BCLK | GPIO_23 | fabric output → |
| J1-5 | GND | GND | — |
| J1-6 | 3.3 V | 3.3 V | — |
| J1-7 | MCLK | GPIO_24 | fabric output → |
| J1-8 | GND | GND | — |

**Microphone wiring for ANC:**

| Channel | Source | Pmod / codec input |
| --- | --- | --- |
| I2S slot 0 (L) | Reference mic (feedforward) | External electret + preamp → ADC left |
| I2S slot 1 (R) | Error mic (feedback, optional) | Second mic → ADC right |
| Output L | Anti-noise | DAC left → headphone driver |
| Output R | Passthrough / monitor | DAC right → monitor mix |

Use a **3.5 mm electret capsule** with a simple op-amp preamp (e.g., OPA1678)
for each microphone. Keep reference mic physically separated from the headphone
driver to avoid feedback before the algorithm converges.

### Option B: Custom carrier with SSM2518 Class-D codec

For a compact speaker ANC product:

1. Connect SSM2518 **BCLK, LRCK, SDIN, SDOUT** to fabric GPIO (soft I2S master).
2. Connect SSM2518 **SCL/SDA** to HPS I2C for volume/mute control (Linux
   `i2c-dev` driver or bare-metal init table).
3. MCLK: SSM2518 can derive from BCLK in slave mode, or provide 12.288 MHz
   from `audio_clock_gen`.

### Option C: FMC mezzanine audio card

If your carrier has an **FMC connector**, many audio FMC modules (Analog
Devices, etc.) expose multi-channel I2S/TDM. Set `TDM_SLOTS = 4` in
`anc_top.v` and map channels in Platform Designer.

## Clocking

The design defaults to:

| Clock | Frequency | Derivation |
| --- | --- | --- |
| `sys_clk` | 100 MHz | 065B on-board oscillator (HVIO PLL ref) |
| `mclk` | 12.288 MHz | 100 MHz ÷ 8.138020833 (approximated in RTL) |
| `bclk` | 3.072 MHz | mclk ÷ 4 |
| `lrck` | 48 kHz | bclk ÷ 64 |

Run `audio_clock_gen` from the same clock domain as the I2S logic. If your
board provides a dedicated audio crystal (24.576 MHz), use that as MCLK
directly and disable the internal divider.

## Quartus / Platform Designer steps

1. Create a new **Agilex 5 E-Series** project; target device `A5ED065B` (or your OPN).
2. Add **Platform Designer (Qsys)** system:
   - Agilex 5 HPS (DDR, clocks, resets)
   - LWH2F bridge → export `h2f_lw_axi_master`
   - `anc_top` as custom component with AXI4-Lite slave
3. Assign HVIO pins per `constraints/anc_pins.qsf`.
4. Set `sys_clk` timing constraint to 100 MHz; `mclk` domain is asynchronous —
   use FIFOs between I2S and DSP (already in `anc_top.v`).
5. Compile; program via **Intel FPGA Download Cable II** (on-board USB-JTAG).

## Secondary-path calibration

Before enabling adaptation:

1. Put the design in **bypass mode** (`CONTROL.bypass = 1`).
2. Play a known test tone through the speaker (HPS can stream WAV via I2S TX).
3. Capture the error-mic response; compute Ŝ (128-tap FIR) offline in Python:

   ```bash
   python -m anc_control.calibrate_secondary --capture error.wav --tone sweep.wav
   ```

4. Write Ŝ coefficients to BRAM via `SECONDARY_PATH_BASE` register window.

## Bring-up checklist

- [ ] `sys_clk` toggles; LEDs heartbeat in BTS
- [ ] MCLK/BCLK/LRCK visible on scope (12.288 / 3.072 / 48 kHz)
- [ ] I2S loopback test passes (`tb_i2s_loopback` or on-board bypass)
- [ ] Reference mic signal visible in `SAMPLE_COUNT` increment
- [ ] Secondary-path model loaded; `STATUS.running` set
- [ ] Enable ANC (`CONTROL.enable=1`); verify noise reduction at ear
- [ ] AI classifier reports expected class for test stimuli
