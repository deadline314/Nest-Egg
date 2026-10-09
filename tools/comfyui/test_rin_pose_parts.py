"""Offline source/assembly checks; these do not certify animation or anatomy."""
import contextlib
import hashlib
import io
import json
import shutil
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

from rin_pose_parts import build, WORK


class PosePartsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.work = Path(self.temp.name)
        shutil.copy(WORK / "poses.json", self.work / "poses.json")
        for folder in ("01_candidates", "04_refinement"):
            shutil.copytree(WORK / folder, self.work / folder)

    def tearDown(self):
        self.temp.cleanup()

    def run_build(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return build(self.work)

    def hashes(self):
        return {p.relative_to(self.work).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
                for p in (self.work / "03_parts").rglob("*") if p.is_file()}

    def test_source_pixels_pivots_and_repeatability(self):
        report = self.run_build()
        spec = json.loads((self.work / "poses.json").read_text())
        for name, summary in report.items():
            self.assertEqual(summary["unassigned_pixels"], 0)
            self.assertTrue(all(c == 1 for c in summary["components"].values()))
            folder = self.work / "03_parts" / name
            source = np.array(Image.open(folder / "source_rgba.png"))
            metadata = json.loads((folder / "parts.json").read_text())
            for part in metadata["parts"]:
                piece = np.array(Image.open(folder / part["file"]))
                x0, y0, x1, y1 = part["box"]
                used = piece[:, :, 3] > 0
                np.testing.assert_array_equal(piece[used], source[y0:y1, x0:x1][used])
                self.assertEqual([part["pivot"][0] + x0, part["pivot"][1] + y0], metadata["joints"][part["joint"]])
            if spec[name].get("replacement"):
                original = np.array(Image.open(self.work / spec[name]["source"]))
                keep = original[:, :, 3] > 8
                for polygon in [spec[name]["replacement"]["polygon"], *spec[name].get("clear_polygons", [])]:
                    m = Image.new("L", (original.shape[1], original.shape[0]))
                    ImageDraw.Draw(m).polygon([tuple(p) for p in polygon], fill=255)
                    keep &= np.array(m) == 0
                np.testing.assert_array_equal(source[keep], original[keep])
        before = self.hashes()
        self.run_build()
        self.assertEqual(self.hashes(), before)

    def test_invalid_inputs_keep_previous_outputs(self):
        self.run_build()
        before = self.hashes()
        spec = json.loads((self.work / "poses.json").read_text())
        spec["crouch"]["parts"] = []
        (self.work / "poses.json").write_text(json.dumps(spec))
        with self.assertRaisesRegex(AssertionError, "unassigned"):
            self.run_build()
        self.assertEqual(self.hashes(), before)

    def test_changed_source_and_wrong_canvas_are_rejected(self):
        self.run_build()
        before = self.hashes()
        spec = json.loads((self.work / "poses.json").read_text())
        spec["kneel"]["source_sha256"] = "0" * 64
        (self.work / "poses.json").write_text(json.dumps(spec))
        with self.assertRaisesRegex(AssertionError, "hash mismatch"):
            self.run_build()
        self.assertEqual(self.hashes(), before)
        spec = json.loads((WORK / "poses.json").read_text())
        replacement = self.work / spec["kneel"]["replacement"]["image"]
        Image.new("RGBA", (32, 32)).save(replacement)
        spec["kneel"]["replacement"]["sha256"] = hashlib.sha256(replacement.read_bytes()).hexdigest()
        (self.work / "poses.json").write_text(json.dumps(spec))
        with self.assertRaisesRegex(AssertionError, "canvas mismatch"):
            self.run_build()
        self.assertEqual(self.hashes(), before)


if __name__ == "__main__":
    unittest.main()
