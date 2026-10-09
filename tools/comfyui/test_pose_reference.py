"""Verify posed UV sampling and reject bad reference data before publication."""
import copy
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np

from cut_parts import mesh_warp, validate_reference, require_single_instance, main


class PoseReferenceTest(unittest.TestCase):
    def setUp(self):
        self.part = {"name": "leg", "kind": "mesh",
                     "tex_size": [8, 8],
                     "uv": [[0, 0], [7, 0], [7, 7], [0, 7]],
                     "vertices": [[2, 2], [9, 2], [11, 9], [2, 9]],
                     "triangles": [[0, 1, 2], [0, 2, 3]]}

    def test_non_affine_texture_samples_and_inverse(self):
        yy, xx = np.mgrid[:8, :8]
        image = np.stack((xx * 20, yy * 20, xx * 0 + 255), axis=-1).astype(np.uint8)
        bent = mesh_warp(image, self.part, (14, 12))
        for uv, vertex in zip(self.part["uv"], self.part["vertices"]):
            self.assertTrue(np.array_equal(bent[vertex[1], vertex[0]], image[uv[1], uv[0]]))
        self.assertTrue(np.array_equal(bent[0, 0], [0, 0, 0]))
        back = mesh_warp(bent, self.part, (8, 8), inverse=True)
        self.assertTrue(np.array_equal(back[0, 0], image[0, 0]))
        self.assertTrue(np.array_equal(back[7, 7], image[7, 7]))
        # Interior samples survive the forward/inverse map without a second bend.
        self.assertLessEqual(np.abs(back[1:7, 1:7, :2].astype(int) - image[1:7, 1:7, :2]).max(), 1)
        shifted = mesh_warp(image, self.part, (16, 14), shift=(2, 2))
        self.assertTrue(np.array_equal(shifted[4:12, 4:14], bent[2:10, 2:12]))

    def test_invalid_bindings_are_rejected(self):
        for key, value in [("vertices", [[float("nan"), 0]] * 4), ("uv", [[0, 0]] * 4),
                           ("uv", [[0, 0]]), ("triangles", [[0, 1, 9]]),
                           ("triangles", [[0, 1.5, 2]]), ("triangles", [[0, 1, 1]])]:
            part = copy.deepcopy(self.part)
            part[key] = value
            with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                validate_reference({"parts": [part]})

    def test_second_pass_validation_precedes_all_output(self):
        with tempfile.TemporaryDirectory() as temp:
            work = Path(temp)
            (work / "body.json").write_text(json.dumps({"parts": [{"name": "torso", "kind": "sprite", "tex_size": [8, 8], "xform": [1, 0, 0, 1, 0, 0]}]}))
            broken = copy.deepcopy(self.part)
            broken["triangles"] = [[0, 1, 99]]
            (work / "armor.json").write_text(json.dumps({"parts": [broken]}))
            out = work / "output"
            out.mkdir()
            sentinel = out / "previous.png"
            sentinel.write_bytes(b"unchanged")
            args = ["cut_parts", "--ref", str(work), "--out", str(out), "--char", "unused",
                    "--orig", "unused", "--body", "unused", "--armor", "unused"]
            with patch("sys.argv", args), self.assertRaises(ValueError):
                main()
            self.assertEqual(sentinel.read_bytes(), b"unchanged")
            self.assertEqual(list(out.iterdir()), [sentinel])

    def test_two_sides_cannot_overwrite_one_texture(self):
        near = dict(self.part, name="leg_front", texture="leg")
        far = dict(self.part, name="leg_back", texture="leg")
        with self.assertRaisesRegex(ValueError, "leg_front and leg_back"):
            require_single_instance({"parts": [near, far]}, {"leg"})
        require_single_instance({"parts": [near, far]}, {"torso"})
        require_single_instance({"parts": [near, dict(far, texture="leg_far")]}, {"leg", "leg_far"})

    def test_legacy_rigid_reference_and_invalid_transforms(self):
        sprite = {"name": "head", "tex_size": [8, 8], "xform": [1, 0, 0, 1, 2, 3]}
        validate_reference({"parts": [sprite]})
        for key, value in [("xform", [1, 0, 0, 0, 2, 3]), ("xform", [1, 0, 0, 1, float("nan"), 3]),
                           ("xform", [1, 0]), ("kind", "unknown"), ("tex_size", [0, 8])]:
            with self.subTest(key=key), self.assertRaises(ValueError):
                validate_reference({"parts": [dict(sprite, **{key: value})]})


if __name__ == "__main__":
    unittest.main()
