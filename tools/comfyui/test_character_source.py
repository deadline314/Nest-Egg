"""CPU checks for retained source provenance and failure-safe publication; no model or GPU."""
import hashlib
import json
import tempfile
import unittest
import subprocess
import sys
from pathlib import Path
from unittest.mock import patch

from PIL import Image

import build_character
import field_spec
from character_source import publish_source, read_source


class RetainedSourceTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix="nest-egg-character-source-")
        self.addCleanup(self.folder.cleanup)
        self.root = Path(self.folder.name)
        self.work = self.root / "art_src/characters/sample"
        self.work.mkdir(parents=True)
        self.source = self.work / "original.png"
        image = Image.new("RGBA", (4, 6), (23, 45, 67, 0))
        image.putpixel((2, 3), (123, 111, 99, 255))
        image.putpixel((1, 3), (77, 66, 55, 120))
        image.save(self.source)
        self.record = {"source": self.source.relative_to(self.root).as_posix(), "dimensions": [4, 6],
                       "sha256": hashlib.sha256(self.source.read_bytes()).hexdigest()}
        self.record_path = self.work / "source.json"
        self.record_name = self.record_path.relative_to(self.root).as_posix()
        self.save_record()
        self.target = self.work / "base_rgba.png"

    def save_record(self):
        self.record_path.write_text(json.dumps(self.record), encoding="utf-8")

    def test_publishes_original_png_bytes_and_preserves_repeat_timestamp(self):
        publish_source(self.root, self.record_name, self.target)
        self.assertEqual(self.target.read_bytes(), self.source.read_bytes())
        timestamp = self.target.stat().st_mtime_ns
        publish_source(self.root, self.record_name, self.target)
        self.assertEqual(self.target.stat().st_mtime_ns, timestamp)

    def test_wrong_sha_or_size_cannot_replace_existing_source_even_when_forced(self):
        for field, invalid in [("sha256", "0" * 64), ("dimensions", [8, 6])]:
            with self.subTest(field=field):
                original = dict(self.record)
                self.record[field] = invalid
                self.save_record()
                self.target.write_bytes(b"existing approved source")
                with self.assertRaises(ValueError):
                    publish_source(self.root, self.record_name, self.target, force=True)
                self.assertEqual(self.target.read_bytes(), b"existing approved source")
                self.record = original

    def test_replacement_requires_explicit_selection_and_never_writes_original(self):
        self.target.write_bytes(b"previous source")
        with self.assertRaisesRegex(ValueError, "already exists"):
            publish_source(self.root, self.record_name, self.target)
        self.assertEqual(self.target.read_bytes(), b"previous source")
        with self.assertRaisesRegex(ValueError, "original"):
            publish_source(self.root, self.record_name, self.source, force=True)
        publish_source(self.root, self.record_name, self.target, force=True)
        self.assertEqual(self.target.read_bytes(), self.source.read_bytes())

    def test_path_escapes_are_rejected_before_writing(self):
        with self.assertRaisesRegex(ValueError, "outside"):
            publish_source(self.root, self.record_name, self.root / "elsewhere.png")
        self.record["source"] = "outside.png"
        self.save_record()
        with self.assertRaisesRegex(ValueError, "inside"):
            read_source(self.root, self.record_name)
        self.assertFalse(self.target.exists())

    def test_missing_contract_fields_report_the_record_path(self):
        del self.record["sha256"]
        self.save_record()
        with self.assertRaisesRegex(ValueError, "source.json"):
            read_source(self.root, self.record_name)

    def test_rgb_or_empty_alpha_cannot_be_adopted(self):
        for mode, color in [("RGB", "red"), ("RGBA", (0, 0, 0, 0)), ("RGBA", (0, 0, 0, 255))]:
            with self.subTest(mode=mode, color=color):
                Image.new(mode, (4, 6), color).save(self.source)
                self.record["sha256"] = hashlib.sha256(self.source.read_bytes()).hexdigest()
                self.save_record()
                with self.assertRaises(ValueError):
                    read_source(self.root, self.record_name)

    def test_design_import_uses_no_model_and_refuses_seed_regeneration(self):
        build = object.__new__(build_character.Build)
        build.recipe = {"design": {"source_record": self.record_name}}
        build.id, build.work, build.force, build.seed = "sample", self.work, False, None
        with patch.object(build_character, "ROOT", self.root), patch.object(build, "check"), patch.dict("sys.modules", {"comfy_api": None}):
            self.assertEqual(build.step_design(), [self.target.resolve()])
            original = self.target.read_bytes()
            build.seed = 42
            with self.assertRaisesRegex(ValueError, "no local generation seed"):
                build.step_design()
            self.assertEqual(self.target.read_bytes(), original)

    def test_spec_cli_rejects_seed_and_retained_source_together(self):
        result = subprocess.run([sys.executable, str(Path(field_spec.__file__)), "--id", "unused",
                                 "--name", "Unused", "--height", "56", "--seed", "42",
                                 "--source-record", "unused.json"], capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn(b"not allowed with argument", result.stderr)

    def test_spec_refuses_changed_base_before_pose_or_output(self):
        design = self.work / "01_design"
        design.mkdir()
        (design / "prompt.txt").write_text("Retained native source", encoding="utf-8")
        changed = Image.open(self.source).copy()
        changed.putpixel((2, 3), (80, 90, 100, 255))
        changed.save(self.target)
        before = self.target.read_bytes()
        argv = ["field_spec.py", "--id", "sample", "--name", "Sample", "--height", "56",
                "--source-record", self.record_name]
        with patch.object(field_spec, "ROOT", self.root), patch.object(sys, "argv", argv), \
                patch.object(field_spec.subprocess, "run", side_effect=AssertionError("must not launch a model")):
            with self.assertRaisesRegex(ValueError, "exactly match"):
                field_spec.main()
        self.assertEqual(self.target.read_bytes(), before)
        self.assertFalse((self.root / "tools/comfyui/specs/sample_side.json").exists())
        self.assertFalse((self.root / "tools/comfyui/recipes/sample.json").exists())


if __name__ == "__main__":
    unittest.main()
