"""Failure-oriented CPU tests; real Godot export probes are separate evidence."""
from __future__ import annotations

import hashlib
import json
import os
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import campaign_build as build
import campaign_release as audit
import pack_integrity as pack


def pck_bytes(entries=None, version=4, engine=(4, 7, 2)) -> bytes:
    entries = entries or [("data/probe.json", b'{"fixture":true}')]
    body, index = bytearray(), bytearray(struct.pack("<I", len(entries)))
    for name, content in entries:
        raw = ("res://" + name).encode()
        raw += b"\x00" * (-len(raw) % 4)
        index += struct.pack("<I", len(raw)) + raw
        index += struct.pack("<QQ", len(body), len(content))
        index += hashlib.md5(content, usedforsecurity=False).digest() + struct.pack("<I", 0)
        body += content
    header = b"GDPC" + struct.pack("<IIIIIQQ", version, *engine, 2, 104, 104 + len(body)) + bytes(64)
    return header + body + index


class ImmutableStageTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.root = self.base / "repo"
        self.root.mkdir()
        self.policy = {"schema": 1, "engine_version": "4.7.2.stable", "development_scripts": [],
                       "dynamic_paths": [], "directory_loads": []}
        self.specs = {"schema": 1, "runtime_roots": ["autoload", "data"],
                      "runtime_files": ["project.godot"], "optional_missing": ["tools/dev_tools.json"],
                      "chapters": [{"id": "one", "status": "draft", "acceptance_ticket": "NE-233",
                                    "entry": "data/entry.tres", "terminal": "data/end.tres", "evidence": []}]}
        for folder in ("autoload", "data/story", "tools/release", "pm/Nest-Egg"):
            (self.root / folder).mkdir(parents=True)
        self.put("project.godot", '[application]\nrun/main_scene="res://data/entry.tres"\n[autoload]\nStory="*res://autoload/story.gd"\n')
        self.put("autoload/story.gd", 'const CHAPTER_PATHS = ["res://data/story/one.json", "res://data/story/later.json"]\n')
        self.put("autoload/story.gd.uid", "uid://dteststory\n")
        self.put("data/story/one.json", json.dumps({"chapter": {"id": "one"}, "quests": [], "scenes": {}}))
        self.put("data/story/later.json", json.dumps({"chapter": {"id": "later"}, "quests": [], "scenes": {}}))
        self.put("data/entry.tres", '[gd_resource type="Resource" format=3]\n[resource]\n')
        self.put("data/end.tres", '[gd_resource type="Resource" format=3]\n[resource]\n')
        self.put("tools/release/campaign_specs.json", json.dumps(self.specs))
        self.put("pm/Nest-Egg/[NE-233]驗收.md", "> 狀態：進行中\n- [ ] 章節驗收\n")
        self.git("init", "-q")
        self.commit()
        self.sha = self.git("rev-parse", "HEAD").strip()

    def put(self, name, text):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], text=True)

    def commit(self):
        self.git("add", ".")
        self.git("-c", "user.name=Stanley Li", "-c", "user.email=stanley890314@gmail.com", "commit", "-qm", "fixture source")

    def prepare(self, version="tool-test"):
        return build.prepare(self.root, self.base / "builds", self.sha, "one", version, self.policy)

    def tearDown(self):
        self.temp.cleanup()

    def test_dirty_and_untracked_inputs_never_enter_commit_snapshot(self):
        self.put("data/untracked.png", "not committed")
        self.put("data/story/one.json", "dirty invalid JSON")
        destination, report = self.prepare()
        self.assertTrue(report["source_worktree_dirty"])
        self.assertFalse((destination / "project/data/untracked.png").exists())
        self.assertIsInstance(json.loads((destination / "project/data/story/one.json").read_text()), dict)
        self.assertEqual(report["source_sha"], self.sha)

    def test_all_later_story_sources_are_preserved(self):
        destination, report = self.prepare()
        self.assertTrue((destination / "project/data/story/later.json").is_file())
        self.assertEqual(len(report["readiness"]["loaded_story_sources"]), 2)
        self.assertEqual(report["resource_closure"]["issues"], [])

    def test_existing_stage_is_preserved_even_when_previous_build_failed(self):
        destination, _ = self.prepare()
        original = (destination / "source-manifest.json").read_bytes()
        with self.assertRaises(FileExistsError):
            self.prepare()
        self.assertEqual((destination / "source-manifest.json").read_bytes(), original)

    def test_outputs_inside_repo_are_rejected_before_writes(self):
        with self.assertRaisesRegex(audit.AuditError, "outside"):
            build.prepare(self.root, self.root / "builds", self.sha, "one", "test", self.policy)
        self.assertFalse((self.root / "builds").exists())

    def test_unknown_chapter_and_unsafe_version_do_not_reserve_stage(self):
        for end, version in (("later", "test"), ("one", "../escape")):
            with self.subTest(end=end), self.assertRaises(audit.AuditError):
                build.prepare(self.root, self.base / "builds", self.sha, end, version, self.policy)
        self.assertFalse((self.base / "builds").exists())

    def test_only_full_existing_commit_sha_is_accepted(self):
        for sha in (self.sha[:8], "HEAD", "0" * 40, "--help"):
            with self.subTest(sha=sha), self.assertRaises(audit.AuditError):
                build.prepare(self.root, self.base / "builds", sha, "one", "test", self.policy)

    def test_real_committed_symlink_is_rejected(self):
        (self.root / "data/link.tres").symlink_to("entry.tres")
        self.commit()
        self.sha = self.git("rev-parse", "HEAD").strip()
        with self.assertRaisesRegex(audit.AuditError, "linked"):
            self.prepare()

    def test_output_parent_symlink_is_rejected(self):
        real = self.base / "real"
        real.mkdir()
        link = self.base / "linked"
        link.symlink_to(real, target_is_directory=True)
        with self.assertRaisesRegex(audit.AuditError, "linked output"):
            build.prepare(self.root, link, self.sha, "one", "test", self.policy)

    def test_verification_detects_same_size_content_corruption(self):
        destination, _ = self.prepare()
        path = destination / "project/data/end.tres"
        raw = path.read_bytes()
        path.write_bytes(b"X" + raw[1:])
        with self.assertRaisesRegex(audit.AuditError, "staged input changed"):
            build.verify_stage(destination)

    def test_verification_detects_extra_ignored_input(self):
        destination, _ = self.prepare()
        (destination / "project/data/new.png").write_bytes(b"extra")
        with self.assertRaisesRegex(audit.AuditError, "unexpected"):
            build.verify_stage(destination)

    def test_manifest_tampering_is_detected(self):
        destination, _ = self.prepare()
        path = destination / "source-manifest.json"
        path.write_text(path.read_text() + " ", encoding="utf-8")
        with self.assertRaisesRegex(audit.AuditError, "checksum"):
            build.verify_stage(destination)

    def test_draft_export_is_blocked_and_no_product_receipt_created(self):
        destination, _ = self.prepare()
        with self.assertRaisesRegex(audit.AuditError, "formal chapter export blocked"):
            build.require_product_ready(destination)
        report = json.loads((destination / "export-blocked.json").read_text())
        self.assertFalse(report["exported"])
        self.assertFalse((destination / "probe-manifest.json").exists())

    def test_claimed_acceptance_with_blank_evidence_and_no_quests_is_blocked(self):
        self.specs["chapters"][0].update(status="accepted", evidence=["pm/Nest-Egg/empty.log"])
        self.put("tools/release/campaign_specs.json", json.dumps(self.specs))
        self.put("pm/Nest-Egg/empty.log", " ")
        self.put("pm/Nest-Egg/[NE-233]驗收.md", "> 狀態：完成\n- [x] 空標記\n")
        self.commit()
        self.sha = self.git("rev-parse", "HEAD").strip()
        _, report = self.prepare()
        issues = report["readiness"]["chapters"][0]["issues"]
        self.assertTrue(any("empty/trivial" in p for p in issues))
        self.assertIn("published production main quests absent", issues)
        self.assertFalse(report["readiness"]["ready_for_product_export"])

    def test_unknown_dynamic_reference_blocks_and_known_directory_keeps_later_files(self):
        self.put("data/loader.gd", 'const PATH = "res://data/story/%s.json"\n')
        self.put("data/loader.gd.uid", "uid://dtestloader\n")
        self.put("project.godot", (self.root / "project.godot").read_text() + 'Loader="*res://data/loader.gd"\n')
        self.commit()
        self.sha = self.git("rev-parse", "HEAD").strip()
        _, report = self.prepare()
        self.assertTrue(any("uncovered dynamic" in p for p in report["resource_closure"]["issues"]))
        self.policy["dynamic_paths"] = [{"source": "data/loader.gd", "path": "data/story/%s.json", "root": "data/story"}]
        destination, report = self.prepare("known-dynamic")
        self.assertEqual(report["resource_closure"]["issues"], [])
        self.assertTrue((destination / "project/data/story/later.json").exists())

    def test_changed_directory_loader_contract_blocks(self):
        self.policy["directory_loads"] = [{"source": "autoload/story.gd", "root": "data/absent"}]
        _, report = self.prepare()
        self.assertTrue(any("directory loader contract" in p for p in report["resource_closure"]["issues"]))

    def test_runtime_reference_to_development_file_blocks(self):
        self.put("data/notes.md", "development")
        self.put("data/loader.gd", 'const FILE = "res://data/notes.md"\n')
        self.put("data/loader.gd.uid", "uid://dloader\n")
        self.put("project.godot", (self.root / "project.godot").read_text() + 'Loader="*res://data/loader.gd"\n')
        self.commit()
        self.sha = self.git("rev-parse", "HEAD").strip()
        destination, report = self.prepare()
        self.assertFalse((destination / "project/data/notes.md").exists())
        self.assertTrue(any("reference:" in p for p in report["resource_closure"]["issues"]))

    def test_malformed_import_mapping_blocks(self):
        self.put("data/sprite.png", "fixture bytes")
        self.put("data/sprite.png.import", 'source_file="res://data/other.png"\n')
        self.commit()
        self.sha = self.git("rev-parse", "HEAD").strip()
        _, report = self.prepare()
        self.assertIn("invalid import source mapping: data/sprite.png.import", report["resource_closure"]["issues"])

    def test_invalid_policy_cannot_expand_exclusions_or_dynamic_roots(self):
        for field, value in (("development_scripts", ["autoload/story.gd"]),
                             ("dynamic_paths", [{"source": "data/loader.gd", "root": "tools", "path": "tools/%s.json"}])):
            candidate = {**self.policy, field: value}
            with self.subTest(field=field), self.assertRaises(audit.AuditError):
                build.validate_policy(candidate)

    def test_log_errors_fail_even_when_process_returns_zero_and_log_is_preserved(self):
        log = self.base / "zero-error.log"
        with self.assertRaisesRegex(audit.AuditError, "exit=0, error_log=True"):
            build.run_logged([os.sys.executable, "-c", "print('SCRIPT ERROR: genuine failure')"], log, self.base)
        original = log.read_bytes()
        with self.assertRaises(FileExistsError):
            build.run_logged([os.sys.executable, "-c", "print('PASS')"], log, self.base)
        self.assertEqual(log.read_bytes(), original)

    def test_nonzero_export_retains_log(self):
        log = self.base / "nonzero.log"
        with self.assertRaisesRegex(audit.AuditError, "exit=7"):
            build.run_logged([os.sys.executable, "-c", "raise SystemExit(7)"], log, self.base)
        self.assertIn("exit_code=7", log.read_text())

    def test_runtime_dirs_are_scoped_without_changing_proxy_or_home(self):
        log = self.base / "scope.log"
        command = [os.sys.executable, "-c", "import os; assert os.environ['XDG_DATA_HOME'].startswith(" + repr(str(self.base)) + "); print('scoped')"]
        build.run_logged(command, log, self.base)
        self.assertTrue((self.base / "user/data").is_dir())

    def test_global_class_dependency_is_kept_and_unused_development_script_is_pruned(self):
        self.put("data/a.gd", 'class_name RuntimeA\nextends Resource\nvar other: RuntimeB\n')
        self.put("data/b.gd", 'class_name RuntimeB\nextends Resource\n')
        self.put("data/dev.gd", 'class_name DevOnly\nextends Resource\nconst BAD="res://tools/missing.json"\n')
        for name in ("a", "b", "dev"):
            self.put(f"data/{name}.gd.uid", f"uid://d{name}fixture\n")
        self.put("data/entry.tres", '[gd_resource type="Resource" load_steps=2 format=3]\n[ext_resource type="Script" path="res://data/a.gd" id="1"]\n[resource]\nscript=ExtResource("1")\n')
        self.commit()
        self.sha = self.git("rev-parse", "HEAD").strip()
        destination, report = self.prepare()
        self.assertTrue((destination / "project/data/b.gd").is_file())
        self.assertFalse((destination / "project/data/dev.gd").exists())
        self.assertFalse((destination / "project/data/dev.gd.uid").exists())
        self.assertEqual(report["resource_closure"]["issues"], [])

    def test_script_loaded_by_uid_is_retained_and_unresolved_required_uid_blocks(self):
        self.put("data/helper.gd", 'extends RefCounted\n')
        self.put("data/helper.gd.uid", "uid://dhelperfixture\n")
        story = (self.root / "autoload/story.gd").read_text()
        self.put("autoload/story.gd", story + 'const HELPER=preload("uid://dhelperfixture")\nconst BAD=preload("uid://dunknownfixture")\n')
        self.commit()
        self.sha = self.git("rev-parse", "HEAD").strip()
        destination, report = self.prepare()
        self.assertTrue((destination / "project/data/helper.gd").is_file())
        self.assertTrue(any("unresolved required UID" in issue for issue in report["resource_closure"]["issues"]))

    def test_root_icon_import_settings_are_committed_inputs(self):
        self.specs["runtime_files"].append("icon.png")
        self.put("tools/release/campaign_specs.json", json.dumps(self.specs))
        self.put("icon.png", "fixture image")
        self.put("icon.png.import", 'source_file="res://icon.png"\n')
        self.commit()
        self.sha = self.git("rev-parse", "HEAD").strip()
        destination, report = self.prepare()
        self.assertTrue((destination / "project/icon.png.import").is_file())
        self.assertIn("icon.png.import", {f["path"] for f in report["files"]})

    def test_import_cache_is_sealed_and_later_corruption_is_detected(self):
        destination, report = self.prepare()
        cache = destination / "project/.godot/imported/a.res"
        cache.parent.mkdir(parents=True)
        cache.write_bytes(b"generated fixture")
        (destination / "project/.godot/.gdignore").write_bytes(b"")
        build.write_json(destination / "import-receipt.json", {"kind": "unit-test-fixture"})
        integrity = build.seal_import(destination, report)
        self.assertEqual(len(integrity["generated_files"]), 2)
        build.verify_stage(destination)
        cache.write_bytes(b"corrupted fixture")
        with self.assertRaisesRegex(audit.AuditError, "generated import input changed"):
            build.verify_stage(destination)

    def test_import_cannot_change_committed_uid_or_generate_arbitrary_source(self):
        destination, report = self.prepare()
        build.write_json(destination / "import-receipt.json", {"kind": "unit-test-fixture"})
        (destination / "project/data/new.py").write_text("unexpected")
        with self.assertRaisesRegex(audit.AuditError, "unexpected generated"):
            build.seal_import(destination, report)
        (destination / "project/data/new.py").unlink()
        (destination / "project/autoload/story.gd.uid").write_text("uid://dchanged\n")
        with self.assertRaisesRegex(audit.AuditError, "editor changed committed input"):
            build.seal_import(destination, report)

    def test_editor_template_version_mismatch_is_rejected(self):
        templates = self.base / "templates"
        templates.mkdir()
        (templates / "version.txt").write_text("4.7.1.stable\n")
        result = subprocess.CompletedProcess([], 0, stdout="4.7.2.stable.official.fixture\n", stderr="")
        with patch.object(build.subprocess, "run", return_value=result), self.assertRaisesRegex(audit.AuditError, "version does not match"):
            build.engine_templates(self.base / "editor", templates)

    def test_forged_template_provenance_is_rejected(self):
        templates = self.base / "templates"
        templates.mkdir()
        (templates / "version.txt").write_text("4.7.2.stable\n")
        build.write_json(templates / "provenance.json", {"archive_sha256": "0" * 64, "url": "https://unknown.invalid/template"})
        result = subprocess.CompletedProcess([], 0, stdout="4.7.2.stable.official.fixture\n", stderr="")
        with patch.object(build.subprocess, "run", return_value=result), self.assertRaisesRegex(audit.AuditError, "provenance"):
            build.engine_templates(self.base / "editor", templates)


class PackIntegrityTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.path = Path(self.temp.name) / "fixture.pck"

    def tearDown(self):
        self.temp.cleanup()

    def inspect(self, data, required=None):
        self.path.write_bytes(data)
        return pack.inspect_pack(self.path, required=required)

    def test_valid_v4_pack_streams_all_payload_hashes(self):
        raw = b'{"fixture":true}'
        result = self.inspect(pck_bytes(), {"data/probe.json": hashlib.sha256(raw).hexdigest()})
        self.assertTrue(result["integrity_verified"])
        self.assertEqual(result["engine_version"], "4.7.2")
        self.assertFalse(result["native_windows_launch_verified"])

    def test_embedded_linux_footer_and_architecture_are_verified(self):
        elf = bytearray(64)
        elf[:4] = b"\x7fELF"
        elf[18:20] = struct.pack("<H", 62)
        pck = pck_bytes()
        result = self.inspect(bytes(elf) + pck + struct.pack("<Q4s", len(pck), b"GDPC"))
        self.assertTrue(result["embedded"])
        self.assertEqual(result["target"], "linux")

    def test_payload_corruption_same_size_fails_md5(self):
        raw = bytearray(pck_bytes())
        raw[104] ^= 1
        with self.assertRaisesRegex(audit.AuditError, "checksum mismatch"):
            self.inspect(raw)

    def test_truncated_and_oversized_directory_fields_are_rejected(self):
        raw = pck_bytes()
        for value in (raw[:-4], raw[:50]):
            with self.subTest(length=len(value)), self.assertRaises(audit.AuditError):
                self.inspect(value)
        raw = bytearray(pck_bytes())
        directory = struct.unpack_from("<Q", raw, 32)[0]
        struct.pack_into("<I", raw, directory + 4, 2**32 - 1)
        with self.assertRaisesRegex(audit.AuditError, "entry out of bounds"):
            self.inspect(raw)

    def test_unknown_engine_pack_version_and_encryption_are_rejected(self):
        for raw in (pck_bytes(engine=(4, 7, 1)), pck_bytes(version=99)):
            with self.assertRaisesRegex(audit.AuditError, "version"):
                self.inspect(raw)
        raw = bytearray(pck_bytes())
        struct.pack_into("<I", raw, 20, 3)
        with self.assertRaisesRegex(audit.AuditError, "flags"):
            self.inspect(raw)

    def test_duplicate_paths_and_traversal_are_rejected(self):
        for entries in ([('data/a.json', b'a'), ('data/a.json', b'b')], [('data/../escape', b'a')]):
            with self.subTest(entries=entries), self.assertRaises(audit.AuditError):
                self.inspect(pck_bytes(entries))

    def test_development_artifact_and_missing_required_json_are_rejected(self):
        with self.assertRaisesRegex(audit.AuditError, "development file"):
            self.inspect(pck_bytes([("tools/dev.json", b"{}")]))
        with self.assertRaisesRegex(audit.AuditError, "missing or changed"):
            self.inspect(pck_bytes(), {"data/later.json": "0" * 64})

    def test_out_of_bounds_and_overlapping_payloads_are_rejected(self):
        raw = bytearray(pck_bytes())
        directory = struct.unpack_from("<Q", raw, 32)[0]
        length = struct.unpack_from("<I", raw, directory + 4)[0]
        struct.pack_into("<Q", raw, directory + 8 + length, len(raw))
        with self.assertRaisesRegex(audit.AuditError, "payload out of bounds"):
            self.inspect(raw)
        raw = bytearray(pck_bytes([("data/a", b"1234"), ("data/b", b"5678")]))
        directory = struct.unpack_from("<Q", raw, 32)[0]
        length = struct.unpack_from("<I", raw, directory + 4)[0]
        second = directory + 8 + length + 36
        length2 = struct.unpack_from("<I", raw, second)[0]
        struct.pack_into("<Q", raw, second + 4 + length2, 0)
        with self.assertRaisesRegex(audit.AuditError, "overlapping"):
            self.inspect(raw)

    def test_actual_sparse_windows_file_at_4gib_boundary_is_rejected(self):
        with self.path.open("wb") as stream:
            stream.write(b"MZ\x00\x00")
            stream.truncate(1 << 32)
        with self.assertRaisesRegex(audit.AuditError, ">= 4 GiB"):
            pack.inspect_pack(self.path)


if __name__ == "__main__":
    unittest.main()
