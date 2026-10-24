"""Regression controls for review sheets; the original joint verdict remains unchanged."""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

import numpy as np
from PIL import Image

from check_joint_frames import inspect
from joint_audit_both import class_sheet

TOOLS = Path(__file__).resolve().parent


class JointAuditSheetTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)

    def sample(self, alpha, *, radius=10, joint="joint", pose="idle", color=(70, 80, 90)):
        name = f"{joint}-{pose}.png"
        pixels = np.empty((128, 128, 4), dtype=np.uint8)
        pixels[:, :, :3] = color
        pixels[:, :, 3] = alpha
        Image.fromarray(pixels).save(self.root / name)
        metrics = inspect(alpha[64-radius:64+radius, 64-radius:64+radius])
        self.assertTrue(metrics["components"] != 1 or metrics["hole_pixels"] or metrics["center_alpha"] < 128)
        return dict(char="fixture", facing=1, joint=joint, radius=radius,
                    rect=[0, 0, 128, 128], pose=pose, zoom=3.4, file=name,
                    frame=0, seconds=1/60, **metrics)

    def render(self, samples):
        report = {"failures": samples}
        out = self.root / "sheet.png"
        with contextlib.redirect_stdout(io.StringIO()):
            class_sheet(self.root, report, self.root, report, out, cols=1)
        return np.array(Image.open(out).convert("RGB"))

    def assert_focused_marker(self, pixels):
        # A single source pixel is outlined at the centre of the 44px review crop.
        self.assertEqual(tuple(pixels[22*11, 22*11]), (0, 255, 0))

    def test_enclosed_hole_outside_checked_band_cannot_steal_focus(self):
        alpha = np.zeros((128, 128), np.uint8)
        alpha[48:80, 48:80] = 255
        alpha[62, 62] = 0
        alpha[0:36, 0:36] = 255
        alpha[10:26, 10:26] = 0  # unrelated pocket outside the actual joint band
        self.assert_focused_marker(self.render([self.sample(alpha)]))

    def test_outside_component_cannot_relabel_intact_joint_material(self):
        alpha = np.zeros((128, 128), np.uint8)
        alpha[54:74, 58:66] = 255
        alpha[65, 70] = 255  # the only loose piece in the checked band
        alpha[0:48, 0:48] = 255  # larger but entirely outside that band
        self.assert_focused_marker(self.render([self.sample(alpha)]))

    def test_focus_is_a_real_bad_pixel_not_the_average_between_pockets(self):
        alpha = np.full((128, 128), 255, np.uint8)
        alpha[64, 63] = 0
        alpha[88:108, 88:108] = 0
        self.assert_focused_marker(self.render([self.sample(alpha, radius=50)]))

    def test_stale_report_keeps_previous_sheet(self):
        alpha = np.full((128, 128), 255, np.uint8)
        alpha[62, 62] = 0
        sample = self.sample(alpha)
        Image.new("RGBA", (128, 128), (70, 80, 90, 255)).save(self.root / sample["file"])
        out = self.root / "previous.png"
        out.write_bytes(b"previous review sheet")
        report = {"failures": [sample]}
        with contextlib.redirect_stdout(io.StringIO()):
            with self.assertRaisesRegex(ValueError, "no matching pixels"):
                class_sheet(self.root, report, self.root, report, out, cols=1)
        self.assertEqual(out.read_bytes(), b"previous review sheet")

    def test_representatives_and_tile_order_are_stable_across_hash_seeds(self):
        samples = []
        for joint in ["a_joint", "z_joint", "m_joint"]:
            for pose, color in [("run", (200, 20, 30)), ("idle", (20, 30, 200))]:
                alpha = np.full((128, 128), 255, np.uint8)
                alpha[62, 62] = 0
                samples.append(self.sample(alpha, joint=joint, pose=pose, color=color))
        report = self.root / "report.json"
        report.write_text(json.dumps({"failures": samples}))
        code = ("import json,sys; from pathlib import Path; "
                "sys.path.insert(0,sys.argv[1]); from joint_audit_both import class_sheet; "
                "p=Path(sys.argv[2]); r=json.loads((p/'report.json').read_text()); "
                "class_sheet(p,r,p,r,p/sys.argv[3],cols=2)")
        hashes = []
        for seed in range(6):
            name = f"seed-{seed}.png"
            subprocess.run([sys.executable, "-c", code, str(TOOLS), str(self.root), name],
                           check=True, capture_output=True, text=True,
                           env={**os.environ, "PYTHONHASHSEED": str(seed)})
            hashes.append(hashlib.sha256((self.root / name).read_bytes()).hexdigest())
        self.assertEqual(len(set(hashes)), 1, "identical reports must select the same frames and order")


if __name__ == "__main__":
    unittest.main()
