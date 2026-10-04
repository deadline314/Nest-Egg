"""時間伸縮（音高不變）的測試（NE-182）：用合成的衰減音，不依賴下載的素材。

用法：python tools/audio/test_time_stretch.py（需要 ffmpeg 含 rubberband 濾鏡；沒有時略過）
"""
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audio_lib as lib  # noqa: E402


def rubberband_available() -> bool:
    if shutil.which("ffmpeg") is None:
        return False
    out = subprocess.run(["ffmpeg", "-hide_banner", "-filters"], capture_output=True, text=True).stdout
    return "rubberband" in out


def shot(freq: float = 1000.0, seconds: float = 0.6, attack_at: float = 0.02) -> np.ndarray:
    """起音在 attack_at 秒、之後指數衰減的單頻音，像一聲槍響的簡化版。"""
    n = int(lib.SR * seconds)
    t = np.arange(n) / lib.SR
    envelope = np.where(t >= attack_at, np.exp(-(t - attack_at) * 9.0), 0.0)
    return (np.sin(2 * np.pi * freq * t) * envelope * 0.8).astype(np.float32)


def dominant_frequency(x: np.ndarray) -> float:
    spectrum = np.abs(np.fft.rfft(x * np.hanning(len(x))))
    return float(np.fft.rfftfreq(len(x), 1.0 / lib.SR)[int(np.argmax(spectrum))])


@unittest.skipUnless(rubberband_available(), "需要含 rubberband 濾鏡的 ffmpeg")
class TimeStretchTest(unittest.TestCase):
    def test_length_is_the_original_divided_by_the_tempo(self):
        x = shot()
        for tempo in (1.25, 1.5, 2.0):
            self.assertEqual(len(lib.time_stretch(x, tempo)), round(len(x) / tempo))

    def test_pitch_does_not_change(self):
        x = shot(freq=1000.0)
        for tempo in (1.25, 1.5, 2.0):
            y = lib.time_stretch(x, tempo)
            self.assertAlmostEqual(dominant_frequency(y) / 1000.0, 1.0, delta=0.03, msg=f"tempo {tempo}")

    def test_attack_stays_where_it_should(self):
        x = shot(attack_at=0.05)
        for tempo in (1.5, 2.0):
            y = lib.time_stretch(x, tempo)
            expected = int(np.argmax(np.abs(x))) / tempo
            self.assertLess(abs(int(np.argmax(np.abs(y))) - expected), 0.003 * lib.SR, msg=f"tempo {tempo}")

    def test_tempo_one_returns_an_unchanged_copy(self):
        x = shot()
        y = lib.time_stretch(x, 1.0)
        self.assertTrue(np.array_equal(x, y) and y is not x)

    def test_stereo_keeps_its_shape(self):
        mono = shot()
        stereo = np.stack([mono, mono * 0.5], axis=1)
        y = lib.time_stretch(stereo, 1.5)
        self.assertEqual(y.shape, (round(len(mono) / 1.5), 2))

    def test_loudness_can_be_matched_afterwards(self):
        x = lib.normalize_rms(shot(), -20.0)
        y = lib.normalize_rms(lib.time_stretch(x, 2.0), lib.active_rms_db(x))
        self.assertAlmostEqual(lib.active_rms_db(y), lib.active_rms_db(x), delta=0.6)
        self.assertLessEqual(float(np.max(np.abs(y))), lib.from_db(-0.9))


if __name__ == "__main__":
    unittest.main(verbosity=2)
