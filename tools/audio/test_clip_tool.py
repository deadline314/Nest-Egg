"""音訊片段擷取工具的測試（NE-179）：用合成的短音訊、暫存資料夾，不依賴下載的素材，也不動專案的資料。

用法：python tools/audio/test_clip_tool.py（需要 ffmpeg；沒有時略過）
"""
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import audio_lib as lib  # noqa: E402
import clip_tool as ct  # noqa: E402

SR = 48000
HAVE_FFMPEG = shutil.which("ffmpeg") is not None and shutil.which("ffprobe") is not None


def burst(seconds: float, freq: float) -> np.ndarray:
    t = np.arange(int(SR * seconds)) / SR
    return (np.sin(2 * np.pi * freq * t) * np.exp(-t * 18.0) * 0.8).astype(np.float32)


def two_bursts() -> np.ndarray:
    """0.0–0.3 秒一聲、1.0–1.3 秒一聲，中間靜音；共 2 秒。"""
    x = np.zeros(int(SR * 2.0), dtype=np.float32)
    x[: int(SR * 0.3)] = burst(0.3, 440.0)
    x[int(SR * 1.0): int(SR * 1.3)] = burst(0.3, 880.0)
    return x


class SegmentsTest(unittest.TestCase):
    def test_finds_each_burst(self):
        segments = lib.find_segments(two_bursts(), SR)
        self.assertEqual(len(segments), 2)
        self.assertAlmostEqual(segments[1][0], 1.0, delta=0.05)
        self.assertLess(segments[0][1], 0.6)

    def test_silence_and_noise_floor(self):
        self.assertEqual(lib.find_segments(np.zeros(SR, dtype=np.float32), SR), [])
        self.assertEqual(len(lib.find_segments(two_bursts() + 1e-5, SR)), 2)

    def test_close_hits_merge(self):
        x = np.zeros(SR, dtype=np.float32)
        x[: int(SR * 0.1)] = burst(0.1, 440.0)
        x[int(SR * 0.2): int(SR * 0.3)] = burst(0.1, 440.0)
        self.assertEqual(len(lib.find_segments(x, SR, min_gap_ms=150.0)), 1)

    def test_peaks_shape(self):
        peaks = lib.peaks(two_bursts(), 100)
        self.assertEqual(len(peaks), 100)
        self.assertTrue(all(low <= high for low, high in peaks))


