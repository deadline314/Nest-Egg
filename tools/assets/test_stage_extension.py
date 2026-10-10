import copy
import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np
from PIL import Image

from stage_extension import compose, project_path, size_pair


class StageExtensionTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        original = Image.new("RGB", (16, 8), (120, 60, 30))
        original.save(self.root / "original.webp", "WEBP", lossless=True, method=6)
        Image.new("RGB", (32, 24), (0, 0, 0)).save(self.root / "raw.png")
        # Independently derived one-pixel border around an unchanged centre.
        expected = np.zeros((24, 32, 3), dtype=np.uint8)
        expected[7:17, 7:25] = [120, 60, 30]
        Image.fromarray(expected).save(self.root / "expected.webp", "WEBP", lossless=True, method=6)
        sha = lambda name: hashlib.sha256((self.root / name).read_bytes()).hexdigest()
        self.entry = {"id": "fixture", "original": "original.webp", "original_sha256": sha("original.webp"), "original_size": [16, 8],
            "raw": "raw.png", "raw_sha256": sha("raw.png"), "raw_size": [32, 24], "registration_canvas": [32, 24],
            "registration_matrix": [[1, 0, 0], [0, 1, 0]], "original_canvas_xy": [8, 8], "crop_xywh": [0, 0, 32, 24],
            "edge_match_fade_px": 1, "out": "out.webp", "out_sha256": sha("expected.webp"),
            "scale": .5, "source_width": 32, "world_origin": [-4, -4], "original_world_origin": [0, 0]}

    def test_reconstructs_exact_centre_and_bounded_edge_without_mutating_recipe(self):
        before = json.dumps(self.entry)
        result = compose(self.entry, self.root)
        self.assertTrue(result["centre_unchanged"])
        self.assertFalse(result["native_adopted"])
        self.assertEqual(result["out_sha256"], self.entry["out_sha256"])
        self.assertEqual(json.dumps(self.entry), before)
        with Image.open(self.root / "out.webp") as image:
            self.assertEqual(image.crop((8, 8, 24, 16)).tobytes(), Image.new("RGB", (16, 8), (120, 60, 30)).tobytes())

    def test_unreviewed_result_preserves_previous_output(self):
        (self.root / "out.webp").write_bytes(b"previous reviewed image")
        self.entry["out_sha256"] = "0" * 64
        with self.assertRaises(ValueError):
            compose(self.entry, self.root)
        self.assertEqual((self.root / "out.webp").read_bytes(), b"previous reviewed image")
        self.assertFalse((self.root / "out.webp.candidate").exists())

    def test_changed_source_or_raw_never_writes_output(self):
        for field in ["original_sha256", "raw_sha256"]:
            entry = copy.deepcopy(self.entry)
            entry[field] = "0" * 64
            with self.assertRaises(ValueError):
                compose(entry, self.root)
            self.assertFalse((self.root / "out.webp").exists())

    def test_crop_cannot_remove_furniture(self):
        self.entry["crop_xywh"] = [9, 0, 23, 24]
        with self.assertRaises(ValueError):
            compose(self.entry, self.root)

    def test_affine_does_not_stretch_or_invent_large_edges(self):
        for matrix in [[[1, .2, 0], [0, 1, 0]], [[1, 0, 100], [0, 1, 0]], [[float("nan"), 0, 0], [0, 1, 0]]]:
            entry = copy.deepcopy(self.entry)
            entry["registration_matrix"] = matrix
            with self.assertRaises(ValueError):
                compose(entry, self.root)

    def test_project_paths_and_decoded_budget_are_bounded(self):
        with self.assertRaises(ValueError):
            project_path(self.root, "../outside.webp")
        for size in [[True, 3], [0, 2], [3000, 3000], [3.0, 4]]:
            with self.assertRaises(ValueError):
                size_pair(size, "fixture")

    def test_world_contract_cannot_move_or_shrink_original_furniture(self):
        for change in [{"world_origin": [0, 0]}, {"source_width": 16}, {"scale": float("inf")}]:
            entry = copy.deepcopy(self.entry)
            entry.update(change)
            with self.assertRaises(ValueError):
                compose(entry, self.root)


if __name__ == "__main__":
    unittest.main()
