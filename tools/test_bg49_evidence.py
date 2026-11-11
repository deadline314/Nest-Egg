"""Known-answer float ROI checks and proof that the default sampler is unchanged."""
from pathlib import Path
import copy
import hashlib
import json
import re
import tempfile
import unittest

import numpy as np
from PIL import Image
import verify_bg49_held as verify

ROOT = Path(__file__).resolve().parents[1]


class EvidenceChecks(unittest.TestCase):
    def test_default_sampler_changes_only_by_noop_observer(self):
        source = (ROOT / "tools/readability_check.gd").read_text(encoding="utf-8")
        stripped, count = re.subn(r"\n\n\n## Opt-in observer.*?func _record_probe_sample\([^\n]*\) -> void:\n\tpass", "", source, count=1, flags=re.S)
        self.assertEqual(count, 1)
        stripped, count = re.subn(r"\n\n\n## Presentation-only fixture preparation;.*?func _prepare_probe_level\([^\n]*\) -> void:\n\tpass", "", stripped, count=1, flags=re.S)
        self.assertEqual(count, 1)
        preparation = "\t_prepare_probe_level(data)\n"
        self.assertEqual(stripped.count(preparation), 1)
        stripped = stripped.replace(preparation, "", 1)
        call = "\t\t\t_record_probe_sample(probe, level, spot, sample, foe, [player_contrast, edge_contrast, enemy_contrast])\n"
        self.assertEqual(stripped.count(call), 1)
        stripped = stripped.replace(call, "", 1)
        # Exact published 6f061e39 blob, also checked against the untouched
        # local pre-hook byte snapshot. Only the no-op method/call are removed.
        self.assertEqual(hashlib.sha256(stripped.encode()).hexdigest(), "b677c123ff80b77293a377bff5d009a66d913aedda5cf065d8ace48fc6f1b77d")

    def fixture(self, folder):
        # Hand-derived identity mapping with bottom clipping: body=18*54,
        # outer=58*88; its ring contains exactly 144 brighter ground pixels.
        rgb = np.full((100, 100, 3), .125, dtype="<f2")
        rgb[32:86, 23:41] = .5
        rgb[90:93, 8:56] = .75
        raw = rgb[12:100, 3:61].tobytes()
        (folder / "player.bin").write_bytes(raw)
        ring_count = 58 * 88 - 18 * 54
        outside = (.125 * (ring_count - 144) + .75 * 144) / ring_count
        player_value = (.5 - outside) / (outside + .02)
        edge_value = (.75 - .125) / (.125 + .02)
        cumulative = dict(player=0.0, edge=0.0, enemy=0.0)
        samples = []
        for n in range(16):
            cumulative["player"] += player_value / 16
            cumulative["edge"] += edge_value / 16
            samples.append(dict(level="synthetic", spot="known answer", column=2, sample=n,
                                source_size=[100, 100], density=1, canvas_transform_values=[1, 0, 0, 1, 0, 0],
                                viewport_final_transform_values=[1, 0, 0, 1, 0, 0],
                                player=dict(feet=[32, 90], on_floor=True, body=[23, 32, 18, 54], outer=[3, 12, 58, 88],
                                            space_valid=True, support=dict(found=True, gap=0, normal=[0, -1]), facing=1, aim=[1, 0],
                                            edge=[8, 90, 48, 3], below=[8, 98, 48, 2],
                                            roi=dict(raw="player.bin", sha256=hashlib.sha256(raw).hexdigest(),
                                                     format=14, source_rect=[3, 12, 58, 88], width=58, height=88)),
                                enemy=None, cumulative_original=copy.deepcopy(cumulative), visible_world_prompts=[]))
        report = dict(samples_per_spot=16, sample_interval=.2, thresholds=dict(player=.6, edge=1.0, enemy=.45),
                      brightness=.5, viewport=[100, 100], pure_world=dict(bloom_active=True, world_prompt_process_disabled=True),
                      native_float_rois=dict(file="roi-samples.json", failed=False, same_original_probe_input=True, samples=16),
                      results=[dict(level="synthetic", spot="known answer", column=2, sampling_valid=True, passed=True,
                                    player_contrast=player_value, edge_contrast=edge_value, enemy_contrast=None,
                                    screenshot="synthetic.png", capture_size=[100, 100])])
        Image.new("RGB", (100, 100)).save(folder / "synthetic.png")
        (folder / "readability-report.json").write_bytes(json.dumps(report).encode())
        payload = dict(samples_per_spot=16, sample_interval=.2, records=samples)
        (folder / "roi-samples.json").write_bytes(json.dumps(payload).encode())
        return payload

    def run_fixture(self, mutation=None):
        with tempfile.TemporaryDirectory(prefix="bg49-roi-") as temporary:
            folder = Path(temporary).resolve()
            self.assertEqual(folder.parent, Path(tempfile.gettempdir()).resolve())
            payload = self.fixture(folder)
            if mutation:
                mutation(folder, payload)
                (folder / "roi-samples.json").write_bytes(json.dumps(payload).encode())
                with self.assertRaises(AssertionError): verify.verify_world(folder)
            else:
                result = verify.verify_world(folder)
                self.assertEqual(result["points"], 1)
                self.assertEqual(result["native_float_samples"], 16)

    def test_known_clipped_roi_and_original_sixteen_means(self):
        self.run_fixture()

    def test_corrupt_cumulative_is_rejected(self):
        self.run_fixture(lambda folder, p: p["records"][7]["cumulative_original"].update(player=100))

    def test_corrupt_geometry_is_rejected(self):
        self.run_fixture(lambda folder, p: p["records"][3]["player"].update(body=[24, 32, 18, 54]))

    def test_duplicate_sample_is_rejected(self):
        self.run_fixture(lambda folder, p: p["records"][3].update(sample=2))

    def test_prompt_contamination_is_rejected(self):
        self.run_fixture(lambda folder, p: p["records"][3].update(visible_world_prompts=["contaminating prompt"]))

    def test_changed_raw_byte_is_rejected(self):
        def corrupt(folder, payload):
            raw = (folder / "player.bin").read_bytes()
            (folder / "player.bin").write_bytes(bytes([raw[0] ^ 1]) + raw[1:])
        self.run_fixture(corrupt)

    def test_hdr_is_not_clamped(self):
        rgb = np.full((8, 8, 3), .125)
        rgb[2:6, 2:6] = 2
        result = verify.contrast(rgb, [2, 2, 4, 4], [0, 0, 8, 8])
        self.assertAlmostEqual(result["inner"], 2)
        self.assertAlmostEqual(result["bright"], (2 - .125) / (.125 + .02))


if __name__ == "__main__":
    unittest.main()