@unittest.skipUnless(HAVE_FFMPEG, "需要 ffmpeg 與 ffprobe")
class ClipToolTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="test_audio_clip_"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        audio_src = self.tmp / "assets_src" / "audio"
        raw = self.tmp / "assets_src" / "raw" / "audio"
        (raw / "packA").mkdir(parents=True)
        audio_src.mkdir(parents=True)
        pcm = np.ascontiguousarray(two_bursts(), dtype=np.float32).tobytes()
        subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-", "-c:a", "pcm_s24le", str(raw / "packA" / "two.wav")],
                       input=pcm, check=True)
        (audio_src / "catalog.json").write_text(json.dumps({"_說明": "t", "categories": {"GUN": "槍聲"}, "assets": {
            "GUN-0007": {"pack": "packA", "file": "two.wav", "dur": 2.0, "desc": "兩聲"}}}, ensure_ascii=False, indent=0) + "\n", encoding="utf-8")
        (audio_src / "manifest.json").write_text(json.dumps({"packs": [{"id": "packA", "kind": "sfx", "title": "A", "author": "a", "license": "CC0-1.0",
                                                                        "page": "https://example.test/a", "download": "https://example.test/a.zip", "dir": "packA"}]},
                                                            ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
        patches = {"ROOT": self.tmp, "RAW": raw, "AUDIO_SRC": audio_src, "CATALOG": audio_src / "catalog.json", "MANIFEST": audio_src / "manifest.json",
                   "CLIPS": audio_src / "clips.json", "EDIT_DIR": self.tmp / "assets_src" / "work" / "clip_edit"}
        for name, value in patches.items():
            patcher = mock.patch.object(ct, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)
        self.raw = raw

    def clips(self):
        return json.loads(ct.CLIPS.read_text(encoding="utf-8"))["clips"] if ct.CLIPS.exists() else []

    def test_prepare_gives_waveform_and_segments(self):
        doc = ct.prepare("GUN-0007")
        self.assertEqual(len(doc["segments"]), 2)
        self.assertTrue((self.tmp / "assets_src" / "work" / "clip_edit" / "GUN-0007" / "long.ogg").is_file())
        self.assertGreater(len(doc["peaks"]), 100)
        self.assertFalse(doc["truncated"])
        self.assertAlmostEqual(doc["duration"], 2.0, delta=0.01)
        self.assertTrue(ct.prepare("GUN-0007", max_seconds=0.5)["truncated"])

    def test_export_keeps_format_and_registers(self):
        result = ct.export("GUN-0007", 0.95, 1.4, note="第二聲", preview=False)
        self.assertEqual(result["id"], "GUN-0008")
        self.assertFalse(result["existing"])
        out = self.raw / "clips_sfx" / "GUN-0008.wav"
        info = ct.probe(out)
        self.assertEqual((info["sample_rate"], info["codec"]), (SR, "pcm_s24le"))
        self.assertAlmostEqual(info["duration"], 0.45, delta=0.01)
        clip = self.clips()[0]
        self.assertEqual((clip["parent"], clip["parent_pack"], clip["parent_file"], clip["start"], clip["end"]), ("GUN-0007", "packA", "two.wav", 0.95, 1.4))
        asset = json.loads(ct.CATALOG.read_text(encoding="utf-8"))["assets"]["GUN-0008"]
        self.assertEqual((asset["pack"], asset["file"], asset["parent"]), ("clips_sfx", "GUN-0008.wav", "GUN-0007"))
        pack = [p for p in json.loads(ct.MANIFEST.read_text(encoding="utf-8"))["packs"] if p["id"] == "clips_sfx"][0]
        self.assertTrue(pack["local"] and pack["license"] == "CC0-1.0" and pack["download"] == [] and pack["page"])

    def test_samples_match_the_original(self):
        ct.export("GUN-0007", 1.0, 1.3, preview=False)
        got = lib.decode(self.raw / "clips_sfx" / "GUN-0008.wav", sr=SR)
        want = two_bursts()[int(SR * 1.0): int(SR * 1.3)]
        n = min(len(got), len(want))
        self.assertLess(float(np.max(np.abs(got[:n] - want[:n]))), 1e-4)

    def test_duplicate_range_returns_existing(self):
        first = ct.export("GUN-0007", 0.0, 0.3, preview=False)
        again = ct.export("GUN-0007", 0.005, 0.305, preview=False)
        self.assertTrue(again["existing"])
        self.assertEqual(again["id"], first["id"])
        self.assertEqual(len(self.clips()), 1)
        self.assertEqual(len(list((self.raw / "clips_sfx").glob("*.wav"))), 1)
        self.assertFalse(ct.export("GUN-0007", 0.0, 0.6, preview=False)["existing"])

    def test_ids_are_never_reused(self):
        ct.export("GUN-0007", 0.0, 0.3, preview=False)
        doc = json.loads(ct.CATALOG.read_text(encoding="utf-8"))
        del doc["assets"]["GUN-0008"]  # 目錄少了編號，片段清單仍記得
        ct.CATALOG.write_text(json.dumps(doc, ensure_ascii=False, indent=0) + "\n", encoding="utf-8")
        self.assertEqual(ct.export("GUN-0007", 1.0, 1.3, preview=False)["id"], "GUN-0009")

    def test_bad_ranges_and_missing_files_explain_and_leave_nothing(self):
        before = ct.CATALOG.read_text(encoding="utf-8")
        for start, end in [(0.5, 0.5), (1.0, 0.5), (-1.0, 0.5), (1.5, 9.0)]:
            with self.assertRaises(ct.ClipError) as caught:
                ct.export("GUN-0007", start, end, preview=False)
            self.assertIn("GUN-0007", str(caught.exception))
        with self.assertRaises(ct.ClipError) as caught:
            ct.export("GUN-9999", 0.0, 0.3, preview=False)
        self.assertIn("GUN-9999", str(caught.exception))
        (self.raw / "packA" / "two.wav").rename(self.raw / "packA" / "moved.wav")
        with self.assertRaises(ct.ClipError) as caught:
            ct.export("GUN-0007", 0.0, 0.3, preview=False)
        self.assertIn("packA", str(caught.exception))
        self.assertEqual(self.clips(), [])
        self.assertEqual(ct.CATALOG.read_text(encoding="utf-8"), before)
        self.assertFalse(list(self.raw.rglob("*.part")) or list(self.raw.rglob("clips_*")))

    def test_write_failure_rolls_back(self):
        before = ct.CATALOG.read_text(encoding="utf-8")
        real = ct.write_atomic
        calls = {"n": 0}

        def flaky(path, text):
            calls["n"] += 1
            if calls["n"] == 2:  # 第二個檔案寫入失敗
                raise OSError("disk full")
            real(path, text)

        with mock.patch.object(ct, "write_atomic", flaky):
            with self.assertRaises(ct.ClipError):
                ct.export("GUN-0007", 0.0, 0.3, preview=False)
        self.assertEqual(self.clips(), [])
        self.assertEqual(ct.CATALOG.read_text(encoding="utf-8"), before)
        self.assertFalse((self.raw / "clips_sfx" / "GUN-0008.wav").exists())

    def test_rebuild_restores_missing_outputs(self):
        ct.export("GUN-0007", 1.0, 1.3, preview=False)
        out = self.raw / "clips_sfx" / "GUN-0008.wav"
        out.unlink()
        doc = json.loads(ct.CATALOG.read_text(encoding="utf-8"))
        del doc["assets"]["GUN-0008"]
        ct.CATALOG.write_text(json.dumps(doc, ensure_ascii=False, indent=0) + "\n", encoding="utf-8")
        made, errors = ct.rebuild()
        self.assertEqual((made, errors), (1, []))
        self.assertAlmostEqual(ct.probe(out)["duration"], 0.3, delta=0.01)
        self.assertIn("GUN-0008", json.loads(ct.CATALOG.read_text(encoding="utf-8"))["assets"])
        self.assertEqual(ct.rebuild(), (0, []))

    def test_rebuild_reports_a_missing_original(self):
        ct.export("GUN-0007", 1.0, 1.3, preview=False)
        (self.raw / "clips_sfx" / "GUN-0008.wav").unlink()
        (self.raw / "packA" / "two.wav").unlink()
        made, errors = ct.rebuild()
        self.assertEqual(made, 0)
        self.assertTrue(errors and "packA" in errors[0])

    def test_a_clip_cannot_be_clipped_again(self):
        ct.export("GUN-0007", 0.0, 0.5, preview=False)
        with self.assertRaises(ct.ClipError) as caught:
            ct.export("GUN-0008", 0.0, 0.2, preview=False)
        self.assertIn("GUN-0007", str(caught.exception))


if __name__ == "__main__":
    unittest.main(verbosity=2)
