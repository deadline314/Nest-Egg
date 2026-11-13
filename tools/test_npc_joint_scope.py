"""Adversarial CPU controls for the experimental NPC anatomical region guard."""
import unittest

import numpy as np
from npc_joint_scope import classify


class JointScopeTests(unittest.TestCase):
    def setUp(self):
        self.alpha = np.zeros((16, 16), np.uint8)
        self.alpha[2:14, 2:14] = 255
        self.anchors = {"wrist_front": np.array([8., 8.]), "elbow_front": np.array([3., 3.])}
        self.covered = {"wrist_front", "elbow_front"}

    def run_scope(self):
        return classify(self.alpha, "wrist_front", self.anchors, self.covered)

    def notch(self, end):
        for i in range(2, end + 1):
            self.alpha[i, i] = 0

    def test_intact_material_has_no_defect(self):
        self.assertFalse(self.run_scope()["rejected"])

    def test_open_notch_inside_real_wrist_region_still_rejects(self):
        self.notch(7)
        result = self.run_scope()
        self.assertEqual(result["raw"]["enclosed_pixels"], 0)
        self.assertTrue(result["in_scope"])
        self.assertTrue(result["rejected"])

    def test_enclosed_one_pixel_hole_outside_target_always_rejects(self):
        self.alpha[3, 3] = 0
        result = self.run_scope()
        self.assertEqual(result["raw"]["enclosed_pixels"], 1)
        self.assertTrue(result["rejected"])

    def test_uncovered_centre_is_never_excused(self):
        self.alpha[8, 8] = 127
        self.assertTrue(self.run_scope()["rejected"])

    def test_detached_single_pixel_is_never_excused(self):
        self.alpha[0, 0] = 255
        self.assertTrue(self.run_scope()["rejected"])

    def test_exterior_open_notch_requires_complete_same_frame_neighbour(self):
        self.notch(4)
        result = self.run_scope()
        self.assertTrue(result["assigned_exterior"])
        self.assertFalse(result["rejected"])
        self.covered.remove("elbow_front")
        with self.assertRaisesRegex(ValueError, "Missing same-frame"):
            self.run_scope()

    def test_nearby_head_cannot_own_a_real_wrist_defect(self):
        self.notch(7)
        self.anchors["neck"] = np.array([7., 7.])
        self.covered.add("neck")
        self.assertTrue(self.run_scope()["rejected"])

    def test_missing_native_positions_cannot_create_a_pass(self):
        self.anchors.pop("elbow_front")
        with self.assertRaisesRegex(ValueError, "native neighbouring"):
            self.run_scope()

    def test_native_pixel_overlap_retains_boundary_defects(self):
        self.notch(4)
        self.anchors["wrist_front"] = np.array([8., 4.5])
        self.anchors["elbow_front"] = np.array([2., 4.5])
        result = self.run_scope()
        self.assertIn([4, 4], result["in_scope"])
        self.assertTrue(result["rejected"])


if __name__ == "__main__":
    unittest.main()
