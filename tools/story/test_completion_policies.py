"""Reject authored results that could fall back to legacy immediate publication."""
import copy
import unittest
import re
from pathlib import Path
import ch1_runtime_backend as backend


class CompletionPolicies(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scenes = backend.compile_document()["scenes"]

    def test_actual_chapter_is_read_only_and_has_known_policies(self):
        original = copy.deepcopy(self.scenes)
        backend.validate_completion_policies(self.scenes)
        self.assertEqual(self.scenes, original)

    def test_training_dialogues_declare_map_interaction(self):
        found = set()
        root = Path(__file__).resolve().parents[2]
        for resource in sorted((root / "data/props").glob("ch1_training_*.tres")):
            for ident in re.findall(r'^\s*(?:done_scene|fail_scene)\s*=\s*&"([^"]+)"', resource.read_text(), re.M):
                scene = self.scenes[ident]
                if scene["mode"] == "dialogue":
                    with self.subTest(resource=resource.name, scene=ident):
                        self.assertIs(scene.get("map_interaction"), True)
                    found.add(ident)
        self.assertTrue({"ch1_p02_talk", "ch1_p04_fall", "ch1_p04_dash"}.issubset(found))
        self.assertFalse(self.scenes["ch1_p01_door"].get("map_interaction", False))

    def test_map_interaction_requires_a_boolean(self):
        for value in [1, "true", None, [], {}]:
            with self.subTest(value=value):
                with self.assertRaisesRegex(backend.CompileError, "bad_map.*map_interaction"):
                    backend.validate_completion_policies({"bad_map": {"mode":"dialogue", "map_interaction":value}})

    def test_map_interaction_cannot_claim_a_stage_or_passive_scene(self):
        for mode in ["animated", "cinematic", "radio", "bubbles", "dispatch"]:
            with self.subTest(mode=mode):
                with self.assertRaisesRegex(backend.CompileError, "bad_map.*map_interaction"):
                    backend.validate_completion_policies({"bad_map": {"mode":mode, "map_interaction":True}})
                backend.validate_completion_policies({"disabled_map": {"mode":mode, "map_interaction":False}})

    def test_each_original_prologue_result_cannot_lose_its_gate(self):
        for ident in ["ch1_p05_service_fall", "ch1_p05_service_clean", "ch1_p06_call"]:
            with self.subTest(scene=ident):
                scene = copy.deepcopy(self.scenes[ident])
                scene.pop("completion_policy")
                with self.assertRaisesRegex(backend.CompileError, ident):
                    backend.validate_completion_policies({ident:scene})

    def test_future_unregistered_result_cannot_silently_publish(self):
        with self.assertRaisesRegex(backend.CompileError, "future_result"):
            backend.validate_completion_policies({"future_result":{
                "mode":"dialogue", "results":[{"kind":"flag", "id":"done", "value":True}]}})

    def test_unknown_or_malformed_policy_is_not_an_owner(self):
        for policy in ["atomic_v1", "typo", True, 1, [], {}]:
            with self.subTest(policy=policy):
                with self.assertRaisesRegex(backend.CompileError, "future_result"):
                    backend.validate_completion_policies({"future_result":{
                        "mode":"dialogue", "completion_policy":policy, "set_flags":["done"]}})

    def test_important_flag_radio_keeps_its_original_owner(self):
        backend.validate_completion_policies({"radio":self.scenes[backend.BOOTH_RECORDING]})
        scene = copy.deepcopy(self.scenes[backend.BOOTH_RECORDING])
        scene["freeze"] = False
        with self.assertRaisesRegex(backend.CompileError, "radio"):
            backend.validate_completion_policies({"radio":scene})

    def test_radio_cannot_add_an_unguarded_reward_or_transfer(self):
        for field, value in [("results",[{"kind":"item_acquire","id":"ch1_grey_cloth"}]),
                             ("transfer_items",["ch1_grey_cloth"])]:
            with self.subTest(field=field):
                scene = copy.deepcopy(self.scenes[backend.BOOTH_RECORDING])
                scene[field] = value
                with self.assertRaisesRegex(backend.CompileError, "radio"):
                    backend.validate_completion_policies({"radio":scene})


if __name__ == "__main__":
    unittest.main()
