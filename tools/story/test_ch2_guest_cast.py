"""CPU guard for the first NE-267 body unit and unchanged guest-book outcomes."""
import copy
import unittest
from pathlib import Path
import struct

import ch2_source
import guest_ticket_staging
from ch1_closure import ProductionSource


class GuestCastTests(unittest.TestCase):
    def setUp(self):
        self.original = ProductionSource()
        ch2_source._guest_book(self.original)
        self.framed = copy.deepcopy(self.original)
        ch2_source._guest_book_frames(self.framed)

    def test_zheng_exists_in_every_real_s18_branch(self):
        for scene in self.framed.segments.values():
            if scene.section != "S18":
                continue
            with self.subTest(scene=scene.id):
                actors = [s for s in scene.steps if s.get("do") == "actor" and s.get("id") == "zheng"]
                self.assertEqual(len(actors), 1)
                actor = actors[0]
                self.assertEqual((actor["kind"], actor["speaker"], actor["facing"]), ("guest_zheng", "zheng", -1))
                self.assertEqual(actor["weapon"], "")
                self.assertEqual(actor["pos"][0], 470 if scene.id == "ch2_t_s18_ticket" else 410)
                self.assertEqual(actor["pos"][1], 265.5)

    def test_visual_cast_does_not_rewrite_dialogue_choices_or_rewards(self):
        presentation = {"actor", "scene", "stage", "camera", "pose", "move", "wait", "reach", "prop", "prop_move",
                        "prop_hold", "prop_release", "prop_visible", "gesture"}
        for ident, original in self.original.segments.items():
            actual = self.framed.segments[ident]
            with self.subTest(scene=ident):
                lines = tuple(s for s in actual.steps if s.get("do") not in presentation)
                self.assertEqual(lines, tuple(s for s in original.steps if s.get("do") not in presentation))
                self.assertEqual(actual.when, original.when)
                self.assertEqual(actual.completion, original.completion)
                self.assertEqual(actual.next_scene, original.next_scene)
                options = tuple(o for o in actual.options if o.id != "back")
                self.assertEqual(options, tuple(o for o in original.options if o.id != "back"))

    def test_guests_do_not_leak_into_next_guest_selection_or_closing(self):
        for scene in self.framed.segments.values():
            if scene.section in {"S17", "S21"}:
                with self.subTest(scene=scene.id):
                    self.assertFalse(any(s.get("do") == "actor" and s.get("kind", "").startswith("guest_")
                                         for s in scene.steps))

    def test_opening_initializes_standing_before_the_real_sit_transition(self):
        steps = self.framed.segments["ch2_t_s18_ticket"].steps
        actor_index = next(i for i, s in enumerate(steps) if s.get("do") == "actor" and s.get("id") == "zheng")
        sit_index = next(i for i, s in enumerate(steps) if s.get("do") == "move" and s.get("id") == "zheng")
        self.assertEqual((steps[sit_index]["to"], steps[sit_index]["then"]), ([410, 265.5], "sit"))
        self.assertEqual(steps[actor_index]["pose"], "idle")
        # Actor creation and pose instructions execute synchronously. The NPC's
        # first update must see stand before a sit target can transition from it.
        self.assertGreaterEqual(sum(s.get("time", 0) for s in steps[actor_index + 1:sit_index]
                                    if s.get("do") == "wait"), .25)

    def test_departure_clears_the_original_actor_plane_chair(self):
        steps = self.framed.segments["ch2_t_s18_done"].steps
        moves = [s for s in steps if s.get("do") == "move" and s.get("id") == "zheng"]
        self.assertEqual(len(moves), 1)
        self.assertEqual((moves[0]["to"], moves[0]["pose"], moves[0]["then"]), ([470, 265.5], "walk", "idle"))
        self.assertGreater(moves[0]["to"][0], 442.75)

    def test_paper_resource_paths_and_native_state_canvases(self):
        root = Path(__file__).resolve().parents[2]
        layer = guest_ticket_staging.layer()
        self.assertEqual(len(layer["states"]), 8)
        for state in layer["states"].values():
            path = state["path"]
            self.assertTrue(path.startswith("res://art/"))
            self.assertNotIn("\\", path)
            header = (root / path.removeprefix("res://")).read_bytes()[:26]
            self.assertEqual(header[:8], b"\x89PNG\r\n\x1a\n")
            self.assertEqual(struct.unpack(">II", header[16:24]), (96, 96))
            self.assertEqual(header[25], 6, "native RGBA state, not an opaque RGB substitute")

    def test_windows_state_paths_are_rejected_before_story_generation(self):
        bad = copy.deepcopy(guest_ticket_staging.STATES)
        bad[0]["path"] = bad[0]["path"].replace("/", "\\")
        with self.assertRaisesRegex(ValueError, "POSIX"):
            guest_ticket_staging.validate_states(bad)
        with self.assertRaisesRegex(ValueError, "1..8"):
            guest_ticket_staging.validate_states(bad * 2)


if __name__ == "__main__":
    unittest.main()
