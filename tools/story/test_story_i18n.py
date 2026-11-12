"""ST-2: visible narration/subtitle schema and safe translation metadata."""
import copy
import unittest

import story_i18n


class StoryI18nTests(unittest.TestCase):
    def fixture(self):
        return {"scenes": {"opening": {"steps": [
            {"do": "narrate", "lines": ["雨一直下。", "水位升高。", 12, {"id": "內部名稱"}]},
            {"do": "title", "text": "序章", "ja": "序章", "en": "Prologue", "sub": "巢蛋當舖"},
        ], "when": {"text": "中文條件"}, "set_flags": ["中文旗標"]}}}

    def test_visible_paths_and_generation_preserve_source(self):
        document = self.fixture()
        original = copy.deepcopy(document)
        table = {"雨一直下。": {"ja": "雨が降り続く。", "en": "The rain keeps falling."},
                 "水位升高。": {"ja": "水位が上がる。", "en": "The water rises."},
                 "巢蛋當舖": {"ja": "巢蛋当舗", "en": "Nest Egg Pawnshop"}}
        paths = [entry[0] for entry in story_i18n.walk(document)]
        self.assertEqual(paths, ["/scenes/opening/steps/0/lines/0", "/scenes/opening/steps/0/lines/1",
                                 "/scenes/opening/steps/1/text", "/scenes/opening/steps/1/sub"])
        self.assertEqual(story_i18n.apply(document, table), [])
        steps = document["scenes"]["opening"]["steps"]
        self.assertEqual(steps[0]["lines_en"][:2], ["The rain keeps falling.", "The water rises."])
        self.assertEqual(steps[0]["lines"], original["scenes"]["opening"]["steps"][0]["lines"])
        self.assertEqual(steps[0]["lines_en"][2:], [12, {"id": "內部名稱"}])
        self.assertEqual(steps[1]["sub_en"], "Nest Egg Pawnshop")
        self.assertEqual(document["scenes"]["opening"]["when"], original["scenes"]["opening"]["when"])
        self.assertEqual(document["scenes"]["opening"]["set_flags"], ["中文旗標"])
        self.assertEqual(story_i18n.missing_strings(document, {}), [])
        once = copy.deepcopy(document)
        self.assertEqual(story_i18n.apply(document, table), [])
        self.assertEqual(document, once)

    def test_bad_alternates_are_missing_at_the_source_path(self):
        for bad in ("wrong container", [], ["too short"], [{"text": "bad"}, "", 12, {"id": "內部名稱"}]):
            with self.subTest(bad=bad):
                document = self.fixture()
                steps = document["scenes"]["opening"]["steps"]
                steps[0]["lines_ja"] = bad
                steps[1]["sub_ja"] = {"text": "bad"}
                self.assertEqual(story_i18n.missing_strings(document, {}), ["雨一直下。", "水位升高。", "巢蛋當舖"])
                missing = story_i18n.apply(document, {})
                self.assertIn("/scenes/opening/steps/0/lines/0 [ja] 雨一直下。", missing)
                self.assertIn("/scenes/opening/steps/1/sub [ja] 巢蛋當舖", missing)

    def test_authored_overrides_win_per_line(self):
        document = {"steps": [{"do": "narrate", "lines": ["雨一直下。", "水位升高。"],
                               "lines_ja": ["作者の訳。", None]}]}
        table = {"雨一直下。": {"ja": "表の訳。", "en": "Rain."},
                 "水位升高。": {"ja": "水位が上がる。", "en": "Water rises."}}
        self.assertEqual(story_i18n.apply(document, table), [])
        self.assertEqual(document["steps"][0]["lines_ja"], ["作者の訳。", "水位が上がる。"])

    def test_non_narration_string_arrays_are_not_visible(self):
        document = {"steps": [{"do": "flags", "lines": ["中文旗標"]}], "ids": ["內部名稱"]}
        self.assertEqual(story_i18n.walk(document), [])
        self.assertEqual(story_i18n.apply(document, {}), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
