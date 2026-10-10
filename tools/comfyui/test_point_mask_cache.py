import contextlib
import io
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import numpy as np
from PIL import Image


import make_parts


class PointMaskCacheMainTests(unittest.TestCase):
    """Exercise the real make_parts.main cache reads/writes with fake SAM outputs."""

    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(prefix="point-mask-cache-")
        self.root = Path(self.temp.name)
        self.work = self.root / "work"
        (self.work / "sam").mkdir(parents=True)
        rgba = np.zeros((12, 12, 4), dtype=np.uint8)
        rgba[1:11, 1:11] = (55, 80, 120, 255)
        Image.fromarray(rgba, "RGBA").save(self.work / "base_rgba.png")
        self.spec_path = self.root / "spec.json"
        self.spec = {
            "id": "point-mask-cache-fixture",
            "groups": {"body": {"sam": ["body"]}},
            "parts": {"body": {"group": "body"}, "near_leg": {"group": "near_leg"}},
            "joints": {"hip": [6, 3]},
            "near_leg": {
                "pos": [[5, 5]],
                "neg": [[8, 8]],
                "threshold": 0.3,
                "close": 0,
                "fill_grow": 0,
                "cover": [{"pos": [[4, 4]], "neg": [[9, 9]]}],
            },
            "seam": 0,
        }
        self._save_spec()
        self.point_calls: list[dict] = []

    def tearDown(self) -> None:
        self.temp.cleanup()

    def _save_spec(self) -> None:
        self.spec_path.write_text(json.dumps(self.spec), encoding="utf8")

    def _record_text_masks(self, _image: str, prompts: list[str], out_dir: str,
                           threshold: float = 0.4, refine: int = 2) -> dict[str, Path]:
        out = Path(out_dir)
        out.mkdir(parents=True, exist_ok=True)
        result = {}
        for prompt in prompts:
            path = out / f"{make_parts.slug(prompt)}.png"
            Image.new("L", (12, 12), 255).save(path)
            result[prompt] = path
        return result

    def _record_point_masks(self, image: str, out_dir: str, jobs: dict,
                            threshold: float = 0.3, refine: int = 2) -> dict[str, Path]:
        out = Path(out_dir)
        out.mkdir(parents=True, exist_ok=True)
        result = {}
        for name, points in jobs.items():
            self.point_calls.append({
                "name": name,
                "image": Path(image).read_bytes(),
                "pos": points.get("pos", []),
                "neg": points.get("neg", []),
                "threshold": threshold,
                "refine": refine,
            })
            path = out / f"{name}.png"
            Image.new("L", (12, 12), 255).save(path)
            result[name] = path
        return result

    def _run_main(self) -> None:
        argv = ["make_parts", "--spec", str(self.spec_path), "--work", str(self.work), "--no-complete"]
        with patch.object(sys, "argv", argv), \
             patch.object(make_parts, "segment", side_effect=self._record_text_masks), \
             patch.object(make_parts, "segment_points", side_effect=self._record_point_masks), \
             contextlib.redirect_stdout(io.StringIO()):
            make_parts.main()

    def _prime(self) -> None:
        self._run_main()
        self.assertEqual({c["name"] for c in self.point_calls}, {
            "near_leg", "near_leg_far", "near_leg_cover0"
        })
        self.point_calls.clear()

    def _called(self, *names: str) -> set[str]:
        return {c["name"] for c in self.point_calls if c["name"] in names}

    def test_unchanged_near_far_cover_inputs_hit_cache(self) -> None:
        self._prime()
        self._run_main()
        self.assertEqual(self.point_calls, [])

    def test_same_size_source_edit_invalidates_near_far_and_cover(self) -> None:
        self._prime()
        with Image.open(self.work / "base_rgba.png") as image:
            rgba = np.array(image.convert("RGBA"))
        rgba[2, 2] = (255, 0, 0, 255)
        Image.fromarray(rgba, "RGBA").save(self.work / "base_rgba.png")
        self._run_main()
        self.assertEqual(self._called("near_leg", "near_leg_far", "near_leg_cover0"), {
            "near_leg", "near_leg_far", "near_leg_cover0"
        })

    def test_near_leg_positive_points_invalidate_near_and_far(self) -> None:
        self._prime()
        self.spec["near_leg"]["pos"] = [[4, 5]]
        self._save_spec()
        self._run_main()
        self.assertEqual(self._called("near_leg", "near_leg_far"), {"near_leg", "near_leg_far"})
        self.assertNotIn("near_leg_cover0", self._called("near_leg_cover0"))

    def test_near_leg_negative_points_invalidate_near_and_far(self) -> None:
        self._prime()
        self.spec["near_leg"]["neg"] = [[8, 7]]
        self._save_spec()
        self._run_main()
        self.assertEqual(self._called("near_leg", "near_leg_far"), {"near_leg", "near_leg_far"})
        self.assertNotIn("near_leg_cover0", self._called("near_leg_cover0"))

    def test_cover_positive_points_invalidate_cover(self) -> None:
        self._prime()
        self.spec["near_leg"]["cover"][0]["pos"] = [[3, 4]]
        self._save_spec()
        self._run_main()
        self.assertIn("near_leg_cover0", self._called("near_leg_cover0"))

    def test_cover_negative_points_invalidate_cover(self) -> None:
        self._prime()
        self.spec["near_leg"]["cover"][0]["neg"] = [[10, 9]]
        self._save_spec()
        self._run_main()
        self.assertIn("near_leg_cover0", self._called("near_leg_cover0"))

    def test_threshold_invalidates_near_far_and_cover(self) -> None:
        self._prime()
        self.spec["near_leg"]["threshold"] = 0.42
        self._save_spec()
        self._run_main()
        self.assertEqual(self._called("near_leg", "near_leg_far", "near_leg_cover0"), {
            "near_leg", "near_leg_far", "near_leg_cover0"
        })

    def test_model_name_in_key_invalidates_masks(self) -> None:
        self._prime()
        original = make_parts.SAM_CKPT
        with patch.object(make_parts, "SAM_CKPT", "test-model-name.safetensors"):
            self._run_main()
        self.assertEqual(self._called("near_leg", "near_leg_far", "near_leg_cover0"), {
            "near_leg", "near_leg_far", "near_leg_cover0"
        })
        self.assertEqual(make_parts.SAM_CKPT, original)

    def test_refine_value_in_key_matches_point_segmentation_calls(self) -> None:
        self._prime()
        old_refine = getattr(make_parts, "POINT_MASK_REFINE", 2)
        with patch.object(make_parts, "POINT_MASK_REFINE", old_refine + 1, create=True):
            self._run_main()
        self.assertEqual(self._called("near_leg", "near_leg_far", "near_leg_cover0"), {
            "near_leg", "near_leg_far", "near_leg_cover0"
        })
        self.assertTrue(all(c["refine"] == old_refine + 1 for c in self.point_calls))

    def test_missing_mask_regenerates_even_when_key_file_exists(self) -> None:
        self._prime()
        for name in ("near_leg", "near_leg_far", "near_leg_cover0"):
            (self.work / "sam" / f"{name}.png").unlink()
        self._run_main()
        self.assertEqual(self._called("near_leg", "near_leg_far", "near_leg_cover0"), {
            "near_leg", "near_leg_far", "near_leg_cover0"
        })


if __name__ == "__main__":
    unittest.main()
