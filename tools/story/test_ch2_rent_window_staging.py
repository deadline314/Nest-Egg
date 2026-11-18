"""S08窗口呈現與原結果邊界的受限CPU回歸。"""
import copy
import json
from pathlib import Path
import unittest

import ch2_source
import rent_window_staging as staging

ROOT = Path(__file__).resolve().parents[2]


class RentWindowStagingTests(unittest.TestCase):
    def setUp(self):
        self.source = ch2_source.build_source()
        self.first = self.source.segments["ch2_t_s08_contract"]
        self.revisit = self.source.segments["ch2_t_s08_contract_revisit"]

    def test_original_three_lines_and_revisit_line_are_retained(self):
        lines = [(s["speaker"], s["text"]) for s in self.first.steps if s.get("do") == "say"]
        self.assertEqual(lines, [
            ("window_clerk", "攤位押金本金二百，本期利息二十。申請沒有核准前，不收續租款。"),
            ("rin", "這行要留副本，代收處給我的金額不一樣。"),
            ("window_clerk", "副本給您，章蓋的是暫未核准。"),
        ])
        self.assertEqual([s["text"] for s in self.revisit.steps if s.get("do") == "say"],
                         ["合約副本給過了，申請核准前我們不收續租款。"])

    def test_original_entry_predicates_and_dispatcher_are_retained(self):
        self.assertEqual(self.first.when, {"not": {"flag": "ch2_evidence_contract", "equals": True}})
        self.assertEqual(self.revisit.when, {"flag": "ch2_evidence_contract", "equals": True})
        self.assertEqual(ch2_source.DISPATCH["rent_window"], ["ch2_t_s08_contract", "ch2_t_s08_contract_revisit"])
        self.assertEqual(self.revisit.completion, ())
        self.assertEqual(self.first.mode, "animated")
        self.assertEqual(self.revisit.mode, "animated")

    def test_independent_rule_changes_presentation_only(self):
        original = json.loads((ROOT / "tests/fixtures/story_result_contract_originals.json").read_text(encoding="utf-8"))["ch2"]["BOUNDARIES"]["ch2_t_s08_contract"]
        actual = next(r["rule"] for r in json.loads((ROOT / "data/story_contracts/ch2.json").read_text(encoding="utf-8"))["records"] if r["id"] == "ch2_t_s08_contract")
        self.assertEqual(original["mode"], "dialogue")
        expected = copy.deepcopy(original)
        expected["mode"] = "animated"
        self.assertEqual(actual, expected)

    def test_one_real_seated_clerk_with_supported_pose(self):
        for segment in [self.first, self.revisit]:
            actors = [s for s in segment.steps if s.get("do") == "actor" and s.get("id") == "window_clerk"]
            self.assertEqual(len(actors), 1)
            actor = actors[0]
            self.assertEqual((actor["kind"], actor["speaker"], actor["pose"]), ("ch2_window_clerk", "window_clerk", "sit"))
            self.assertEqual(actor["weapon"], "")
            self.assertTrue(actor["pose_support"] and actor["pose_reason"])
            self.assertTrue(0 <= actor["seat_sag"] <= .9)

    def test_stamp_is_really_held_pressed_released_and_hand_retracted(self):
        steps = list(staging.stamp_steps())
        hold = next(i for i, s in enumerate(steps) if s["do"] == "prop_hold")
        press = next(i for i, s in enumerate(steps) if s.get("to") == staging.PRESS_GRIP)
        mark = next(i for i, s in enumerate(steps) if s["do"] == "prop_visible")
        release = next(i for i, s in enumerate(steps) if s["do"] == "prop_release")
        retract = next(i for i, s in enumerate(steps) if s.get("release"))
        self.assertTrue(hold < press < mark < release < retract)
        self.assertLess(steps[press-1]["to"][1], steps[press]["to"][1])
        self.assertFalse(any("results" in s or "set_flags" in s or s["do"] in ["transaction", "world_action"] for s in steps))

    def test_revisit_does_not_repeat_stamp_or_create_a_second_copy(self):
        self.assertFalse(any(s["do"] == "prop_hold" for s in self.revisit.steps))
        paper = [s for s in self.revisit.steps if s.get("id") == staging.PAPER and s["do"] == "prop_visible"]
        self.assertEqual(len(paper), 1)
        self.assertFalse(paper[0]["visible"])
        mark = [s for s in self.revisit.steps if s.get("id") == staging.MARK and s["do"] == "prop_visible"]
        self.assertEqual(mark, [{"do": "prop_visible", "id": staging.MARK, "visible": False}])


if __name__ == "__main__":
    unittest.main()
