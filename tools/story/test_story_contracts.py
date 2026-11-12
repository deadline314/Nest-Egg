"""Independent author/runtime content boundary; no game writes or generated files."""
import copy
import dataclasses
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import story_contracts as contracts
from build_ch2_story import spec
from chapter_compiler import compile_chapter, CompileError

class StoryContracts(unittest.TestCase):
    def setUp(self):
        self.records = contracts.load_records()
        self.chapter = compile_chapter(spec())

    def test_original_contracts_are_complete_and_generated_unchanged(self):
        self.assertEqual(len(self.records),48)
        contracts.validate_generated(self.chapter["scenes"],"res://data/story/ch2_heron.json",self.records)

    def _load_changed(self, mutate):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            record = copy.deepcopy(next(v for v in self.records.values() if v["role"] == "boundary" and not v["rule"]["then"] and not v["rule"].get("failures")))
            records = [record]
            mutate(records)
            (root/"chapter.json").write_text(json.dumps({"version":1,"records":records}),encoding="utf-8")
            path = root/"catalog.json"
            path.write_text(json.dumps({"version":1,"chapters":[{"source":record["source"],"path":"chapter.json"}]}),encoding="utf-8")
            return contracts.load_records(path)

    def test_bad_complete_catalog_never_returns_partial_records(self):
        changes = [lambda r:r.append({}),lambda r:r[0].update(role=[]),lambda r:r[0]["rule"].update(operations=[{"kind":"flag","id":"bad","value":1}]),lambda r:r[0]["rule"].update(unknown=True),lambda r:r[0].update(levels=[{}]),lambda r:r[0]["rule"].update(then="missing"),lambda r:r[0]["rule"].update(then=r[0]["id"]),lambda r:r[0]["rule"].update(when={"not":{"unknown":True}}),lambda r:r[0]["rule"].update(operations=[{"kind":"item_transfer","id":"original","destination":False}])]
        for i,change in enumerate(changes):
            with self.subTest(i=i),self.assertRaises(ValueError):self._load_changed(change)

    def test_explicit_json_bool_and_numeric_version_are_not_confused(self):
        self.assertFalse(contracts._same(True,1))
        self.assertTrue(contracts._same(1.0,1))
        self.assertTrue(self._load_changed(lambda rows:None))

    def test_finite_fractional_wait_is_not_rounded(self):
        rule={"default":"no","options":[{"id":"yes","target":"","flags":{}},{"id":"no","target":"","flags":{}}],"waits":{"3":0.125}}
        self.assertTrue(contracts._rule_valid("choice",rule))
        rule["waits"]["3"]=float("inf")
        self.assertFalse(contracts._rule_valid("choice",rule))

    def test_generated_effects_cannot_authorize_themselves(self):
        for mutate in [lambda s:s["ch2_t_s05_gate"]["results"].append({"kind":"item_acquire","id":"extra"}),lambda s:s["ch2_t_s05_gate"].update(completion_policy="main_flags_v1"),lambda s:s["ch2_t_s05_gate"]["results"][0].update(value=1)]:
            scenes=copy.deepcopy(self.chapter["scenes"]);mutate(scenes)
            with self.assertRaises(ValueError):contracts.validate_generated(scenes,"res://data/story/ch2_heron.json",self.records)

    def test_missing_catalog_blocks_author_generation(self):
        with patch.object(contracts,"CATALOG",Path("missing-test_bad_cutscene-catalog.json")):
            with self.assertRaises(ValueError):compile_chapter(spec())

    def test_all_three_new_content_examples_use_only_data(self):
        import importlib.util
        fixture=contracts.ROOT/"tests/fixtures/story_contracts_data_only"
        definition=importlib.util.spec_from_file_location("contract_fixture",fixture/"source.py")
        module=importlib.util.module_from_spec(definition);definition.loader.exec_module(module)
        source=module.add_content(spec())
        before=copy.deepcopy(source)
        with patch.object(contracts,"CATALOG",fixture/"catalog.json"):
            generated=compile_chapter(source)
        self.assertEqual(source,before)
        self.assertEqual(generated["scenes"]["ch2_t_patrol_copy"]["results"],[{"kind":"item_acquire","id":"ch2_patrol_copy"},{"kind":"flag","id":"ch2_patrol_copy_received","value":True}])
        with patch.object(contracts,"CATALOG",fixture/"catalog.json"):
            source.source.segments["ch2_t_patrol_copy_prompt"].options[0].intent[0]["value"]=1
            with self.assertRaises(CompileError):compile_chapter(source)


    def test_missing_new_npc_contract_is_a_compile_error(self):
        from ch1_closure import Binding,set_flag
        source=spec();source.source.bindings["patroller"]=Binding("npc","NPC author","res://data/npcs/ch2_patroller.tres")
        source.source.flag_defaults["test_contract_new_flag"]=False
        source.source.add("ch2_t_new_unregistered_npc","TEST",(("patroller","新NPC結果。"),("rin","保留來源。"),("patroller","不能缺契約。")),binding="patroller",completion=(set_flag("test_contract_new_flag"),))
        with self.assertRaisesRegex(CompileError,"ch2_heron.json.*ch2_t_new_unregistered_npc.*contract"):compile_chapter(source)

    def test_unknown_explicit_binding_rejected_even_for_pure_dialogue(self):
        source=spec();source.source.add("ch2_t_unknown_binding","TEST",(("patroller","純對話也不能使用未知綁定。"),),binding="test_missing_npc")
        with self.assertRaisesRegex(CompileError,"ch2_t_unknown_binding.*binding"):compile_chapter(source)

    def test_legacy30_survive_text_but_not_effect_or_entry_changes(self):
        from ch1_closure import set_flag
        migration=json.loads((contracts.ROOT/"data/story_contracts/migration-5a.json").read_text())
        self.assertEqual(len(migration["legacy"]),30)
        for ident,record in migration["legacy"].items():
            self.assertTrue(contracts._same(contracts.effect_projection(self.chapter["scenes"][ident]),record["effects"]),ident)
        source=spec();ident="ch2_t_s01_settled";segment=source.source.segments[ident]
        for name in migration["legacy"]:
            original=source.source.segments[name]
            steps=copy.deepcopy(original.steps)
            spoken=next(step for step in steps if step.get("do")=="say")
            spoken["text"]=("查" if spoken["text"].startswith("觀") else "觀")+spoken["text"][1:]
            source.source.segments[name]=dataclasses.replace(original,steps=tuple(steps))
        compile_chapter(source)
        source.source.flag_defaults["test_contract_new_flag"]=False
        source.source.segments[ident]=dataclasses.replace(segment,completion=segment.completion+(set_flag("test_contract_new_flag"),))
        with self.assertRaisesRegex(CompileError,"ch2_t_s01_settled.*legacy"):compile_chapter(source)
        source=spec();source.dispatch=copy.deepcopy(source.dispatch)
        source.dispatch["old_k"]=list(reversed(source.dispatch["old_k"]))
        with self.assertRaisesRegex(CompileError,"entry|legacy"):compile_chapter(source)

    def test_known_npc_entry_cannot_add_unregistered_effect_sibling(self):
        from ch1_closure import set_flag
        source=spec();source.dispatch=copy.deepcopy(source.dispatch)
        source.source.flag_defaults["test_contract_new_flag"]=False
        source.source.add("ch2_t_unregistered_sibling","TEST",(("patroller","原入口的新副作用。"),),completion=(set_flag("test_contract_new_flag"),))
        source.dispatch["patroller"]=["ch2_t_unregistered_sibling"]+source.dispatch["patroller"]
        with self.assertRaisesRegex(CompileError,"ch2_t_unregistered_sibling.*contract"):compile_chapter(source)

    def test_unbound_generic_scene_is_not_inferred_from_policy_or_speaker(self):
        from ch1_closure import set_flag
        source=spec();source.source.flag_defaults["test_generic_flag"]=False
        source.source.add("ch2_t_generic_presentation","TEST",(("patroller","不是由名稱或講者授NPC來源。"),),completion=(set_flag("test_generic_flag"),))
        source.completion_policies["ch2_t_generic_presentation"]="main_flags_v1"
        compiled=compile_chapter(source)
        self.assertIn("ch2_t_generic_presentation",compiled["scenes"])


    def test_missing_or_corrupt_sealed_index_never_becomes_empty_allowlist(self):
        with tempfile.TemporaryDirectory() as directory:
            file=Path(directory)/"migration.json"
            for contents in (None,b"{}"):
                if contents is not None:file.write_bytes(contents)
                with self.subTest(contents=contents),patch.object(contracts,"MIGRATION",file):
                    with self.assertRaisesRegex(CompileError,"migration"):compile_chapter(spec())

    def test_policy_cannot_replace_removed_known_npc_contract(self):
        records=copy.deepcopy(self.records);del records["ch2_t_s05_gate"]
        with patch.object(contracts,"load_records",return_value=records):
            with self.assertRaisesRegex(CompileError,"ch2_t_s05_gate.*contract"):compile_chapter(spec())


    def test_declared_npc_pure_dialogue_does_not_need_a_write_contract(self):
        from ch1_closure import Binding
        source=spec();source.source.bindings["patroller"]=Binding("npc","NPC author","res://data/npcs/ch2_patroller.tres")
        source.source.add("ch2_t_new_pure_npc","TEST",(("patroller","純對話保留原呈現能力。"),),binding="patroller")
        self.assertIn("ch2_t_new_pure_npc",compile_chapter(source)["scenes"])


    def _explicit_legacy_binding(self, name, resource):
        from ch1_closure import Binding
        source=spec();source.source.bindings[name]=Binding("npc","explicit original author binding",resource)
        ident="ch2_t_s01_settled";source.source.segments[ident]=dataclasses.replace(source.source.segments[ident],binding=name)
        return source

    def test_explicit_original_entry_and_resource_preserve_legacy(self):
        source=self._explicit_legacy_binding("old_k","res://data/npcs/ch2_old_k.tres")
        self.assertIn("ch2_t_s01_settled",compile_chapter(source)["scenes"])

    def test_explicit_legacy_binding_without_original_entry_refuses(self):
        source=self._explicit_legacy_binding("new_npc","res://data/npcs/ch2_old_k.tres")
        with self.assertRaisesRegex(CompileError,"ch2_t_s01_settled.*legacy entry"):compile_chapter(source)

    def test_explicit_legacy_binding_wrong_resource_refuses(self):
        source=self._explicit_legacy_binding("old_k","res://data/npcs/ch2_patroller.tres")
        with self.assertRaisesRegex(CompileError,"ch2_t_s01_settled.*legacy entry"):compile_chapter(source)

if __name__=="__main__":unittest.main()
