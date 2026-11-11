"""CPU delivery regression: real Build/check_spec/cutter, no model or engine.

Standalone: python tools/comfyui/test_final_overrides.py
The valid synthetic schema and all images are created in a temporary folder;
no guest assets, saved source packet, Godot cache or external service is used.
"""
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import struct
import shutil
import tempfile
import unittest
import zlib

from PIL import Image

import build_character
from check_spec import REQUIRED_BONES


class FinalOverrideDeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="final-overrides-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.addCleanup(self.archive_if_requested)
        self.work, self.skin, self.rig = self.root / "source", self.root / "skin", self.root / "rig.json"
        (self.work / "06_parts").mkdir(parents=True)
        (self.work / "overrides").mkdir()
        Image.new("RGBA", (8, 8), (20, 40, 60, 255)).save(self.work / "base_rgba.png")
        for name in ("panel", "trim"):
            Image.new("RGBA", (8, 8), (20, 40, 60, 255)).save(self.work / "06_parts" / f"{name}.png")
        spec = {
            "id": "override_fixture", "display_name": "CPU fixture", "scale": 1,
            "tex_px_per_wp": 1, "illustration_px_per_wp": 1, "ground_y": 8,
            "joints": {"hip": [4, 4]}, "groups": {"body": {"rest": True}},
            "bones": [{"name": name, "parent": "" if name == "hip" else "hip", "at": "hip"}
                      for name in REQUIRED_BONES],
            "parts": {name: {"group": "body", "from": "hip", "to": "hip", "mode": "upright",
                             "uses": [{"name": name, "bone": "hip", "z": 0}]} for name in ("panel", "trim")},
            "glow": {}, "weapon_anchor": {"bone": "hip", "from": "hip", "to": "hip", "dx": 0, "dy": 0, "reach": 1}}
        spec_path = self.root / "spec.json"
        spec_path.write_text(json.dumps(spec), encoding="utf8")
        recipe = {"id": "override_fixture", "work": str(self.work), "spec": str(spec_path), "rig": str(self.rig), "design": {}}
        recipe_path = self.root / "recipe.json"
        recipe_path.write_text(json.dumps(recipe), encoding="utf8")
        self.build = build_character.Build(recipe_path, False, None)
        # Only the destination is redirected. Real schema validation and real
        # subprocess cutter run unchanged, including its staged publication.
        self.build.char_dir = self.skin
        self.run_build()
        self.target = self.skin / "parts/panel.png"
        with Image.open(self.target) as image:
            self.size = image.size
        self.before = self.snapshot()
        Image.new("RGBA", (8, 8), (170, 80, 30, 255)).save(self.work / "06_parts/panel.png")

    def run_build(self):
        with contextlib.redirect_stdout(io.StringIO()):
            return self.build.step_textures()

    def snapshot(self):
        paths = [self.rig, self.skin / "character.json", *sorted((self.skin / "parts").glob("*"))]
        return {str(path.relative_to(self.root)): path.read_bytes() for path in paths if path.is_file()}

    def assert_refused(self, path):
        self.source_before = self.source_snapshot()
        with self.assertRaises(SystemExit) as caught:
            self.run_build()
        self.assertIn(str(path), str(caught.exception))
        self.assertEqual(self.snapshot(), self.before)
        self.assertEqual(self.source_snapshot(), self.source_before)

    def source_snapshot(self):
        return {str(path.relative_to(self.root)): path.read_bytes()
                for path in sorted(self.work.rglob("*")) if path.is_file()}

    def archive_if_requested(self):
        if not os.environ.get("OVERRIDE_EVIDENCE"):
            return
        output = Path(os.environ["OVERRIDE_EVIDENCE"]) / self._testMethodName
        for path in self.root.rglob("*"):
            if path.is_file():
                target = output / "after" / path.relative_to(self.root)
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copyfile(path, target)
        snapshots = {}
        for label, values in [("delivery-before", getattr(self, "before", {})), ("source-before", getattr(self, "source_before", {}))]:
            snapshots[label] = {}
            for name, data in values.items():
                target = output / label / name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
                snapshots[label][name] = hashlib.sha256(data).hexdigest()
        (output / "snapshots.json").write_text(json.dumps(snapshots, indent=2) + "\n", encoding="utf8")

    def png_bytes(self):
        encoded = io.BytesIO()
        Image.new("RGBA", self.size, (15, 85, 145, 235)).save(encoded, format="PNG", compress_level=0)
        return encoded.getvalue()

    def damaged_idat_with_valid_crc(self):
        data = self.png_bytes()
        at = 8
        while at < len(data):
            length = struct.unpack(">I", data[at:at + 4])[0]
            if data[at + 4:at + 8] == b"IDAT":
                payload = bytearray(data[at + 8:at + 8 + length])
                payload[0] = 0  # invalid zlib header; retain a valid PNG chunk CRC
                chunk = b"IDAT" + bytes(payload)
                return data[:at + 4] + chunk + struct.pack(">I", zlib.crc32(chunk)) + data[at + 12 + length:]
            at += 12 + length
        raise AssertionError("synthetic PNG is missing IDAT")

    def test_truncated_png_refuses_before_delivery_changes(self):
        path = self.work / "overrides/panel.png"
        data = self.png_bytes()
        path.write_bytes(data[:data.index(b"IDAT") + 6])
        with Image.open(path) as header:
            self.assertEqual((header.mode, header.size), ("RGBA", self.size))
        self.assert_refused(path)

    def test_valid_crc_broken_idat_requires_complete_decode(self):
        path = self.work / "overrides/panel.png"
        path.write_bytes(self.damaged_idat_with_valid_crc())
        with Image.open(path) as image:
            image.verify()  # CRC-only verification is deliberately insufficient.
        with self.assertRaises(OSError):
            with Image.open(path) as image:
                image.load()
        self.assert_refused(path)

    def test_tiff_named_png_refuses_before_delivery_changes(self):
        path = self.work / "overrides/panel.png"
        Image.new("RGBA", self.size, "blue").save(path, format="TIFF")
        self.assert_refused(path)

    def test_all_overrides_validate_before_first_delivery_change(self):
        first, last = self.work / "overrides/panel.png", self.work / "overrides/trim.png"
        first.write_bytes(self.png_bytes())
        last.write_bytes(self.damaged_idat_with_valid_crc())
        self.assert_refused(last)

    def test_wrong_size_refuses_before_delivery_changes(self):
        path = self.work / "overrides/panel.png"
        Image.new("RGBA", (1, 1), "blue").save(path)
        self.assert_refused(path)

    def test_wrong_mode_refuses_before_delivery_changes(self):
        path = self.work / "overrides/panel.png"
        Image.new("RGB", self.size, "blue").save(path)
        self.assert_refused(path)

    def test_unknown_part_refuses_before_delivery_changes(self):
        path = self.work / "overrides/unknown.png"
        Image.new("RGBA", self.size, "blue").save(path)
        self.assert_refused(path)

    def test_valid_png_keeps_its_original_encoded_bytes(self):
        path = self.work / "overrides/panel.png"
        original = self.png_bytes()
        path.write_bytes(original)
        self.source_before = self.source_snapshot()
        self.run_build()
        self.assertEqual(self.target.read_bytes(), original)
        self.assertEqual(path.read_bytes(), original)
        self.assertEqual(self.source_snapshot(), self.source_before)
        with Image.open(self.target) as image:
            image.load()
            self.assertEqual(image.getpixel((0, 0)), (15, 85, 145, 235))


if __name__ == "__main__":
    unittest.main(verbosity=2)
