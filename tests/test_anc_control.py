"""Tests for ANC HPS control software."""

import struct
import tempfile
from pathlib import Path

import pytest

from anc_control.fpga_bridge import AncFpgaBridge, ControlFlag, NoiseClass, Reg
from anc_control.calibrate_secondary import lms_identify, read_wav_mono
import wave


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
            # Last write should be at address 1
            val = struct.unpack_from("<I", bridge._buf, Reg.SECONDARY_WR)[0]
            assert (val & 0x7F) == 1

    def test_read_status_default(self):
        with AncFpgaBridge(dry_run=True) as bridge:
            st = bridge.read_status()
            assert not st.running
            assert st.sample_count == 0


class TestCalibration:
    def test_lms_identify_impulse(self):
        # Sustained unit step — first tap should grow positively
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
