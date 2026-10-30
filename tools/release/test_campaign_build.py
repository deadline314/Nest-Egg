"""Failure-oriented CPU tests; real Godot export probes are separate evidence."""
from __future__ import annotations

import hashlib
import json
import os
import stat
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

import campaign_build as build
import campaign_release as audit
import pack_integrity as pack


def real_symlink(link: Path, target, *, directory=False) -> None:
    """Skip only the known Windows capability failure, never a rejection check."""
    try:
        link.symlink_to(target, target_is_directory=directory)
    except OSError as exc:
        if sys.platform == "win32" and getattr(exc, "winerror", None) == 1314:
            raise unittest.SkipTest(
                f"native Windows symlink unavailable (WinError 1314, no creation privilege): {link.name}; "
                "rejection assertion requires a real link; Linux coverage retained"
            ) from exc
        raise


def real_junction(link: Path, target: Path) -> None:
    """Create a real Windows junction with inherited permissions in the test temp."""
    if sys.platform != "win32":
        raise unittest.SkipTest("native Windows junction/reparse test; current host is not Windows")
    command = ["powershell.exe", "-NoProfile", "-NonInteractive", "-Command",
               "$ErrorActionPreference='Stop'; New-Item -ItemType Junction "
               "-Path $env:NE232_TEST_JUNCTION -Target $env:NE232_TEST_TARGET | Out-Null"]
    environment = {**os.environ, "NE232_TEST_JUNCTION": str(link), "NE232_TEST_TARGET": str(target)}
    result = subprocess.run(command, capture_output=True, text=True, env=environment, timeout=30)
    if result.returncode:
        raise AssertionError(f"native junction creation failed (exit {result.returncode}): {result.stdout}\n{result.stderr}")
    if not getattr(link.lstat(), "st_file_attributes", 0) & stat.FILE_ATTRIBUTE_REPARSE_POINT:
        raise AssertionError("created junction has no native reparse attribute")


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


