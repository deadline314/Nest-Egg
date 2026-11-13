"""CPU regression: source material selection inside a hidden overlap, before publication."""
import contextlib
import importlib.util
from importlib.machinery import SourceFileLoader
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import numpy as np
from PIL import Image
import refine_parts

if os.environ.get("REFINE_UNDER_TEST"):
    path = os.environ["REFINE_UNDER_TEST"]
    loader = importlib.util.spec_from_loader("frozen_underlap", SourceFileLoader("frozen_underlap", path))
    refine_parts = importlib.util.module_from_spec(loader)
    loader.loader.exec_module(refine_parts)


class UnderlapMaterialTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="underlap-material-")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        (self.work / "06_parts").mkdir()
        Image.new("RGBA", (32, 32)).save(self.work / "base_rgba.png")
        self.hand = np.zeros((32, 32, 4), np.uint8)
        self.hand[14:27, 8:21] = (190, 140, 100, 255)
        self.hand[14:18, 8:21] = (100, 70, 40, 255)  # nearest pixel is sleeve colour
        sleeve = np.zeros_like(self.hand)
        sleeve[4:20, 4:26] = (100, 70, 40, 255)
        Image.fromarray(self.hand).save(self.work / "06_parts/hand.png")
        Image.fromarray(sleeve).save(self.work / "06_parts/sleeve.png")
        self.spec = {"parts": {"hand": {}, "sleeve": {}}, "refine": {"underlap": [
            {"part": "hand", "under": "sleeve", "poly": [[8, 8], [20, 8], [20, 16], [8, 16]], "inset": 2}]}}

    def run_refine(self):
        spec = self.work / "spec.json"
        spec.write_text(json.dumps(self.spec), encoding="utf8")
        with patch.object(sys, "argv", ["refine", "--spec", str(spec), "--work", str(self.work)]), contextlib.redirect_stdout(io.StringIO()):
            refine_parts.main()
        return np.array(Image.open(self.work / "07_refined/hand.png"))

    def test_default_nearest_behaviour_and_output_bytes_unchanged(self):
        result = self.run_refine()
        self.assertEqual(result[10, 12].tolist(), [100, 70, 40, 255])
        expected = self.hand.copy()
        expected[8:14, 8:21] = (100, 70, 40, 255)
        np.testing.assert_array_equal(result, expected)
        encoded = io.BytesIO()
        Image.fromarray(expected).save(encoded, format="PNG")
        first = (self.work / "07_refined/hand.png").read_bytes()
        self.assertEqual(first, encoded.getvalue())
        self.run_refine()
        self.assertEqual((self.work / "07_refined/hand.png").read_bytes(), first)

    def test_selected_opaque_material_only_changes_new_overlap_rgb(self):
        old = self.run_refine()
        self.spec["refine"]["underlap"][0]["material_point"] = [12, 22]
        result = self.run_refine()
        self.assertEqual(result[10, 12].tolist(), [190, 140, 100, 255])
        np.testing.assert_array_equal(result[:, :, 3], old[:, :, 3])
        own = self.hand[:, :, 3] > 127
        np.testing.assert_array_equal(result[own], self.hand[own])
        untouched = old[:, :, 3] == 0
        np.testing.assert_array_equal(result[untouched], old[untouched])

    def test_invalid_or_transparent_material_rejects_before_replacing_output(self):
        self.run_refine()
        target = self.work / "07_refined/hand.png"
        before = target.read_bytes()
        for point in [[1, 1], [-1, 22], [32, 22], [12], [True, 22], [float("nan"), 22]]:
            with self.subTest(point=point):
                self.spec["refine"]["underlap"][0]["material_point"] = point
                with self.assertRaisesRegex(ValueError, "material_point"):
                    self.run_refine()
                self.assertEqual(target.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
