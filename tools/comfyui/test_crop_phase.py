"""Native sampling registration: legacy bytes, retained material and invalid records."""
import copy
import importlib.util
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

import cut_layers as cutter
from crop_phase import freeze_crop_phase, validate_crop_phase
from check_spec import check

ROOT = Path(__file__).resolve().parents[2]
WORK = ROOT / "art_src/characters/guest_zheng"
if os.environ.get("CUT_UNDER_TEST"):
    from importlib.machinery import SourceFileLoader
    loader = SourceFileLoader("cut_under_test", os.environ["CUT_UNDER_TEST"])
    loaded_spec = importlib.util.spec_from_loader(loader.name, loader)
    cutter = importlib.util.module_from_spec(loaded_spec)
    loader.exec_module(cutter)


class CropPhaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.spec = json.loads((WORK / "repair_candidates/wrist-v3/spec.json").read_text(encoding="utf8"))
        cls.part = copy.deepcopy(cls.spec["parts"]["hand"])
        cls.part.pop("crop_phase", None)
        cls.k = cls.spec["tex_px_per_wp"] / cls.spec["illustration_px_per_wp"]
        cls.joints = {name: np.asarray(value, float) * cls.k for name, value in cls.spec["joints"].items()}
        cls.source = Image.open(WORK / "repair_candidates/crop-phase-prototype-v3/reference-source.png").copy()
        cls.candidate = Image.open(WORK / "repair_candidates/wrist-v3/hand.png").copy()
        cls.transform = cutter.part_transform(cls.source, cls.part, cls.joints, cls.k)
        cls.phase = freeze_crop_phase(cls.transform, cls.k)
        # Frozen pre-change implementation, independent of the new optional path.
        snapshot = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs/cut_layers-before-crop-phase.py.txt"
        from importlib.machinery import SourceFileLoader
        loader = SourceFileLoader("legacy_ne267_cut_layers", str(snapshot))
        module_spec = importlib.util.spec_from_loader(loader.name, loader)
        cls.legacy = importlib.util.module_from_spec(module_spec)
        loader.exec_module(cls.legacy)

    def registered(self):
        return dict(self.part, crop_phase=copy.deepcopy(self.phase))

    def test_legacy_all_parts_pixel_and_png_bytes(self):
        import io
        for name, part in self.spec["parts"].items():
            part = {key: value for key, value in part.items() if key != "crop_phase"}
            source = Image.open(WORK / "07_refined" / f"{name}.png")
            old = self.legacy.part_transform(source, part, self.joints, self.k)
            new = cutter.part_transform(source, part, self.joints, self.k)
            for before, after in zip(old, new):
                np.testing.assert_array_equal(before, after)
            a = self.legacy.render_part(source, old, self.k)
            b = cutter.render_part(source, new, self.k)
            np.testing.assert_array_equal(a, b)
            buffers = [io.BytesIO(), io.BytesIO()]
            Image.fromarray(a).save(buffers[0], format="PNG")
            Image.fromarray(b).save(buffers[1], format="PNG")
            self.assertEqual(buffers[0].getvalue(), buffers[1].getvalue())

    def test_reference_unchanged_exact(self):
        part = self.registered()
        transform = cutter.part_transform(self.source, part, self.joints, self.k)
        actual = cutter.render_part(self.source, transform, self.k, crop_phase=part["crop_phase"])
        expected = self.legacy.render_part(self.source, self.transform, self.k)
        np.testing.assert_array_equal(actual, expected)

    def test_extension_preserves_fingers_uv_contact_and_remote_normals(self):
        part = self.registered()
        transform = cutter.part_transform(self.candidate, part, self.joints, self.k)
        after = cutter.render_part(self.candidate, transform, self.k, crop_phase=self.phase)
        before = self.legacy.render_part(self.source, self.transform, self.k)
        shift = transform[3] - self.transform[3]
        np.testing.assert_allclose(shift, [9, 0], rtol=0, atol=1e-8)
        self.assertEqual(after.shape[:2], (100, 180))
        aligned = np.zeros_like(after)
        aligned[:100, 9:180] = before
        np.testing.assert_array_equal(after[:, 69:], aligned[:, 69:])
        contact = np.array([515.5529567748308, 875.1217090189457, 1.])
        old_uv = np.linalg.inv(np.vstack((self.transform[0], [0, 0, 1]))) @ contact
        new_uv = np.linalg.inv(np.vstack((transform[0], [0, 0, 1]))) @ contact
        np.testing.assert_allclose(new_uv, old_uv + [9, 0, 0], rtol=0, atol=1e-10)
        normals_before = np.zeros_like(after)
        normals_before[:, 9:] = cutter.make_normal_map(before)
        normals_after = cutter.make_normal_map(after)
        affected = cv2.dilate(np.any(aligned != after, axis=2).astype("uint8"), np.ones((7, 7), "uint8")) > 0
        reference = np.zeros(affected.shape, bool)
        reference[:, 9:] = True
        np.testing.assert_array_equal(normals_after[reference & ~affected], normals_before[reference & ~affected])

    def test_malformed_fields(self):
        bad_values = {"origin": [None, [False, 0], [float("nan"), 0], [10 ** 1000, 0], [0]],
                      "size": [[True, 2], [0, 2], [1.5, 2], [2]],
                      "affine": [[], [[1, 0, 0], [0, float("inf"), 0]]],
                      "k": [False, 0, 2, float("nan")]}
        for key, values in bad_values.items():
            for value in values:
                with self.subTest(key=key, value=value):
                    record = dict(self.phase, **{key: value})
                    with self.assertRaisesRegex(ValueError, "spec.parts.hand.crop_phase." + key):
                        validate_crop_phase(record, self.part, self.joints, self.k, "spec.parts.hand.crop_phase")

    def test_wrong_origin_affine_and_joint_frame_rejected(self):
        for field in ("origin", "affine", "joint"):
            record, joints = copy.deepcopy(self.phase), copy.deepcopy(self.joints)
            if field == "origin":
                record["origin"][0] += .01
            elif field == "affine":
                record["affine"][0][2] += .01
            else:
                joints[self.part["from"]][0] += 1
            with self.assertRaisesRegex(ValueError, "crop_phase.affine"):
                validate_crop_phase(record, self.part, joints, self.k)

    def test_oversized_footprint_rejected_before_render(self):
        part = self.registered()
        part["crop_phase"]["size"] = [100000, 2]
        with self.assertRaisesRegex(ValueError, "crop_phase.size"):
            cutter.part_transform(self.source, part, self.joints, self.k)

    def test_check_spec_reports_part_field_before_slow_steps(self):
        recipe = json.loads((ROOT / "tools/comfyui/recipes/guest_zheng.json").read_text(encoding="utf8"))
        spec = copy.deepcopy(self.spec)
        spec["parts"]["hand"]["crop_phase"] = dict(self.phase, k=False)
        errors, _ = check(recipe, spec, False)
        self.assertTrue(any("spec.parts.hand.crop_phase.k" in error for error in errors), errors)

    def test_main_rejects_before_temporary_publication(self):
        with tempfile.TemporaryDirectory(prefix="crop-phase-invalid-") as temporary:
            folder = Path(temporary)
            (folder / "07_refined").mkdir()
            self.source.save(folder / "07_refined/hand.png")
            spec = copy.deepcopy(self.spec)
            spec.pop("eye_states", None)
            spec["parts"] = {"hand": self.registered()}
            spec["parts"]["hand"]["crop_phase"]["origin"][0] += .25
            spec_path = folder / "spec.json"
            spec_path.write_text(json.dumps(spec), encoding="utf8")
            command = ["cut_layers.py", "--spec", str(spec_path), "--work", str(folder),
                       "--char", str(folder / "character"), "--rig", str(folder / "rig.json")]
            with patch.object(sys, "argv", command):
                with self.assertRaisesRegex(ValueError, "spec.parts.hand.crop_phase.affine"):
                    cutter.main()
            self.assertFalse((folder / "character/parts.tmp").exists())


if __name__ == "__main__":
    unittest.main()
