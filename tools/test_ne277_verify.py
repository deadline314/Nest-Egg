import copy
from pathlib import Path
import unittest
from ne277_verify import METRICS, LIMITS, verify_motion, verify_feedback, verify_gait, rope_inside_crop


class MotionEvidenceTests(unittest.TestCase):
    def test_rope_world_geometry_cannot_claim_clipped_or_missing_nodes(self):
        frame = {"crop": [300, 100, 400, 300], "rope_screen_points": [[400.0, 200.0] for _ in range(20)]}
        self.assertTrue(rope_inside_crop(frame))
        for point in [[0.0, 200.0], [301.0, 200.0], [400.0, float("nan")]]:
            bad = copy.deepcopy(frame); bad["rope_screen_points"][10] = point
            self.assertFalse(rope_inside_crop(bad))
        frame["rope_screen_points"].pop()
        self.assertFalse(rope_inside_crop(frame))

    def test_gait_controls_use_actual_frames_and_cannot_claim_false_verdicts(self):
        rows = []
        for kind in ["idle", "lunge"]:
            for side in [-1, 1]:
                for broken in [False, True]:
                    frames = [{"frame": i, "angles": [1.0 if broken and i == 0 else 0.0] + [0.0] * 5, "floor_errors": [0.0, 0.0]} for i in range(90)]
                    rows.append({"name": f"{kind}/{side}/negative-{str(broken).lower()}", "initial_angles": [0.0] * 6, "frames": frames, "leg_pop": 1.0 if broken else 0.0, "penetration": 0.0, "accepted": not broken})
        d = {"rows": rows, "failures": []}
        self.assertEqual([], verify_gait(d))
        for mutate in [lambda x: x.update(rows=[]), lambda x: x["rows"][0]["frames"].pop(), lambda x: x["rows"][1].update(accepted=True), lambda x: x["rows"][0]["frames"][0].update(floor_errors=[float("nan"), 0.0]), lambda x: x["rows"][0].update(leg_pop=0.9), lambda x: x["rows"][0].update(leg_pop=float("nan")), lambda x: x["rows"][0].update(penetration=float("nan"))]:
            with self.subTest(mutate=mutate):
                bad = copy.deepcopy(d); mutate(bad)
                self.assertTrue(verify_gait(bad))

    def fixture(self):
        frames = [{"tick": i, "phase": phase, "angles": {"hand": 0.1}, "on_floor": True, "foot_ground_error": [0.0, 0.0], "held_input": phase != 0, "hold_mode": "sustain" if phase else ""} for i, phase in enumerate([1, 2, 3, 0])]
        return {"checks": 12, "failures": [], "rows": [{"name": "glaive/1/guard-held", "ended": True, "frames": frames, "held": True, "released": True, "results": {key: {"value": 0, "limit": LIMITS[key]} for key in METRICS}, "path_samples": 4, "palm_max": 0, "second_max": 0, "second_missed": 0}]}

    def test_valid(self):
        self.assertEqual([], self.verify(self.fixture()))

    def verify(self, data):
        return verify_motion(data, {"glaive/1/guard-held"}, Path("."))

    def test_rejects_each_missing_metric(self):
        for key in METRICS:
            with self.subTest(key=key):
                d = self.fixture(); del d["rows"][0]["results"][key]
                self.assertTrue(self.verify(d))

    def test_rejects_failed_state_mutations(self):
        changes = [lambda d: d.update(checks=0), lambda d: d.update(rows=[]), lambda d: d["rows"].append(copy.deepcopy(d["rows"][0])), lambda d: d["rows"][0].update(frames=[]), lambda d: d["rows"][0].update(ended=False), lambda d: d["rows"][0].update(released=False), lambda d: d["rows"][0]["frames"][1].update(tick=9), lambda d: d["rows"][0]["frames"][2].update(phase=2), lambda d: d["rows"][0].update(path_samples=0), lambda d: d["rows"][0].update(second_missed=1), lambda d: d["rows"][0]["results"]["angle_pop"].update(value=1), lambda d: d["rows"][0]["results"]["angle_pop"].update(value=float("nan")), lambda d: d["rows"][0]["frames"][0].update(angles={}), lambda d: d.update(failures=["bad"])]
        for i, change in enumerate(changes):
            with self.subTest(case=i):
                d = self.fixture(); change(d)
                self.assertTrue(self.verify(d))
        for floor in [None, [], [0.0], [1.0, 0.0], [float("nan"), 0.0]]:
            with self.subTest(floor=floor):
                d = self.fixture(); d["rows"][0]["frames"][0]["foot_ground_error"] = floor
                self.assertTrue(self.verify(d))

    def test_headless_cannot_claim_native(self):
        self.assertTrue(verify_motion(self.fixture(), {"glaive/1/guard-held"}, Path("."), native=True))

    def test_missing_or_disabled_held_input_cannot_bypass_validation(self):
        for field in [None, False, "true"]:
            with self.subTest(held=field):
                d = self.fixture(); d["rows"][0]["held"] = field
                self.assertTrue(self.verify(d))
        d = self.fixture()
        for frame in d["rows"][0]["frames"]:
            frame["held_input"] = False
        self.assertTrue(self.verify(d))

    def test_relaxed_limits_and_hidden_real_jump_are_rejected(self):
        d = self.fixture(); d["rows"][0]["results"]["angle_pop"]["limit"] = 1.98
        self.assertTrue(self.verify(d))

        d = self.fixture(); d["rows"][0]["frames"][2]["angles"]["hand"] = 3
        self.assertTrue(self.verify(d))

    def test_feedback_rejects_missing_contact_freeze_and_leaf(self):
        row = {"name": "blade", "reduced": False, "settings": {"reduce_flashes": False, "shake": 1.0, "zoom_enabled": True}, "world_shakes": [{"px": 1.6}], "hits": [{"tick": 9, "amount": 2, "attacker": True, "freeze_attacker": True}], "frames": [{"tick": 9, "player_frozen": True, "enemy_frozen": True}], "first_observed_pair_freeze": True, "expected_layers": ["low", "high"], "played": ["thud", "cut"]}
        events = {"low": {"layers": [{"sounds": ["thud"]}]}, "high": {"layers": [{"sounds": ["cut"]}]}}
        d = {"checks": 8, "failures": [], "rows": [row]}
        self.assertEqual([], verify_feedback(d, {"blade"}, events))
        for mutate in [lambda r: r.update(hits=[]), lambda r: r["frames"][0].update(enemy_frozen=False), lambda r: r.update(played=["cut"]), lambda r: r.update(first_observed_pair_freeze=False), lambda r: r["hits"][0].update(amount=float("nan")), lambda r: r.update(world_shakes=[{"px": float("nan")}])]:
            bad = copy.deepcopy(d); mutate(bad["rows"][0])
            self.assertTrue(verify_feedback(bad, {"blade"}, events))
        self.assertTrue(verify_feedback(d, {"blade", "maul"}, events))

    def test_actual_reduced_world_motion_is_required(self):
        row = {"name": "blade", "reduced": True, "settings": {"reduce_flashes": True, "shake": 0.0, "zoom_enabled": False}, "world_shakes": [], "hits": [{"tick": 9, "amount": 2, "attacker": True, "freeze_attacker": True}], "frames": [{"tick": 9, "player_frozen": True, "enemy_frozen": True}], "first_observed_pair_freeze": True, "expected_layers": ["low", "high"], "played": ["thud", "cut"]}
        events = {"low": {"layers": [{"sounds": ["thud"]}]}, "high": {"layers": [{"sounds": ["cut"]}]}}
        d = {"checks": 8, "failures": [], "rows": [row]}
        self.assertEqual([], verify_feedback(d, {"blade"}, events))
        for mutate in [lambda r: r["settings"].update(shake=1.0), lambda r: r["settings"].update(zoom_enabled=True), lambda r: r.update(world_shakes=[{"px": 1.6}]), lambda r: r["settings"].update(reduce_flashes=False)]:
            with self.subTest(mutate=mutate):
                bad = copy.deepcopy(d); mutate(bad["rows"][0])
                self.assertTrue(verify_feedback(bad, {"blade"}, events))


if __name__ == "__main__":
    unittest.main()
