"""CPU regressions for per-job cache options. No server, model or GPU is used."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from PIL import Image
import comfy_api


class CacheOptionsTest(unittest.TestCase):
    def setUp(self):
        self.folder = tempfile.TemporaryDirectory(prefix="nest-egg-qwen-cache-")
        self.out = Path(self.folder.name)
        self.output = patch.object(comfy_api, "OUT", self.out)
        self.output.start()
        self.server = patch.object(comfy_api.comfy_guard, "ensure_server")
        self.ensure = self.server.start()
        self.graphs = []

        def render(graph, name):
            self.graphs.append(graph)
            path = self.out / f"{name}_0.png"
            Image.new("RGB", (16, 16), (80, 100, 120)).save(path)
            return [path]

        self.renderer = patch.object(comfy_api, "run", side_effect=render)
        self.renderer.start()

    def tearDown(self):
        self.renderer.stop()
        self.server.stop()
        self.output.stop()
        self.folder.cleanup()

    def test_existing_default_job_key_and_cached_image_are_preserved(self):
        blob = json.dumps([comfy_api.QWEN_UNET, "room", 1024, 1024, 25, 7, 1024, []], ensure_ascii=False)
        old_key = hashlib.sha1(blob.encode("utf-8")).hexdigest()
        self.assertEqual(comfy_api._job_key("room", 1024, 1024, 25, 7, 1024, []), old_key)
        comfy_api.qwen("room", seed=7, prefix="default")
        metadata = json.loads((self.out / "default.job.json").read_text(encoding="utf-8"))
        self.assertEqual(metadata["key"], old_key)
        comfy_api.qwen("room", seed=7, prefix="default")
        self.assertEqual(len(self.graphs), 1)

    def test_off_cache_does_not_reuse_a_cpu_job(self):
        comfy_api.qwen("room", seed=7, prefix="same")
        comfy_api.qwen("room", seed=7, prefix="same", cache_device="off")
        self.assertEqual(len(self.graphs), 2)
        self.assertEqual(self.graphs[-1]["1c"]["inputs"]["device"], "off")
        self.assertEqual(self.graphs[-1]["5"]["inputs"]["batch_size"], 1)
        comfy_api.qwen("room", seed=7, prefix="same", cache_device="off")
        self.assertEqual(len(self.graphs), 2)

    def test_precision_is_part_of_cache_identity(self):
        comfy_api.qwen("room", seed=7, prefix="same")
        comfy_api.qwen("room", seed=7, prefix="same", cache_dtype="int8")
        self.assertEqual(len(self.graphs), 2)
        self.assertEqual(self.graphs[-1]["1c"]["inputs"]["dtype"], "int8")

    def test_reference_edit_retains_encoder_sized_latent(self):
        reference = self.out / "reference.png"
        Image.new("RGB", (32, 32), "green").save(reference)
        with patch.object(comfy_api, "upload", return_value="reference.png"):
            comfy_api.qwen("extend", seed=8, images=[reference], cache_device="off", resolution=0)
        graph = self.graphs[-1]
        self.assertNotIn("5", graph)
        self.assertEqual(graph["6"]["inputs"]["latent_image"], ["4", 2])
        self.assertEqual(graph["4"]["inputs"]["resolution"], 0)

    def test_all_reference_slots_restore_load_image_alpha(self):
        references = [self.out / "rgba.png", self.out / "rgb.png"]
        Image.new("RGBA", (32, 64), (90, 100, 120, 64)).save(references[0])
        Image.new("RGB", (64, 32), "green").save(references[1])
        with patch.object(comfy_api, "upload", side_effect=[p.name for p in references]):
            comfy_api.qwen("edit", seed=9, images=references, resolution=0)
        graph = self.graphs[-1]
        for i in range(len(references)):
            with self.subTest(slot=i):
                node_id, output = graph["4"]["inputs"][f"images.image_{i+1}"]
                self.assertEqual(output, 0)
                self.assertEqual(graph[node_id]["class_type"], "JoinImageWithAlpha")
                self.assertEqual(graph[node_id]["inputs"], {"image": [f"L{i}", 0], "alpha": [f"L{i}", 1]})

    def test_old_rgb_only_reference_job_is_not_reused(self):
        reference = self.out / "reference.png"
        Image.new("RGBA", (32, 32), (90, 100, 120, 64)).save(reference)
        refs = [hashlib.sha1(reference.read_bytes()).hexdigest()]
        old_blob = json.dumps([comfy_api.QWEN_UNET, "edit", 1024, 1024, 25, 9, 1024, refs], ensure_ascii=False)
        old_key = hashlib.sha1(old_blob.encode("utf-8")).hexdigest()
        Image.new("RGB", (16, 16), "red").save(self.out / "old_0.png")
        (self.out / "old.job.json").write_text(json.dumps({"key": old_key, "seed": 9}))
        with patch.object(comfy_api, "upload", return_value="reference.png"):
            comfy_api.qwen("edit", seed=9, images=[reference], prefix="old")
        self.assertEqual(len(self.graphs), 1)
        new_key = json.loads((self.out / "old.job.json").read_text())["key"]
        self.assertNotEqual(new_key, old_key)
        comfy_api.qwen("edit", seed=9, images=[reference], prefix="old")
        self.assertEqual(len(self.graphs), 1)

    def test_bad_option_is_rejected_before_network_or_model_load(self):
        for options in ({"cache_device": "ram"}, {"cache_dtype": "fp8"}):
            with self.subTest(options=options), self.assertRaises(ValueError):
                comfy_api.qwen("room", **options)
        self.ensure.assert_not_called()
        self.assertEqual(self.graphs, [])


if __name__ == "__main__":
    unittest.main()
