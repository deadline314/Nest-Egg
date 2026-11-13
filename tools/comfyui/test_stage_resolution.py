"""CPU stage-canvas contract; mocked model output, actual parts/publication code."""
import contextlib
import io
import json
import importlib.util
from importlib.machinery import SourceFileLoader
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from PIL import Image
import comfy_api
import make_parts

if os.environ.get("PARTS_UNDER_TEST"):
    source = os.environ["PARTS_UNDER_TEST"]
    frozen = importlib.util.spec_from_loader("frozen_stage_parts", SourceFileLoader("frozen_stage_parts", source))
    make_parts = importlib.util.module_from_spec(frozen)
    frozen.loader.exec_module(make_parts)


class StageResolutionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="native-stage-")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        Image.new("RGBA", (32, 64), (30, 60, 90, 251)).save(self.work / "base_rgba.png")
        self.generated = self.work / "model-output.png"
        self.spec = {"id": "stage-fixture", "seam": 0, "joints": {"a": [16, 20], "b": [16, 40]},
                     "groups": {"body": {"sam": [], "rest": True}},
                     "parts": {"body": {"group": "body", "from": "a", "to": "b", "mode": "upright"}},
                     "stages": [{"name": "P", "prompt": "known test underlayer", "resolution": 0}]}

    def run_parts(self):
        spec = self.work / "spec.json"
        spec.write_text(json.dumps(self.spec), encoding="utf-8")
        with patch.object(sys, "argv", ["parts", "--spec", str(spec), "--work", str(self.work)]), \
                patch.object(make_parts, "segment", side_effect=AssertionError("must not run SAM")), \
                patch.object(make_parts, "segment_points", side_effect=AssertionError("must not run SAM")), \
                patch.object(comfy_api, "qwen", return_value=[self.generated]) as model, \
                contextlib.redirect_stdout(io.StringIO()):
            make_parts.main()
        return model

    def test_native_stage_keeps_original_png_bytes_without_resampling(self):
        Image.new("RGBA", (32, 64), (51, 75, 113, 249)).save(self.generated)
        model = self.run_parts()
        self.assertEqual(model.call_args.kwargs["resolution"], 0)
        self.assertEqual((self.work / "04_stages/P.png").read_bytes(), self.generated.read_bytes())

    def test_wrong_native_size_or_mode_cannot_publish_or_replace_parts(self):
        for mode, size in (("RGBA", (16, 32)), ("RGB", (32, 64))):
            with self.subTest(mode=mode, size=size):
                Image.new(mode, size, "blue").save(self.generated)
                part = self.work / "06_parts/body.png"
                part.parent.mkdir(exist_ok=True)
                part.write_bytes(b"previous accepted part")
                with self.assertRaisesRegex(ValueError, "native output"):
                    self.run_parts()
                self.assertEqual(part.read_bytes(), b"previous accepted part")
                self.assertFalse((self.work / "04_stages/P.png").exists())

    def test_existing_recipe_default_retains_previous_canvas_registration(self):
        del self.spec["stages"][0]["resolution"]
        Image.new("RGBA", (16, 32), "blue").save(self.generated)
        model = self.run_parts()
        self.assertEqual(model.call_args.kwargs["resolution"], 1024)
        with Image.open(self.work / "04_stages/P.png") as image:
            self.assertEqual(image.size, (32, 64))


if __name__ == "__main__":
    unittest.main()
