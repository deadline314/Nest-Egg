"""Guard the same native fingertip across a hidden-wrist crop change and compiled Story."""
import json
import math
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]


def read(name):
    return json.loads((ROOT / name).read_text(encoding="utf8"))


class GuestContactSourceTests(unittest.TestCase):
    def setUp(self):
        self.original = read("art_src/characters/guest_zheng/02_pose/hand_contact_original.json")
        self.contact = read("art_src/characters/guest_zheng/hand_contact.json")
        self.affine = read("art_src/characters/guest_zheng/cut_registration.json")["hand"]["native_affine"]

    def native(self, point):
        return [row[0] * point[0] + row[1] * point[1] + row[2] for row in self.affine]

    def test_preserves_original_native_contact_after_crop_growth(self):
        self.assertLess(math.dist(self.native(self.contact["runtime_point"]), self.original["native_affine_point"]), 1e-4)
        self.assertEqual(self.contact["k"], 1)

    def test_previous_cut_coordinate_is_a_real_failure_control(self):
        # A fixed old UV still points into a hand, but changes which physical
        # fingertip holds the paper after the wrist's hidden canvas grew.
        self.assertGreater(math.dist(self.native(self.original["original_runtime_point"]), self.original["native_affine_point"]), 10)

    def test_compiled_real_reaches_use_registered_contact(self):
        chapter = read("data/story/ch2_heron.json")
        scenes = chapter["scenes"]
        scene = scenes["ch2_t_s18_ticket"] if isinstance(scenes, dict) else next(s for s in scenes if s["id"] == "ch2_t_s18_ticket")
        reaches = [s for s in scene["steps"] if s.get("do") == "reach" and s.get("id") == "zheng" and "contact" in s]
        self.assertGreaterEqual(len(reaches), 2)
        self.assertTrue(all(s["contact"] == self.contact["runtime_point"] for s in reaches))


if __name__ == "__main__":
    unittest.main()
