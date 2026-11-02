"""Exercise real offline cuts, cached underlayers and texture export; no model/server/GPU.

    python tools/comfyui/test_source_alpha.py

PARTS_UNDER_TEST may point to a frozen earlier make_parts.py for a negative control.
"""
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

import numpy as np
import cv2
from PIL import Image

import comfy_api
import cut_layers
import make_parts
from check_spec import check

if os.environ.get("PARTS_UNDER_TEST"):
    frozen = importlib.util.spec_from_file_location("frozen_parts", os.environ["PARTS_UNDER_TEST"])
    make_parts = importlib.util.module_from_spec(frozen)
    frozen.loader.exec_module(make_parts)


class SourceAlphaTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="source-alpha-")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.source = np.zeros((64, 64, 4), np.uint8)
        self.source[4:60, 4:60] = (35, 75, 110, 253)
        # One connected silhouette, including faint hair AA and nonopaque interior.
        self.source[4:60, 4, 3] = np.resize([1, 16, 40, 64, 127, 128, 200, 254], 56)
        self.source[4, 4:60, 3] = 40
        Image.fromarray(self.source).save(self.work / "base_rgba.png")
        self.spec = {
            "id": "coverage-fixture", "preserve_source_alpha": True, "seam": 0,
            "joints": {"a": [32, 32], "b": [32, 40]},
            "groups": {"body": {"sam": [], "rest": True}},
            "parts": {"body": {"group": "body", "from": "a", "to": "b", "mode": "upright"}},
        }

    def run_parts(self, *extra):
        spec = self.work / "spec.json"
        spec.write_text(json.dumps(self.spec), encoding="utf8")
        with patch.object(sys, "argv", ["parts", "--spec", str(spec), "--work", str(self.work), *extra]), \
                patch.object(make_parts, "segment", side_effect=AssertionError("unexpected SAM text job")), \
                patch.object(make_parts, "segment_points", side_effect=AssertionError("unexpected SAM point job")), \
                patch.object(comfy_api, "qwen", side_effect=AssertionError("unexpected generation job")), \
                contextlib.redirect_stdout(io.StringIO()):
            make_parts.main()

    def part(self, name="body"):
        with Image.open(self.work / "06_parts" / f"{name}.png") as image:
            return np.array(image.convert("RGBA"))

    def stage_fixture(self):
        stage = self.source.copy()
        stage[4:60, 4:60] = (90, 65, 30, 251)
        (self.work / "04_stages").mkdir(exist_ok=True)
        Image.fromarray(stage).save(self.work / "04_stages/P.png")
        self.spec["stages"] = [{"name": "P", "prompt": "frozen test underlayer"}]
        self.spec["groups"] = {
            "arm": {"sam": [], "outline": [[32, 0], [63, 0], [63, 63], [32, 63]]},
            "body": {"sam": [], "rest": True, "rest_gap": 0, "complete": {
                "stage": "P", "stage_silhouette": True, "occluders": ["arm"],
                "edge_trim": 0, "near": 100, "gap_grow": 0,
            }},
        }
        self.spec["parts"]["arm"] = {**self.spec["parts"]["body"], "group": "arm"}
        return stage

    def test_visible_rgba_and_native_texture_alpha(self):
        before = (self.work / "base_rgba.png").read_bytes()
        self.run_parts()
        actual = self.part()
        np.testing.assert_array_equal(actual, self.source)
        self.assertEqual(before, (self.work / "base_rgba.png").read_bytes())
        source = Image.fromarray(actual)
        joints = {key: np.array(value) for key, value in self.spec["joints"].items()}
        transform = cut_layers.part_transform(source, self.spec["parts"]["body"], joints, 1.0)
        rendered = cut_layers.render_part(source, transform, 1.0)
        # This integer upright transform only translates; compare the entire alpha canvas.
        restored = cv2.warpAffine(rendered[:, :, 3], transform[0], (64, 64), flags=cv2.INTER_NEAREST)
        np.testing.assert_array_equal(restored, self.source[:, :, 3])
        normal = cut_layers.make_normal_map(rendered)
        np.testing.assert_array_equal(normal[:, :, 3], rendered[:, :, 3])

    def test_default_and_explicit_false_keep_legacy_binary_output(self):
        del self.spec["preserve_source_alpha"]
        self.run_parts()
        old = (self.work / "06_parts/body.png").read_bytes()
        expected = np.where(self.source[:, :, 3] > 127, 255, 0)
        np.testing.assert_array_equal(self.part()[:, :, 3], expected)
        self.spec["preserve_source_alpha"] = False
        self.run_parts()
        self.assertEqual(old, (self.work / "06_parts/body.png").read_bytes())

    def test_joint_caps_multiply_coverage(self):
        self.spec["parts"]["body"].update(y=[0, 24], caps=[{"joint": "a", "radius": 14, "feather": 6}])
        self.run_parts()
        actual = self.part()[:, :, 3]
        self.assertEqual(int(actual[20, 20]), 253)
        self.assertGreater(int(actual[32, 43]), 0)
        self.assertLess(int(actual[32, 43]), 253)
        self.assertEqual(int(actual[50, 50]), 0)

    def test_stage_uses_original_and_underlayer_coverage_separately(self):
        stage = self.stage_fixture()
        self.run_parts()
        actual = self.part()
        np.testing.assert_array_equal(actual[20, 16], self.source[20, 16])
        np.testing.assert_array_equal(actual[20, 40], stage[20, 40])
        np.testing.assert_array_equal(self.part("arm")[20, 40], self.source[20, 40])
        first = (self.work / "06_parts/body.png").read_bytes()
        self.run_parts()
        self.assertEqual(first, (self.work / "06_parts/body.png").read_bytes())
        self.run_parts("--no-complete")
        self.assertEqual(int(self.part()[20, 40, 3]), 0)
        np.testing.assert_array_equal(self.part()[20, 16], self.source[20, 16])

    def test_same_size_source_and_stage_edits_invalidate_completion(self):
        stage = self.stage_fixture()
        self.run_parts()
        self.source[20, 16] = (10, 20, 30, 200)
        Image.fromarray(self.source).save(self.work / "base_rgba.png")
        self.run_parts()
        np.testing.assert_array_equal(self.part()[20, 16], self.source[20, 16])
        stage[20, 40] = (70, 30, 20, 252)
        Image.fromarray(stage).save(self.work / "04_stages/P.png")
        self.run_parts()
        np.testing.assert_array_equal(self.part()[20, 40], stage[20, 40])

    def test_legacy_and_unkeyed_completions_are_not_reused(self):
        stage = self.stage_fixture()
        self.spec["preserve_source_alpha"] = False
        self.run_parts()
        self.assertEqual(int(self.part()[20, 16, 3]), 255)
        self.spec["preserve_source_alpha"] = True
        self.run_parts()
        np.testing.assert_array_equal(self.part()[20, 16], self.source[20, 16])
        (self.work / "05_groups/body.key").unlink()
        Image.new("RGBA", (64, 64), (255, 0, 255, 255)).save(self.work / "05_groups/body.png")
        self.run_parts()
        np.testing.assert_array_equal(self.part()[20, 40], stage[20, 40])

    def test_invalid_option_fails_before_any_output(self):
        for value in [1, 0, "true", None, {}, []]:
            self.spec["preserve_source_alpha"] = value
            with self.subTest(value=value), contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit) as raised:
                    self.run_parts()
                self.assertEqual(raised.exception.code, 2)
            self.assertFalse((self.work / "06_parts").exists())

    def test_selective_export_keeps_unrelated_part_bytes(self):
        self.stage_fixture()
        self.run_parts()
        body = (self.work / "06_parts/body.png").read_bytes()
        self.source[20, 40] = (40, 60, 80, 128)
        Image.fromarray(self.source).save(self.work / "base_rgba.png")
        self.run_parts("--only", "arm")
        self.assertEqual(body, (self.work / "06_parts/body.png").read_bytes())
        np.testing.assert_array_equal(self.part("arm")[20, 40], self.source[20, 40])

    def test_near_leg_retains_selected_material_alpha(self):
        self.spec["joints"]["hip"] = [32, 16]
        self.spec["near_leg"] = {"pos": [[32, 32]], "close": 0, "fill_grow": 0, "cover_limbs": False}
        self.spec["parts"]["leg"] = {**self.spec["parts"]["body"], "group": "near_leg"}

        def selected(_image, out_dir, jobs, **_kwargs):
            out = Path(out_dir)
            out.mkdir(parents=True, exist_ok=True)
            for name in jobs:
                Image.new("L", (64, 64), 255).save(out / f"{name}.png")

        # The fixture pins a synthetic segmentation result; production alpha composition is real.
        with patch.object(make_parts, "ensure_point_masks", return_value={}):
            spec = self.work / "spec.json"
            spec.write_text(json.dumps(self.spec), encoding="utf8")
            with patch.object(sys, "argv", ["parts", "--spec", str(spec), "--work", str(self.work)]), \
                    patch.object(make_parts, "segment_points", side_effect=selected), \
                    patch.object(comfy_api, "qwen", side_effect=AssertionError("unexpected model job")), \
                    contextlib.redirect_stdout(io.StringIO()):
                make_parts.main()
        np.testing.assert_array_equal(self.part("leg"), self.source)

    def test_generated_crop_preserves_visible_pixels_and_completion_alpha(self):
        self.stage_fixture()
        del self.spec["stages"]
        self.spec["groups"]["body"]["complete"] = {
            "occluders": ["arm"], "what": "cloth", "hidden_by": "sleeve", "near": 100,
        }
        generated = self.source.copy()
        generated[4:60, 4:60] = (110, 50, 30, 199)
        candidate = self.work / "fake_generated.png"
        Image.fromarray(generated).save(candidate)
        spec = self.work / "spec.json"
        spec.write_text(json.dumps(self.spec), encoding="utf8")
        with patch.object(sys, "argv", ["parts", "--spec", str(spec), "--work", str(self.work)]), \
                patch.object(comfy_api, "qwen", return_value=[candidate]) as provider, \
                contextlib.redirect_stdout(io.StringIO()):
            make_parts.main()
        self.assertEqual(provider.call_count, 1)
        np.testing.assert_array_equal(self.part()[20, 16], self.source[20, 16])
        completed = self.part()[20, 40].copy()
        self.assertEqual(int(completed[3]), 199)
        self.spec["preserve_source_alpha"] = False
        spec.write_text(json.dumps(self.spec), encoding="utf8")
        with patch.object(sys, "argv", ["parts", "--spec", str(spec), "--work", str(self.work)]), \
                patch.object(comfy_api, "qwen", return_value=[candidate]), \
                contextlib.redirect_stdout(io.StringIO()):
            make_parts.main()
        # Preserve the existing premultiplied resize/uint8 color conversion, including its quantization.
        np.testing.assert_array_equal(completed[:3], self.part()[20, 40, :3])
        self.assertEqual(int(self.part()[20, 40, 3]), 255)

    def test_source_alpha_schema_validation(self):
        root = Path(__file__).resolve().parents[2]
        spec = json.loads((root / "tools/comfyui/specs/resident_side.json").read_text())
        recipe = {"id": spec["id"], "spec": "unused", "rig": "unused", "work": "unused", "design": {}}
        spec["preserve_source_alpha"] = "true"
        errors, _ = check(recipe, spec, True)
        self.assertTrue(any("spec.preserve_source_alpha" in error for error in errors))
        spec["preserve_source_alpha"] = True
        errors, _ = check(recipe, spec, True)
        self.assertFalse(any("spec.preserve_source_alpha" in error for error in errors))


if __name__ == "__main__":
    unittest.main(verbosity=2)
