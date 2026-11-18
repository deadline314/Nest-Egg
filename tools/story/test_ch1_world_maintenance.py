"""First-chapter optional prop actions keep durable results small and explicit."""
import copy
import unittest
import ch1_runtime_backend as backend
import story_contracts


class WorldMaintenanceTests(unittest.TestCase):
    def test_compiling_twice_preserves_the_dispatch_source(self):
        phases = copy.deepcopy(backend.DISPATCH_PHASES)
        first = backend.compile_document()
        self.assertEqual(first, backend.compile_document())
        self.assertEqual(phases, backend.DISPATCH_PHASES)

    def test_real_actions_own_only_their_completed_flag(self):
        document = backend.compile_document()
        cases = {
            "ch1_t_ledger_check": ("ledger_lock_check", "ch1_ledger_checked"),
            "ch1_t_pump_reset": ("pump_case_reset", "ch1_pump_case_reset"),
        }
        records = story_contracts.load_records()
        for scene_id, (action, flag) in cases.items():
            scene = document["scenes"][scene_id]
            self.assertEqual(scene["mode"], "animated")
            self.assertTrue(scene["overlay"])
            self.assertEqual(scene["steps"][0], {"do": "world_action", "id": action})
            self.assertEqual(scene["results"], [{"kind": "flag", "id": flag, "value": True}])
            self.assertEqual(scene["completion_policy"], "main_terminal_results_v1")
            self.assertIn(scene_id, records)
            bad = copy.deepcopy(document["scenes"])
            bad[scene_id]["results"].append({"kind": "flag", "id": "ch1_flood_gate_open", "value": True})
            with self.assertRaises(ValueError):
                story_contracts.validate_generated(bad, "res://data/story/ch1_kasa.json", records)

    def test_declining_repair_keeps_the_original_route(self):
        scene = backend.compile_document()["scenes"]["ch1_t_pump_check"]
        choice = scene["steps"][-1]
        self.assertEqual(choice["default"], "later")
        later = next(option for option in choice["options"] if option["id"] == "later")
        self.assertFalse(later.get("target"))
        self.assertFalse(later.get("set_flags"))
        self.assertFalse(scene.get("results"))


if __name__ == "__main__":
    unittest.main()
