"""Real retained source bytes: atomic rejection and reproducible registration."""
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest

WORK = Path(__file__).resolve().parent


class WalkRepairRegistration(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.work = self.root / "art_src/characters/guest_zheng"
        for directory in ["07_refined", "repair_candidates/walk-contours-v2/radius-2"]:
            (self.work / directory).mkdir(parents=True)
        source = WORK / "repair_candidates/walk-contours-v2"
        shutil.copyfile(source / "candidates.json", self.work / "repair_candidates/walk-contours-v2/candidates.json")
        shutil.copyfile(WORK / "cut_registration.json", self.work / "cut_registration.json")
        for name in ["pelvis", "foot", "arm_lower"]:
            shutil.copyfile(WORK / "07_refined" / (name + ".png"), self.work / "07_refined" / (name + ".png"))
            shutil.copyfile(source / "radius-2" / (name + "-source.png"), self.work / "repair_candidates/walk-contours-v2/radius-2" / (name + "-source.png"))
        spec = importlib.util.spec_from_file_location("walk_registration", WORK / "register_walk_repairs.py")
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.module.WORK, self.module.ROOT = self.work, self.root

    def tearDown(self):
        self.temporary.cleanup()

    def test_real_sources_are_idempotent_without_crop_or_pivot_changes(self):
        before = json.loads((self.work / "cut_registration.json").read_text(encoding="utf8"))
        self.module.main()
        first = (self.work / "cut_registration.json").read_bytes()
        self.module.main()
        self.assertEqual(first, (self.work / "cut_registration.json").read_bytes())
        after = json.loads(first)
        for name in ["pelvis", "foot", "arm_lower"]:
            target = self.work / "overrides/refined" / (name + ".png")
            candidate = self.work / "repair_candidates/walk-contours-v2/radius-2" / (name + "-source.png")
            self.assertEqual(target.read_bytes(), candidate.read_bytes())
            for field in ["native_affine", "runtime_size", "pivot", "k"]:
                self.assertEqual(before[name][field], after[name][field])
            self.assertNotIn("\\", after[name]["source_path"])

    def test_stale_third_source_rejects_before_any_material_is_written(self):
        source = self.work / "07_refined/arm_lower.png"
        source.write_bytes(source.read_bytes() + b"stale-source")
        registration = (self.work / "cut_registration.json").read_bytes()
        with self.assertRaisesRegex(ValueError, "arm_lower:.*source changed"):
            self.module.main()
        self.assertFalse((self.work / "overrides").exists())
        self.assertEqual(registration, (self.work / "cut_registration.json").read_bytes())

    def test_foreign_override_is_never_overwritten(self):
        target = self.work / "overrides/refined/foot.png"
        target.parent.mkdir(parents=True)
        target.write_bytes(b"another-owner")
        registration = (self.work / "cut_registration.json").read_bytes()
        with self.assertRaisesRegex(ValueError, "foot: another.*override"):
            self.module.main()
        self.assertEqual(target.read_bytes(), b"another-owner")
        self.assertEqual([path.name for path in target.parent.iterdir()], ["foot.png"])
        self.assertEqual(registration, (self.work / "cut_registration.json").read_bytes())


if __name__ == "__main__":
    unittest.main()
