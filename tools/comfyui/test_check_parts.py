"""CPU regressions for texture usage diagnostics; no server or GPU."""
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image
import check_parts


class TextureUsageTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix="nest-egg-parts-")
        self.root = Path(self.folder.name)
        self.character = self.root / "art/characters/test"
        self.character.mkdir(parents=True)
        self.definition = {
            "parts": [{"name": "head", "texture": "head"}],
            "textures": {name: {"file": name + ".png", "pivot": [16, 16]}
                         for name in ["head", "open", "half", "closed", "orphan"]},
            "eye_states": {"part": "head", "open_texture": "open",
                           "half_texture": "half", "closed_texture": "closed"},
        }
        for name in self.definition["textures"]:
            Image.new("RGBA", (32, 32), (70, 90, 120, 255)).save(self.character / (name + ".png"))
        self.root_patch = patch.object(check_parts, "ROOT", self.root)
        self.root_patch.start()

    def tearDown(self):
        self.root_patch.stop()
        self.folder.cleanup()

    def check(self):
        (self.character / "character.json").write_text(json.dumps(self.definition), encoding="utf8")
        return check_parts.check_character("test")

    def test_blink_alternatives_are_used_but_orphan_is_not(self):
        self.assertEqual(self.check(), ["orphan: no part uses this texture"])

    def test_referenced_blink_file_is_still_checked(self):
        (self.character / "half.png").unlink()
        problems = self.check()
        self.assertIn("half: file half.png is missing", problems)
        self.assertNotIn("half: no part uses this texture", problems)
        self.assertIn("orphan: no part uses this texture", problems)

    def test_absent_and_malformed_eye_states_do_not_hide_unused_textures(self):
        for value in [None, [], "half", {"half_texture": []}]:
            with self.subTest(eye_states=value):
                self.definition["eye_states"] = value
                self.assertIn("half: no part uses this texture", self.check())


if __name__ == "__main__":
    unittest.main()
