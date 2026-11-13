"""Bounded source derivatives publish once, reject stale input and never accumulate."""
import hashlib
import importlib.util
from pathlib import Path
import shutil
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "art_src/characters/guest_zheng"
module_spec = importlib.util.spec_from_file_location("zheng_material", WORK / "register_joint_repairs.py")
registration = importlib.util.module_from_spec(module_spec)
module_spec.loader.exec_module(registration)


class MaterialRegistrationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="guest-material-")
        self.addCleanup(temporary.cleanup)
        self.work = Path(temporary.name)
        (self.work / "07_refined").mkdir()
        for name in ("torso", "pelvis", "leg_lower"):
            shutil.copyfile(WORK / "repair_candidates/adoption-v1" / (name + "-source.png"),
                            self.work / "07_refined" / (name + ".png"))
        shutil.copytree(WORK / "repair_candidates/joint-contours-v1", self.work / "repair_candidates/joint-contours-v1")
        (self.work / "torso_underlayer").mkdir()
        for name in ("candidate_torso.png", "material-review.json"):
            shutil.copyfile(WORK / "torso_underlayer" / name, self.work / "torso_underlayer" / name)

    def hashes(self):
        return {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
                for path in (self.work / "07_refined").glob("*.png")}

    def test_idempotent_and_original_opaque_and_bounded_preservation(self):
        before = {path.stem: np.array(Image.open(path)) for path in (self.work / "07_refined").glob("*.png")}
        with patch.object(registration, "WORK", self.work):
            registration.main()
            once = self.hashes()
            registration.main()
            self.assertEqual(once, self.hashes())
        import json
        records = json.loads((self.work / "repair_candidates/joint-contours-v1/candidates.json").read_text())["candidates"]
        for record in records:
            name = record["part"]
            after = np.array(Image.open(self.work / "07_refined" / (name + ".png")))
            old = before[name]
            np.testing.assert_array_equal(after[old[:, :, 3] >= 128], old[old[:, :, 3] >= 128])
            x0, y0, x1, y1 = record["native_source_box"]
            outside = np.ones(old.shape[:2], bool)
            outside[y0:y1, x0:x1] = False
            np.testing.assert_array_equal(after[outside], old[outside])
        after = np.array(Image.open(self.work / "07_refined/torso.png"))
        np.testing.assert_array_equal(after[:, :, 3], before["torso"][:, :, 3])

    def test_stale_source_rejects_all_before_any_publication(self):
        path = self.work / "07_refined/torso.png"
        path.write_bytes(path.read_bytes() + b"unreviewed source")
        before = self.hashes()
        with patch.object(registration, "WORK", self.work):
            with self.assertRaisesRegex(ValueError, "torso: source differs"):
                registration.main()
        self.assertEqual(before, self.hashes())

    def test_changed_derivative_rejects_all_before_any_publication(self):
        path = self.work / "repair_candidates/joint-contours-v1/leg_lower.png"
        path.write_bytes(path.read_bytes() + b"unreviewed derivative")
        before = self.hashes()
        with patch.object(registration, "WORK", self.work):
            with self.assertRaisesRegex(ValueError, "leg_lower: registered bounded material derivative changed"):
                registration.main()
        self.assertEqual(before, self.hashes())


if __name__ == "__main__":
    unittest.main()
