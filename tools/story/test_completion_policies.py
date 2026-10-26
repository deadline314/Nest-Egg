"""Reject authored results that could fall back to legacy immediate publication."""
import copy
import unittest
import ch1_runtime_backend as backend


class CompletionPolicies(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scenes = backend.compile_document()["scenes"]

    def test_actual_chapter_is_read_only_and_has_known_policies(self):
        original = copy.deepcopy(self.scenes)
        backend.validate_completion_policies(self.scenes)
        self.assertEqual(self.scenes, original)

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