def single_file(path: Path, payload: bytes) -> None:
    """A minimal embedded single file: x86_64 PE or ELF header, PCK payload, Godot footer."""
    header = bytearray(128)
    if path.suffix == ".exe":
        header[:2] = b"MZ"
        struct.pack_into("<I", header, 0x3C, 64)
        header[64:68] = b"PE\x00\x00"
        struct.pack_into("<H", header, 68, 0x8664)
    else:
        header[:4] = b"\x7fELF"
        struct.pack_into("<H", header, 18, 62)
    path.write_bytes(header + payload + struct.pack("<Q4s", len(payload), b"GDPC"))


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
        real_symlink(self.root / "data/link.tres", "entry.tres")
        self.git("config", "core.symlinks", "true")  # This disposable fixture repo only.
        self.commit()
        self.sha = self.git("rev-parse", "HEAD").strip()
        with self.assertRaisesRegex(audit.AuditError, "linked"):
            self.prepare()

    def test_output_parent_symlink_is_rejected(self):
        real = self.base / "real"
        real.mkdir()
        link = self.base / "linked"
        real_symlink(link, real, directory=True)
        with self.assertRaisesRegex(audit.AuditError, "linked output"):
            build.prepare(self.root, link, self.sha, "one", "test", self.policy)

    def test_native_windows_output_parent_junction_is_rejected(self):
        real = self.base / "junction-target"
        real.mkdir()
        link = self.base / "junction-output"
        real_junction(link, real)
        try:
            with self.assertRaisesRegex(audit.AuditError, "linked output"):
                build.prepare(self.root, link, self.sha, "one", "test", self.policy)
            self.assertEqual(list(real.iterdir()), [])
        finally:
            link.rmdir()  # Remove the junction itself, never recurse through target.

    def test_native_windows_staged_directory_junction_is_rejected(self):
        if sys.platform != "win32":
            self.skipTest("native Windows junction/reparse test; current host is not Windows")
        destination, _ = self.prepare()
        stage = destination / "project"
        real = stage / "original-data"
        (stage / "data").rename(real)
        link = stage / "data"
        real_junction(link, real)
        try:
            with self.assertRaisesRegex(audit.AuditError, "linked output"):
                build.verify_stage(destination)
            self.assertTrue((real / "story/one.json").is_file())
        finally:
            link.rmdir()

    def test_windows_symlink_privilege_skip_is_narrow(self):
        error = OSError("a required privilege is not held")
        error.winerror = 1314
        link = self.base / "fixture-link"
        with patch.object(Path, "symlink_to", side_effect=error), patch.object(sys, "platform", "win32"):
            with self.assertRaisesRegex(unittest.SkipTest, "WinError 1314"):
                real_symlink(link, "target")
        with patch.object(Path, "symlink_to", side_effect=error), patch.object(sys, "platform", "linux"):
            with self.assertRaises(OSError):
                real_symlink(link, "target")
        other = OSError("unexpected failure")
        other.winerror = 5
        with patch.object(Path, "symlink_to", side_effect=other), patch.object(sys, "platform", "win32"):
            with self.assertRaises(OSError):
                real_symlink(link, "target")

    def test_reparse_attribute_rejects_without_path_is_junction_api(self):
        sentinel = self.base / "reparse-sentinel"
        sentinel.mkdir()
        original = Path.lstat

        def reparse_lstat(path):
            info = original(path)
            return SimpleNamespace(st_mode=info.st_mode, st_file_attributes=0x400) if path == sentinel else info

        with patch.object(Path, "lstat", reparse_lstat), self.assertRaisesRegex(audit.AuditError, "linked output"):
            build.no_links(sentinel / "not-created")

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

    def add_edition_contract(self, order=("one",)):
        self.put("core/campaign_edition.gd", "class_name CampaignEdition\n")
        self.put("data/release/campaign.json", json.dumps({"schema": 1, "chapters": [{"id": i} for i in order]}))
        self.put("data/release/edition.json", json.dumps({"schema": 1, "through": ""}))
        self.specs["runtime_roots"] = ["autoload", "data", "core"]
        self.put("tools/release/campaign_specs.json", json.dumps(self.specs))
        self.commit()
        self.sha = self.git("rev-parse", "HEAD").strip()

    def test_missing_edition_contract_is_named_as_owner_blocker(self):
        _, report = self.prepare()
        blockers = report["readiness"]["owner_blockers"]
        self.assertTrue(any("not committed: data/release/campaign.json" in b for b in blockers))
        self.assertIsNone(report["edition"])

    def test_stage_carries_selected_edition_without_touching_repository(self):
        self.add_edition_contract()
        committed = (self.root / "data/release/edition.json").read_bytes()
        destination, report = self.prepare(version="v-test")
        staged = json.loads((destination / "project/data/release/edition.json").read_text())
        self.assertEqual((staged["through"], staged["source_sha"], staged["version"]), ("one", self.sha, "v-test"))
        self.assertEqual((self.root / "data/release/edition.json").read_bytes(), committed)
        self.assertEqual(report["edition"]["id"], "through-one")
        self.assertNotEqual(report["edition"]["committed_sha256"], report["edition"]["staged_sha256"])
        self.assertFalse(any("edition contract" in b for b in report["readiness"]["owner_blockers"]))
        build.verify_stage(destination)  # The staged override is the recorded input; verification still passes.
        (destination / "project/data/release/edition.json").write_text('{"schema": 1, "through": ""}')
        with self.assertRaisesRegex(audit.AuditError, "staged input changed: data/release/edition.json"):
            build.verify_stage(destination)

    def test_edition_order_mismatch_and_wrong_terminal_chapter_block(self):
        self.add_edition_contract(order=("other",))
        self.put("data/end.tres", '[gd_resource type="Resource" format=3]\n[resource]\nchapter = &"two"\n')
        self.commit()
        self.sha = self.git("rev-parse", "HEAD").strip()
        _, report = self.prepare()
        self.assertTrue(any("chapter order ['other'] differs" in b for b in report["readiness"]["owner_blockers"]))
        self.assertIn("terminal level chapter is 'two', expected 'one'", report["readiness"]["chapters"][0]["issues"])

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

    def test_windows_child_appdata_is_scoped_and_parent_environment_preserved(self):
        log = self.base / "windows-scope.log"
        command = [sys.executable, "-c", "import os; "
                   f"assert os.environ['APPDATA'] == {str(self.base / 'user/roaming')!r}; "
                   f"assert os.environ['LOCALAPPDATA'] == {str(self.base / 'user/local')!r}; "
                   "assert os.environ['HTTP_PROXY'] == 'test-proxy-sentinel'; "
                   "assert os.environ['SSL_CERT_FILE'] == 'test-ca-sentinel'; print('WINDOWS_SCOPE_PASS')"]
        sentinels = {"APPDATA": "parent-roaming", "LOCALAPPDATA": "parent-local",
                     "HTTP_PROXY": "test-proxy-sentinel", "SSL_CERT_FILE": "test-ca-sentinel"}
        with patch.dict(os.environ, sentinels), patch.object(sys, "platform", "win32"):
            before = dict(os.environ)
            build.run_logged(command, log, self.base)
            self.assertEqual(dict(os.environ), before)
        self.assertIn("WINDOWS_SCOPE_PASS", log.read_text())

    def test_pruned_script_basename_is_not_a_global_class(self):
        self.put("autoload/member.gd", "extends Node\nvar _radio_completion: Node\n")
        result = build.closure(self.root, [{"path": "autoload/member.gd"}],
                               [{"path": "game/radio_completion.gd"}], self.policy)
        self.assertEqual(result["issues"], [])

    def test_excluded_actual_global_class_reference_still_refuses(self):
        self.put("autoload/member.gd", "extends Node\nvar writer: MissingWriter\n")
        result = build.closure(self.root, [{"path": "autoload/member.gd"}],
                               [{"path": "core/missing_writer.gd", "global_class": "MissingWriter"}], self.policy)
        self.assertIn("excluded development class referenced: autoload/member.gd: MissingWriter", result["issues"])

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


    # --- NE-232 product/candidate export (engine mocked; real files, real PCK inspection) ---

    def candidate_stage(self, version="v1-candidate", contract=True):
        if contract:
            self.add_edition_contract()
        destination, report = self.prepare(version=version)
        build.write_json(destination / "import-receipt.json", {"kind": "unit-test-fixture"})
        build.seal_import(destination, report)
        return destination

    def fake_export_engine(self, extra=(), info=None):
        launches = []

        def run(command, log, cwd, timeout=900):
            if "--export-release" in command:
                entries = [(n, (cwd / n).read_bytes()) for n in (build.EDITION_DATA, build.CAMPAIGN_DATA)] + list(extra)
                single_file(Path(command[-1]), pck_bytes(entries))
                log.write_text("exit_code=0\n")
            else:
                launches.append(command)
                self.assertEqual([p.name for p in cwd.iterdir()], [Path(command[0]).name])  # Only the executable.
                value = info if info is not None else {"through": "one", "development": False, "issues": [], "version": "v1-candidate",
                                                         "chapters": [{"id": "one", "included": True}],
                                                         "first_level_included": True, "included_levels": {"one": 2}, "endings": []}
                log.write_text(("EDITION_INFO " + json.dumps(value) + "\n" if value else "") + "exit_code=0\n")
            return {"log": log.name, "exit_code": 0, "sha256": audit.digest(log)}
        return run, launches

    def export(self, destination, engine, candidate=True, host="linux"):
        native = {"target": host, "platform": "win32" if host == "windows" else "linux", "architecture": "x86_64"}
        with patch.object(build, "engine_templates", return_value={"test_only": True}), \
                patch.object(build, "run_logged", side_effect=engine), \
                patch.object(build, "native_export_host", return_value=native):
            return build.export(destination, self.base / "godot", self.base / "templates", candidate)

    def test_candidate_needs_a_visible_candidate_version(self):
        destination = self.candidate_stage(version="v1")
        engine, _ = self.fake_export_engine()
        with self.assertRaisesRegex(audit.AuditError, "-candidate"):
            self.export(destination, engine)
        self.assertFalse((destination / "artifacts").exists())

    def test_product_export_stays_blocked_for_draft_chapters(self):
        destination = self.candidate_stage(version="v1")
        engine, _ = self.fake_export_engine()
        with self.assertRaisesRegex(audit.AuditError, "formal chapter export blocked"):
            self.export(destination, engine, candidate=False)
        self.assertFalse((destination / "artifacts").exists())

    def test_candidate_export_records_everything_and_never_overwrites(self):
        destination = self.candidate_stage()
        engine, launches = self.fake_export_engine()
        receipt = self.export(destination, engine)
        self.assertEqual((receipt["kind"], receipt["is_release"], receipt["edition_id"]), ("campaign-candidate", False, "through-one"))
        self.assertFalse(receipt["native_windows_launch_verified"])
        self.assertTrue(receipt["readiness_blockers"])  # Draft chapter reasons stay visible on the candidate.
        self.assertEqual(sorted(receipt["artifacts"]), ["linux", "windows"])
        for target, item in receipt["artifacts"].items():
            path = destination / "artifacts" / item["file"]
            self.assertEqual((path.stat().st_size, audit.digest(path)), (item["bytes"], item["sha256"]))
            self.assertTrue(item["size_limit_ok"] and item["file"].startswith("NestEgg-v1-candidate-through-one."))
        self.assertTrue(receipt["linux_clean_launch"]["verified"] and len(launches) == 1 and "--edition-info" in launches[0])
        self.assertEqual(len((destination / "SHA256SUMS").read_text().splitlines()), 2)
        self.assertFalse((destination / "export-work").exists())
        build.verify_stage(destination)  # The verified stage itself is untouched by the export.
        before = (destination / "artifacts" / receipt["artifacts"]["windows"]["file"]).read_bytes()
        with self.assertRaisesRegex(audit.AuditError, "never overwritten"):
            self.export(destination, engine)
        self.assertEqual((destination / "artifacts" / receipt["artifacts"]["windows"]["file"]).read_bytes(), before)

    def test_windows_candidate_launches_only_exe_and_keeps_acceptance_pending(self):
        destination = self.candidate_stage()
        engine, launches = self.fake_export_engine()
        receipt = self.export(destination, engine, host="windows")
        self.assertEqual(len(launches), 1)
        self.assertTrue(launches[0][0].endswith(".exe"))
        self.assertEqual(Path(launches[0][0]).parent.name, "clean-launch-windows")
        self.assertTrue(receipt["windows_clean_launch"]["verified"])
        self.assertFalse(receipt["linux_clean_launch"]["verified"])
        self.assertIn("not run", receipt["linux_clean_launch"]["reason"])
        self.assertEqual(receipt["native_clean_launch"]["host"]["target"], "windows")
        self.assertFalse(receipt["native_windows_launch_verified"])
        self.assertFalse(receipt["chapter_acceptance_verified"])
        self.assertTrue(receipt["readiness_blockers"])
        self.assertEqual(json.loads((destination / "export-manifest.json").read_text()), receipt)
        self.assertEqual(len((destination / "SHA256SUMS").read_text().splitlines()), 2)
        build.verify_stage(destination)

    def test_windows_launch_failure_retains_artifacts_without_success_manifest(self):
        destination = self.candidate_stage()
        engine, launches = self.fake_export_engine(info={})
        with self.assertRaisesRegex(audit.AuditError, "did not report its edition"):
            self.export(destination, engine, host="windows")
        self.assertEqual(len(launches), 1)
        self.assertTrue(launches[0][0].endswith(".exe"))
        self.assertTrue((destination / "export-failure.json").is_file())
        self.assertFalse((destination / "export-manifest.json").exists())
        self.assertFalse((destination / "SHA256SUMS").exists())
        self.assertEqual(len(list((destination / "artifacts").iterdir())), 2)
        self.assertFalse((destination / "export-work").exists())

    def test_native_export_host_rejects_unsupported_platform_and_architecture(self):
        for host, machine in [("darwin", "arm64"), ("linux", "aarch64"), ("win32", "ARM64")]:
            with self.subTest(host=host, machine=machine), patch.object(build.sys, "platform", host), \
                    patch.object(build.platform, "machine", return_value=machine):
                with self.assertRaisesRegex(audit.AuditError, "unsupported native"):
                    build.native_export_host()
        for host, target, machine in [("linux", "linux", "x86_64"), ("win32", "windows", "AMD64")]:
            with self.subTest(host=host), patch.object(build.sys, "platform", host), \
                    patch.object(build.platform, "machine", return_value=machine):
                self.assertEqual(build.native_export_host(), {"target": target, "platform": host, "architecture": machine})

    def test_pack_entry_outside_the_stage_fails_and_keeps_a_failure_record(self):
        destination = self.candidate_stage()
        engine, _ = self.fake_export_engine(extra=[("data/unverified.json", b"{}")])
        with self.assertRaisesRegex(audit.AuditError, "outside the verified stage"):
            self.export(destination, engine)
        self.assertEqual(json.loads((destination / "export-failure.json").read_text())["is_release"], False)
        self.assertFalse((destination / "export-manifest.json").exists())

    def test_clean_launch_must_report_this_build_scope(self):
        bad = [{"through": "two", "development": False, "issues": [], "chapters": [{"id": "one", "included": True}],
                "first_level_included": True, "included_levels": {"one": 1}},
               {"through": "one", "development": False, "issues": [], "chapters": [{"id": "one", "included": True}],
                "first_level_included": True, "included_levels": {"one": 1}, "version": "other"},
               {"through": "one", "development": False, "issues": [], "chapters": [{"id": "one", "included": True}],
                "first_level_included": True, "included_levels": {"one": 1, "later": 3}},
               {}]
        self.add_edition_contract()
        for i, info in enumerate(bad):
            with self.subTest(info=info):
                destination = self.candidate_stage(version=f"v{i}-candidate", contract=False)
                engine, _ = self.fake_export_engine(info=info)
                with self.assertRaises(audit.AuditError):
                    self.export(destination, engine)
                self.assertFalse((destination / "export-manifest.json").exists())

    def test_pack_scope_accepts_engine_conversions_only(self):
        files = [{"path": p} for p in (".godot/imported/a.ctex", "project.binary", "data/entry.tres.remap",
                                        "icon.png.import", "data/story/one.json", "autoload/story.gdc", "data/new.json", "data/new.gdc")]
        self.assertEqual(build.pack_scope_issues(files, {"data/entry.tres", "icon.png", "data/story/one.json", "autoload/story.gd"}),
                         ["data/new.json", "data/new.gdc"])

