"""Focused unit tests for the read-only campaign release audit prototype."""
from __future__ import annotations

import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import campaign_release as release


class CampaignReleaseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        (self.root / "autoload").mkdir()
        (self.root / "data" / "story").mkdir(parents=True)
        (self.root / "project.godot").write_text("[application]\n", encoding="utf-8")
        (self.root / "autoload" / "story.gd").write_text(
            'const CHAPTER_PATHS: Array[String] = [\n'
            '\t"res://data/story/one.json",\n'
            '\t"res://data/story/two.json",\n'
            "]\n",
            encoding="utf-8",
        )
        for name, count in (("one.json", 2), ("two.json", 3)):
            (self.root / "data" / "story" / name).write_text(
                json.dumps({"quests": [], "scenes": {f"s{i}": {} for i in range(count)}}),
                encoding="utf-8",
            )
        (self.root / "data" / "entry.tres").write_text("entry\n", encoding="utf-8")
        (self.root / "data" / "terminal.tres").write_text("terminal\n", encoding="utf-8")
        (self.root / "data" / "evidence.txt").write_text("accepted evidence\n", encoding="utf-8")
        self.specs = {
            "schema": 1,
            "runtime_roots": ["autoload", "data"],
            "runtime_files": ["project.godot"],
            "optional_missing": ["tools/dev_tools.json"],
            "chapters": [
                {
                    "id": "one",
                    "status": "accepted",
                    "acceptance_ticket": "NE-233",
                    "entry": "data/entry.tres",
                    "terminal": "data/terminal.tres",
                    "evidence": ["data/evidence.txt"],
                }
            ],
        }

    def tearDown(self) -> None:
        self.temp.cleanup()

    def test_local_path_rejects_traversal_absolute_and_hidden_paths(self) -> None:
        for raw in ("../outside.txt", "data/../../outside.txt", "C:/outside.txt", ".git/config", "data/.secret"):
            with self.subTest(raw=raw), self.assertRaises(release.AuditError):
                release.local_path(self.root, raw)

    def test_inventory_rejects_symlink(self) -> None:
        link = self.root / "data" / "linked.tres"
        # Exercise the audit's reparse-point branch on Windows hosts where
        # creating a real symlink may require privileges unavailable to tests.
        link.write_text("link sentinel", encoding="utf-8")
        real_check = Path.is_symlink

        def marked_link(path: Path) -> bool:
            return path == link or real_check(path)

        with patch.object(Path, "is_symlink", marked_link):
            with self.assertRaisesRegex(release.AuditError, "runtime link is unsupported"):
                release.inventory(self.root, self.specs)

    def test_fixed_reference_to_missing_file_is_reported(self) -> None:
        source = self.root / "data" / "refs.gd"
        source.write_text('const MISSING = "res://data/not_there.tres"\n', encoding="utf-8")
        files = release.inventory(self.root, self.specs)
        refs = release.scan_references(self.root, files, self.specs["optional_missing"])
        self.assertEqual([item["path"] for item in refs["missing"]], ["data/not_there.tres"])

    def test_fixed_reference_to_existing_but_unincluded_file_is_reported(self) -> None:
        outside_runtime_roots = self.root / "art"
        outside_runtime_roots.mkdir()
        (outside_runtime_roots / "sprite.png").write_bytes(b"fixture")
        (self.root / "data" / "refs.gd").write_text(
            'const IMAGE = "res://art/sprite.png"\n', encoding="utf-8"
        )
        files = release.inventory(self.root, self.specs)
        refs = release.scan_references(self.root, files, self.specs["optional_missing"])
        self.assertEqual(refs["missing"], [])
        self.assertEqual([item["path"] for item in refs["excluded"]], ["art/sprite.png"])

    def test_gd_comments_are_ignored_but_hash_inside_string_is_not_comment(self) -> None:
        source = self.root / "data" / "refs.gd"
        source.write_text(
            '# const A = "res://data/comment_only.tres"\n'
            'const HASH_TEXT = "res://data/#string_only.tres"\n'
            'const REAL = "res://data/entry.tres" # trailing res://data/also_comment.tres\n',
            encoding="utf-8",
        )
        files = release.inventory(self.root, self.specs)
        refs = release.scan_references(self.root, files, self.specs["optional_missing"])
        self.assertEqual([item["path"] for item in refs["missing"]], ["data/#string_only.tres"])
        self.assertEqual(refs["excluded"], [])

    def test_malformed_spec_fields_report_audit_error(self) -> None:
        self.specs["chapters"][0]["status"] = []
        with self.assertRaisesRegex(release.AuditError, "status"):
            release.validate_specs(self.specs)
        self.specs["chapters"][0]["status"] = "draft"
        self.specs["schema"] = True
        with self.assertRaisesRegex(release.AuditError, "schema"):
            release.validate_specs(self.specs)

    def test_formatted_dynamic_reference_is_listed_separately(self) -> None:
        (self.root / "data" / "refs.gd").write_text(
            'var path = "res://data/%s.tres" % item_id\n', encoding="utf-8"
        )
        refs = release.scan_references(
            self.root, release.inventory(self.root, self.specs), self.specs["optional_missing"]
        )
        self.assertEqual(refs["missing"], [])
        self.assertEqual(len(refs["dynamic"]), 1)
        self.assertEqual(refs["dynamic"][0]["path"], "data/%s.tres")

    def test_story_sources_reads_every_chapter_path_and_reports_counts(self) -> None:
        included = {item["path"] for item in release.inventory(self.root, self.specs)}
        sources = release.story_sources(self.root, included)
        self.assertEqual([item["path"] for item in sources], ["data/story/one.json", "data/story/two.json"])
        self.assertEqual([item["scenes"] for item in sources], [2, 3])

    def test_story_source_missing_from_inventory_is_an_error(self) -> None:
        included = {"autoload/story.gd", "data/story/one.json"}
        with self.assertRaisesRegex(release.AuditError, "loaded story source not included: data/story/two.json"):
            release.story_sources(self.root, included)

    def test_draft_chapter_never_becomes_ready(self) -> None:
        self.specs["chapters"][0]["status"] = "draft"
        with patch.object(release, "git_identity", return_value={"commit": "abc", "dirty": False}):
            report = release.audit(self.root, self.specs, "one")
        self.assertFalse(report["ready_for_export_review"])
        self.assertIn("chapter has not been accepted", report["chapters"][0]["issues"])

    def test_accepted_chapter_without_evidence_never_becomes_ready(self) -> None:
        self.specs["chapters"][0]["evidence"] = []
        with patch.object(release, "git_identity", return_value={"commit": "abc", "dirty": False}):
            report = release.audit(self.root, self.specs, "one")
        self.assertFalse(report["ready_for_export_review"])
        self.assertIn("no acceptance evidence supplied", report["chapters"][0]["issues"])

    def test_cli_report_is_created_once_and_existing_report_is_preserved(self) -> None:
        specs_path = self.root / "specs.json"
        specs_path.write_text(json.dumps(self.specs), encoding="utf-8")
        out = self.root / "reports" / "audit.json"
        argv = ["campaign_release.py", "--root", str(self.root), "--specs", str(specs_path), "--through", "one", "--out", str(out)]
        with patch.object(release, "git_identity", return_value={"commit": "abc", "dirty": False}), patch.object(
            release.sys, "argv", argv
        ), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(release.main(), 0)
        original = out.read_text(encoding="utf-8")
        self.assertTrue(json.loads(original)["ready_for_export_review"])
        with patch.object(release, "git_identity", return_value={"commit": "abc", "dirty": False}), patch.object(
            release.sys, "argv", argv
        ), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(release.main(), 1)
        self.assertEqual(out.read_text(encoding="utf-8"), original)


if __name__ == "__main__":
    unittest.main()
