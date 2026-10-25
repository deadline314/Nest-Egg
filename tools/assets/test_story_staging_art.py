import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from PIL import Image

from story_staging_art import build


class StoryStagingArtTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        Image.new("RGBA", (17, 13), (110, 80, 50, 253)).save(self.root / "frozen.png")
        self.source = (self.root / "frozen.png").read_bytes()
        self.entry = dict(input="frozen.png", sha256=hashlib.sha256(self.source).hexdigest(), size=[17, 13],
                          output="art/environment/fixture.png", kind="prop", emission="none", grade={},
                          alpha_floor=8, pad_even=True, normal=dict(profile="pillow", round_px=3, relief=.1, detail=0))

    def recipe(self, *entries):
        return dict(version=1, files=list(entries or [self.entry]))

    def test_even_padding_and_normals_are_deterministic_and_source_is_immutable(self):
        recipe = self.recipe()
        before = json.dumps(recipe)
        first = build(recipe, self.root, False)
        self.assertEqual(first, build(recipe, self.root, False))
        self.assertEqual((self.root / "frozen.png").read_bytes(), self.source)
        self.assertEqual(json.dumps(recipe), before)
        self.assertEqual(first["files"][0]["canvas_size"], [18, 14])
        for output in first["files"][0]["outputs"]:
            with Image.open(self.root / output["file"]) as image:
                self.assertEqual(image.size, (18, 14))
                self.assertEqual(image.getpixel((17, 13))[3], 0)
        self.assertFalse(list(self.root.rglob(".staging-*")))

    def test_bad_later_source_preserves_all_previous_outputs(self):
        build(self.recipe(), self.root, False)
        output = self.root / self.entry["output"]
        previous = output.read_bytes()
        second = self.entry | dict(output="art/environment/second.png", sha256="0" * 64)
        with self.assertRaisesRegex(ValueError, "hash"):
            build(self.recipe(self.entry, second), self.root, False)
        self.assertEqual(output.read_bytes(), previous)
        self.assertFalse((self.root / second["output"]).exists())

    def test_paths_normal_collisions_and_input_overwrites_are_rejected(self):
        for path in ["../outside.png", "/tmp/escape.png", "art/environment/../../game/escape.png"]:
            with self.subTest(path=path), self.assertRaises(ValueError):
                build(self.recipe(self.entry | dict(output=path)), self.root, False)
        second = self.entry | dict(output="art/environment/fixture_n.png")
        with self.assertRaisesRegex(ValueError, "duplicate"):
            build(self.recipe(self.entry, second), self.root, False)
        source = self.root / self.entry["output"]
        source.parent.mkdir(parents=True)
        source.write_bytes(self.source)
        with self.assertRaisesRegex(ValueError, "frozen input"):
            build(self.recipe(self.entry | dict(input=self.entry["output"])), self.root, False)
        self.assertEqual(source.read_bytes(), self.source)

    def test_invalid_recipe_parameters_fail_before_creating_art(self):
        for edit in [dict(size=[17, 12]), dict(kind="unknown"), dict(pad_even=1), dict(alpha_floor=33), dict(alpha_floor=True),
                     dict(grade={"brightness": float("inf")}), dict(grade={"tint": [1, 1, float("nan")]}),
                     dict(normal={"profile": "unknown"}), dict(normal={"detail_sigma": 10000}),
                     dict(normal={"strength": float("nan")}), dict(normal={"arbitrary": 1})]:
            with self.subTest(edit=edit), self.assertRaises(ValueError):
                build(self.recipe(self.entry | copy.deepcopy(edit)), self.root, False)
            self.assertFalse((self.root / "art").exists())


if __name__ == "__main__":
    unittest.main()