class ProbePlatformTests(unittest.TestCase):
    """Mock the engine process only; use real files and the real PCK inspector."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.native_commands = []
        self.native_failure = False
        self.native_marker = True

    def tearDown(self):
        self.temp.cleanup()

    def fake_engine(self, command, log, cwd, timeout=900):
        if "--export-release" in command:
            path = Path(command[-1])
            payload = pck_bytes([("data/probe.json", (cwd / "data/probe.json").read_bytes()),
                                 ("data/dynamic/later.tres", (cwd / "data/dynamic/later.tres").read_bytes())])
            header = bytearray(128)
            if path.suffix == ".exe":
                header[:2] = b"MZ"
                struct.pack_into("<I", header, 0x3C, 64)
                header[64:68] = b"PE\x00\x00"
                struct.pack_into("<H", header, 68, 0x8664)
            else:
                header[:4] = b"\x7fELF"
                struct.pack_into("<H", header, 18, 62)
            path.write_bytes(header + payload + struct.pack("<Q4s", len(payload), b"GDPC"))
        elif "--import" not in command:
            self.native_commands.append((command, cwd))
            self.assertEqual([p.name for p in cwd.iterdir()], [Path(command[0]).name])
            if self.native_failure:
                log.write_text("SCRIPT ERROR: simulated native failure\nexit_code=1\n")
                raise audit.AuditError("simulated native failure; log retained")
        log.write_text("NE232_TOOL_PROBE_PASS\nexit_code=0\n" if self.native_marker else "exit_code=0\n")
        return {"log": log.name, "exit_code": 0, "sha256": audit.digest(log)}

    def probe(self, host):
        with patch.object(sys, "platform", host), patch.object(build.platform, "machine", return_value="AMD64"), \
                patch.object(build, "engine_templates", return_value={"test_only": True}), \
                patch.object(build, "run_logged", side_effect=self.fake_engine):
            return build.probe(self.base / "probe", self.base / "godot", self.base / "templates")

    def test_windows_probe_launches_only_exe_and_never_claims_native_linux(self):
        result = self.probe("win32")
        self.assertEqual(Path(self.native_commands[0][0][0]).name, "NE232_TOOL_PROBE.exe")
        self.assertEqual(len(self.native_commands), 1)
        self.assertFalse(result["native_linux_fixture_launch_verified"])
        self.assertTrue(result["native_windows_fixture_launch_verified"])
        self.assertTrue(result["native_windows_launch_verified"])
        self.assertFalse(result["artifacts"]["windows"]["native_windows_launch_verified"])
        self.assertEqual(result["native_launch"]["target"], "windows")
        self.assertFalse(result["is_campaign_product"])
        self.assertFalse(result["chapter_acceptance_verified"])
        self.assertTrue((self.base / "probe/native-windows.log").is_file())
        self.assertFalse((self.base / "probe/native-linux.log").exists())

    def test_linux_probe_launches_only_elf_and_never_claims_native_windows(self):
        result = self.probe("linux")
        self.assertEqual(Path(self.native_commands[0][0][0]).name, "NE232_TOOL_PROBE.x86_64")
        self.assertEqual(len(self.native_commands), 1)
        self.assertTrue(result["native_linux_fixture_launch_verified"])
        self.assertFalse(result["native_windows_fixture_launch_verified"])
        self.assertFalse(result["native_windows_launch_verified"])
        self.assertEqual(result["native_launch"]["target"], "linux")
        self.assertFalse((self.base / "probe/native-windows.log").exists())

    def test_native_failure_retains_log_and_never_writes_success_manifest(self):
        self.native_failure = True
        with self.assertRaisesRegex(audit.AuditError, "native failure"):
            self.probe("win32")
        destination = self.base / "probe"
        self.assertIn("SCRIPT ERROR", (destination / "native-windows.log").read_text())
        self.assertTrue((destination / "failure.json").is_file())
        self.assertFalse((destination / "probe-manifest.json").exists())
        self.assertFalse((destination / "checksums.sha256").exists())

    def test_zero_exit_without_runtime_assertions_is_rejected(self):
        self.native_marker = False
        with self.assertRaisesRegex(audit.AuditError, "without runtime assertions"):
            self.probe("win32")
        self.assertFalse((self.base / "probe/probe-manifest.json").exists())

    def test_unsupported_host_or_architecture_fails_before_output_reservation(self):
        for host, machine in (("darwin", "x86_64"), ("linux", "aarch64"), ("win32", "ARM64")):
            with self.subTest(host=host, machine=machine), patch.object(sys, "platform", host), \
                    patch.object(build.platform, "machine", return_value=machine), \
                    patch.object(build, "engine_templates") as templates, self.assertRaisesRegex(audit.AuditError, "native probe host"):
                build.probe(self.base / "probe", self.base / "godot", self.base / "templates")
            templates.assert_not_called()
            self.assertFalse((self.base / "probe").exists())


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
