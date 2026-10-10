"""CPU regression: generated weather layers must match stage intent and committed JSON."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

import build_ch1_story as story


ROOT = Path(__file__).resolve().parents[2]
FORMAL_STAGE_DIR = ROOT / "data" / "cutscene" / "stages"
INDOOR_STAGES = {
    "ch1_pawnshop_front",
    "ch1_pawnshop_kitchen",
    "ch1_revival_room",
    "ch1_revival_lounge",
}
OUTDOOR_RAIN_STAGES = {"ch1_rooftop", "ch1_dawn_noodle_stall"}


def rain_layers(stage: dict) -> list[dict]:
    return [layer for layer in stage["layers"] if layer.get("kind") == "rain"]


class StageWeatherRegression(unittest.TestCase):
    def test_all_rain_stages_have_authored_outdoor_support(self) -> None:
        rainy = set()
        for path in FORMAL_STAGE_DIR.glob("*.json"):
            stage = json.loads(path.read_text(encoding="utf-8"))
            if rain_layers(stage):
                rainy.add(path.stem)
        self.assertEqual(rainy, OUTDOOR_RAIN_STAGES | {"rainy_harbor"})
        shaft = json.loads((FORMAL_STAGE_DIR / "shaft_descent.json").read_text(encoding="utf-8"))
        self.assertEqual(shaft["camera"], {"pos": [320, -80], "zoom": 1.0})
        self.assertTrue(any(layer.get("kind") == "sprite" for layer in shaft["layers"]))

    def test_chapter_story_output_remains_unchanged(self) -> None:
        story.build()
        generated = {
            "chapter": story.CHAPTER,
            "speakers": story.SPEAKERS,
            "respawn_scenes": story.RESPAWN,
            "death_scenes": story.DEATH_SCENES,
            "scenes": story.SCENES,
        }
        formal = json.loads((ROOT / "data" / "story" / "ch1_kasa.json").read_text(encoding="utf-8"))
        self.assertEqual(generated, formal)

    def test_generator_outputs_match_formal_chapter_one_stages(self) -> None:
        self.assertEqual(set(story.STAGES), INDOOR_STAGES | OUTDOOR_RAIN_STAGES)
        with tempfile.TemporaryDirectory(prefix="ne-stage-weather-") as temp_dir:
            original_stage_dir = story.STAGE_DIR
            story.STAGE_DIR = temp_dir
            try:
                for stage_id, (scene, top, bottom, rain, glow, extra) in story.STAGES.items():
                    with self.subTest(stage=stage_id):
                        story.write_stage(stage_id, scene, top, bottom, rain, glow, extra)
                        generated = json.loads(
                            (Path(temp_dir) / f"{stage_id}.json").read_text(encoding="utf-8")
                        )
                        formal = json.loads(
                            (FORMAL_STAGE_DIR / f"{stage_id}.json").read_text(encoding="utf-8")
                        )
                        self.assertEqual(generated, formal)
                        if stage_id in INDOOR_STAGES:
                            self.assertEqual(rain_layers(generated), [])
                        else:
                            self.assertEqual(len(rain_layers(generated)), 1)
            finally:
                story.STAGE_DIR = original_stage_dir


if __name__ == "__main__":
    unittest.main(verbosity=2)
