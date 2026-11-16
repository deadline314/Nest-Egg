"""CPU regression: transparent RGB cannot supply colour to source-alpha fills."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage


path = Path(os.environ.get("REFINE_UNDER_TEST", Path(__file__).with_name("refine_parts.py")))
loader = importlib.util.spec_from_file_location("refine_fill_target", path)
refine_parts = importlib.util.module_from_spec(loader)
loader.loader.exec_module(refine_parts)


class RefineFillTests(unittest.TestCase):
    def fixture(self, operation, colour):
        layer = np.zeros((40, 40, 4), np.uint8)
        layer[7:33, 7:33] = (80, 100, 120, 255)
        if operation == "close_fill":
            layer[7:18, 18:21, 3] = 0
        else:
            layer[10:13, 10:13, 3] = 0
        layer[3, 3] = (50, 60, 70, 64)
        layer[layer[:, :, 3] == 0, :3] = colour
        return layer

    def run_refine(self, layer, operation, mode=True):
        with tempfile.TemporaryDirectory(prefix="refine-fill-") as directory:
            work = Path(directory)
            (work / "06_parts").mkdir()
            Image.fromarray(layer).save(work / "base_rgba.png")
            Image.fromarray(layer).save(work / "06_parts/body.png")
            config = {"parts": ["body"], **({"radius": 4} if operation == "close_fill" else {"max_area": 200})}
            spec = {"parts": {"body": {}}, "refine": {operation: config}}
            if mode is not None:
                spec["preserve_source_alpha"] = mode
            spec_path = work / "spec.json"
            spec_path.write_text(json.dumps(spec), encoding="utf-8")
            with patch.object(sys, "argv", ["refine", "--spec", str(spec_path), "--work", str(work)]), contextlib.redirect_stdout(io.StringIO()):
                refine_parts.main()
            target = work / "07_refined/body.png"
            with Image.open(target) as image:
                result = np.array(image)
            return result, target.read_bytes()

    def fill_mask(self, layer, operation):
        solid = layer[:, :, 3] > 127
        if operation == "close_fill":
            kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9))
            return (cv2.morphologyEx(solid.astype(np.uint8), cv2.MORPH_CLOSE, kernel) > 0) & ~solid
        holes = ndimage.binary_fill_holes(solid) & ~solid
        kernel = cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (3, 3))
        return cv2.dilate(holes.astype(np.uint8), kernel) > 0

    def test_transparent_rgb_cannot_colour_either_fill(self):
        for operation in ["close_fill", "fill_holes"]:
            with self.subTest(operation=operation):
                clean = self.fixture(operation, (80, 100, 120))
                poisoned = self.fixture(operation, (255, 0, 255))
                clean_result, _ = self.run_refine(clean, operation)
                result, _ = self.run_refine(poisoned, operation)
                self.assertTrue(np.any((clean[:, :, 3] == 0) & (result[:, :, 3] > 0)))
                np.testing.assert_array_equal(result[:, :, 3], clean_result[:, :, 3])
                visible = result[:, :, 3] > 0
                np.testing.assert_array_equal(result[visible], clean_result[visible])
                target = self.fill_mask(poisoned, operation)
                np.testing.assert_array_equal(result[~target], poisoned[~target])

    def test_legacy_default_and_false_keep_original_encoded_output(self):
        for operation in ["close_fill", "fill_holes"]:
            with self.subTest(operation=operation):
                layer = self.fixture(operation, (255, 0, 255))
                target = self.fill_mask(layer, operation)
                expected = layer.copy()
                expected[:, :, :3] = cv2.inpaint(layer[:, :, :3], target.astype(np.uint8) * 255, 5, cv2.INPAINT_TELEA)
                expected[:, :, 3][target] = 255
                encoded = io.BytesIO()
                Image.fromarray(expected).save(encoded, format="PNG")
                for mode in [None, False]:
                    result, output = self.run_refine(layer, operation, mode)
                    np.testing.assert_array_equal(result, expected)
                    self.assertEqual(output, encoded.getvalue())

    def test_invalid_alpha_mode_is_rejected(self):
        for value in ["true", 1, []]:
            with self.subTest(value=value):
                with patch.object(sys, "stderr", io.StringIO()), self.assertRaises(SystemExit) as error:
                    self.run_refine(self.fixture("close_fill", (0, 0, 0)), "close_fill", value)
                self.assertEqual(error.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
