"""Tests for ANC HPS control software and golden FxLMS model."""

import struct
import wave
from pathlib import Path

from anc_control.calibrate_secondary import lms_identify, read_wav_mono
from anc_control.codecs import CODECS, SSM2518, program_codec
from anc_control.fpga_bridge import AncFpgaBridge, AncMode, ControlFlag, MemSel, NoiseClass, Reg
from anc_control.fxlms_model import FxLMS, synth_tone


class TestAncFpgaBridge:
    def test_dry_run_enable(self):
        with AncFpgaBridge(dry_run=True) as bridge:
            bridge.enable(True)
            ctrl = struct.unpack_from("<I", bridge._buf, Reg.CONTROL)[0]
            assert ctrl & ControlFlag.ENABLE
            assert not (ctrl & ControlFlag.BYPASS)

    def test_dry_run_bypass(self):
        with AncFpgaBridge(dry_run=True) as bridge:
            bridge.bypass(True)
            ctrl = struct.unpack_from("<I", bridge._buf, Reg.CONTROL)[0]
            assert ctrl & ControlFlag.BYPASS

    def test_set_mu(self):
        with AncFpgaBridge(dry_run=True) as bridge:
            bridge.set_mu(0x2000)
            val = struct.unpack_from("<I", bridge._buf, Reg.MU)[0]
            assert val == 0x2000

    def test_ai_override(self):
        with AncFpgaBridge(dry_run=True) as bridge:
            bridge.set_ai_override(NoiseClass.TONAL)
            val = struct.unpack_from("<I", bridge._buf, Reg.AI_OVERRIDE)[0]
            assert val & (1 << 31)
            assert (val & 0x3) == NoiseClass.TONAL

    def test_load_secondary_path(self):
        with AncFpgaBridge(dry_run=True) as bridge:
            bridge.load_secondary_path([0x7FFF0000, 0x1000])
            sel = struct.unpack_from("<I", bridge._buf, Reg.MEM_SEL)[0]
            assert sel == MemSel.SECONDARY
            addr = struct.unpack_from("<I", bridge._buf, Reg.MEM_ADDR)[0]
            assert addr == 1
            data = struct.unpack_from("<I", bridge._buf, Reg.MEM_DATA)[0]
            assert data == 0x1000

    def test_load_primary_path(self):
        with AncFpgaBridge(dry_run=True) as bridge:
            bridge.load_primary_path([0x1111])
            sel = struct.unpack_from("<I", bridge._buf, Reg.MEM_SEL)[0]
            assert sel == MemSel.PRIMARY

    def test_read_status_default(self):
        with AncFpgaBridge(dry_run=True) as bridge:
            st = bridge.read_status()
            assert not st.running
            assert st.sample_count == 0

    def test_set_mode(self):
        with AncFpgaBridge(dry_run=True) as bridge:
            bridge.set_mode(AncMode.FF_VIRTUAL)
            val = struct.unpack_from("<I", bridge._buf, Reg.MODE)[0]
            assert val == AncMode.FF_VIRTUAL

    def test_codec_init_flag(self):
        with AncFpgaBridge(dry_run=True) as bridge:
            bridge.start_codec_init()
            ctrl = struct.unpack_from("<I", bridge._buf, Reg.CONTROL)[0]
            assert ctrl & ControlFlag.CODEC_INIT

    def test_i2c_write(self):
        with AncFpgaBridge(dry_run=True) as bridge:
            bridge.i2c_write(0x34, 0x03, 0x02)
            ctrl = struct.unpack_from("<I", bridge._buf, Reg.I2C_CTRL)[0]
            data = struct.unpack_from("<I", bridge._buf, Reg.I2C_DATA)[0]
            assert ctrl == 0x34
            assert data == 0x0302


class TestCalibration:
    def test_lms_identify_impulse(self):
        n = 2048
        impulse = [1.0] * n
        response = [1.0] * n
        coeffs = lms_identify(impulse, response, taps=8, mu=0.05)
        assert len(coeffs) == 8
        assert coeffs[0] > 0
        assert sum(abs(c) for c in coeffs) > 0

    def test_read_wav_mono(self, tmp_path: Path):
        wav_path = tmp_path / "test.wav"
        with wave.open(str(wav_path), "wb") as wf:
            wf.setnchannels(1)
            wf.setsampwidth(2)
            wf.setframerate(48000)
            wf.writeframes(struct.pack("<h", 16384))
        samples, rate = read_wav_mono(wav_path)
        assert rate == 48000
        assert len(samples) == 1
        assert abs(samples[0] - 0.5) < 0.01


class TestCodecs:
    def test_ssm2518_table(self):
        assert SSM2518.i2c_addr == 0x34
        assert SSM2518.init[0] == (0x00, 0x80)
        assert CODECS["wm8960"].i2c_addr == 0x1A

    def test_program_codec_dry_run(self):
        with AncFpgaBridge(dry_run=True) as bridge:
            program_codec(bridge, SSM2518)
            data = struct.unpack_from("<I", bridge._buf, Reg.I2C_DATA)[0]
            last_reg, last_val = SSM2518.init[-1]
            assert data == (last_reg << 8) | last_val


class TestFxLMSModel:
    def test_hybrid_reduces_tone(self):
        anc = FxLMS(taps=32, secondary_taps=8, mu=0.05, mode="hybrid")
        tone = synth_tone(800, freq=500.0)
        residual = []
        for x in tone:
            y = anc.step(x, e_mic=x + y if residual else x)
            residual.append(x + y)
        early = sum(abs(v) for v in residual[:80])
        late = sum(abs(v) for v in residual[-80:])
        assert late < early

    def test_ff_frozen_no_adapt(self):
        anc = FxLMS(taps=8, secondary_taps=4, mu=0.2, mode="ff_frozen")
        anc.w[0] = 0.5
        before = list(anc.w)
        for x in synth_tone(64):
            anc.step(x, e_mic=x)
        assert anc.w == before

    def test_ff_virtual_updates_weights(self):
        anc = FxLMS(taps=16, secondary_taps=4, mu=0.02, mode="ff_virtual")
        for x in synth_tone(256):
            anc.step(x)
        assert any(abs(c) > 1e-6 for c in anc.w)
