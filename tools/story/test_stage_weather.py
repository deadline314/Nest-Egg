"""CPU regression: generated weather layers must match stage intent and committed JSON."""

from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import build_ch1_story as story
import ch1_runtime_backend


ROOT = Path(__file__).resolve().parents[2]
FORMAL_STAGE_DIR = ROOT / "data" / "cutscene" / "stages"
INDOOR_STAGES = {
    "ch1_pawnshop_front",
    "ch1_pawnshop_kitchen",
    "ch1_revival_room",
    "ch1_revival_lounge",
}
OUTDOOR_RAIN_STAGES = {"ch1_rooftop", "ch1_dawn_noodle_stall"}


WEATHER_STAGES = OUTDOOR_RAIN_STAGES | {
    "rainy_harbor", "ch2_phone_booth", "ch2_market_pass", "ch2_rooftop_watcher",
}


def rain_layers(stage: dict) -> list[dict]:
    return [layer for layer in stage["layers"] if layer.get("kind") == "rain"]


def weather_layers(stage_id: str, stage: dict) -> list[dict]:
    return [
        layer for layer in rain_layers(stage)
        if not (stage_id == "ch1_pawnshop_kitchen" and layer.get("id") == "tap_water")
    ]


class StageWeatherRegression(unittest.TestCase):
    def test_all_rain_stages_have_authored_outdoor_support(self) -> None:
        rainy = set()
        for path in FORMAL_STAGE_DIR.glob("*.json"):
            stage = json.loads(path.read_text(encoding="utf-8"))
            if weather_layers(path.stem, stage):
                rainy.add(path.stem)
        self.assertEqual(rainy, WEATHER_STAGES)
        shaft = json.loads((FORMAL_STAGE_DIR / "shaft_descent.json").read_text(encoding="utf-8"))
        self.assertEqual(shaft["camera"], {"pos": [320, -80], "zoom": 1.0})
        self.assertTrue(any(layer.get("kind") == "sprite" for layer in shaft["layers"]))

    def test_chapter_story_output_remains_unchanged(self) -> None:
        with tempfile.TemporaryDirectory(prefix="ne-stage-story-") as temp_dir:
            generated_path = Path(temp_dir) / "ch1_kasa.json"
            with patch.object(ch1_runtime_backend, "OUT", generated_path), patch.object(story, "STAGE_DIR", temp_dir):
                self.assertEqual(ch1_runtime_backend.main(), 0)
            generated = json.loads(generated_path.read_text(encoding="utf-8"))
        formal = json.loads((ROOT / "data" / "story" / "ch1_kasa.json").read_text(encoding="utf-8"))
        self.assertEqual(generated, formal)

    def test_kitchen_faucet_stays_local_and_off_until_used(self) -> None:
        kitchen = json.loads((FORMAL_STAGE_DIR / "ch1_pawnshop_kitchen.json").read_text(encoding="utf-8"))
        layers = rain_layers(kitchen)
        self.assertEqual([layer.get("id") for layer in layers], ["tap_water"])
        self.assertIs(layers[0].get("visible"), False)
        x, y, width, height = layers[0]["area"]
        self.assertGreater(x, 0)
        self.assertGreater(y, 0)
        self.assertTrue(0 < width <= 2 and 0 < height <= 8)

        chapter = json.loads((ROOT / "data" / "story" / "ch1_kasa.json").read_text(encoding="utf-8"))
        steps = chapter["scenes"]["ch1_c14_home"]["steps"]
        visible = [step.get("visible") for step in steps
                   if step.get("do") == "prop_visible" and step.get("id") == "tap_water"]
        self.assertEqual(visible, [True, False])

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
                            self.assertEqual(weather_layers(stage_id, generated), [])
                        else:
                            self.assertEqual(len(rain_layers(generated)), 1)
            finally:
                story.STAGE_DIR = original_stage_dir


if __name__ == "__main__":
    unittest.main(verbosity=2)
