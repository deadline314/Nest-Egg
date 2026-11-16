"""Model lifetime checks without loading a GPU model."""
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch
import weakref

import numpy as np
from PIL import Image


class PoseKeypointsTests(unittest.TestCase):
    def run_prediction(self, prediction):
        events, references = [], []

        class Model:
            def __init__(self):
                self.cycle = self

            def __del__(self):
                events.append("released")

        def load(_name):
            model = Model()
            references.append(weakref.ref(model))
            return types.SimpleNamespace(args=[model])

        management = types.ModuleType("comfy.model_management")
        management.unload_all_models = lambda: events.append("unloaded")
        comfy = types.ModuleType("comfy")
        comfy.model_management = management
        nodes = types.ModuleType("comfy_extras.nodes_sam3d_body")
        nodes.SAM3DBody_Loader = types.SimpleNamespace(execute=load)
        nodes.SAM3DBody_Predict = types.SimpleNamespace(execute=prediction)
        extras = types.ModuleType("comfy_extras")
        extras.nodes_sam3d_body = nodes
        torch = types.ModuleType("torch")
        torch.from_numpy = lambda value: value
        torch.set_grad_enabled = lambda _enabled: None
        modules = {"torch": torch, "comfy": comfy, "comfy.model_management": management,
                   "comfy_extras": extras, "comfy_extras.nodes_sam3d_body": nodes}
        spec = importlib.util.spec_from_file_location("pose_keypoints", Path(__file__).with_name("pose_keypoints.py"))
        tool = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(tool)
        with tempfile.TemporaryDirectory() as directory:
            source, output = Path(directory) / "source.png", Path(directory) / "points.json"
            Image.new("RGB", (12, 16)).save(source)
            with patch.dict(sys.modules, modules), patch.object(sys, "path", list(sys.path)), patch.object(
                    sys, "argv", ["pose_keypoints", "--image", str(source), "--out", str(output)]):
                try:
                    tool.main()
                except BaseException as error:
                    traceback = error.__traceback__
                    while traceback is not None:
                        if traceback.tb_frame.f_code is tool.main.__code__:
                            self.assertIsNone(traceback.tb_frame.f_locals.get("model"))
                        traceback = traceback.tb_next
                    raise
                finally:
                    self.assertEqual(events[:1], ["unloaded"])
            self.assertEqual(events, ["unloaded", "released"])
            self.assertTrue(all(reference() is None for reference in references))
            return json.loads(output.read_text(encoding="utf-8"))

    def test_success_keeps_points_and_releases_model(self):
        result = self.run_prediction(lambda *_args, **_kwargs: types.SimpleNamespace(
            args=[{"frames": [[{"pred_keypoints_2d": np.array([[2.3, 4.5]])}]]}]))
        self.assertEqual(result, {"image_size": [12, 16], "points": {"nose": [2.3, 4.5]}})

    def test_no_person_still_releases_model(self):
        with self.assertRaisesRegex(SystemExit, "found nobody"):
            self.run_prediction(lambda *_args, **_kwargs: types.SimpleNamespace(args=[{"frames": [[]]}]))

    def test_prediction_error_still_releases_model(self):
        def reject(*_args, **_kwargs):
            raise RuntimeError("prediction failed")
        with self.assertRaisesRegex(RuntimeError, "prediction failed"):
            self.run_prediction(reject)


if __name__ == "__main__":
    unittest.main()
