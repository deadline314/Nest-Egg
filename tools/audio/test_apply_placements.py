"""套用「預計使用」工具的測試（NE-186）：用暫存資料夾裡的小資料，不動專案的檔案，也不重建音訊。

用法：python tools/audio/test_apply_placements.py
"""
import contextlib
import io
import json
import shutil
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import apply_placements as ap  # noqa: E402

HEADER = "| 位置 | 名稱 | 遊戲裡的位置 | 目前素材 | 預計使用 | 手動放入 | 備選素材 |\n|---|---|---|---|---|---|---|\n"


def row(slot, name, current, planned, manual="[ ]"):
    return f"| {slot} | {name} | 某處 | {current} | {planned} | {manual} | |\n"


class ApplyPlacementsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="test_audio_apply_"))
        self.addCleanup(shutil.rmtree, self.tmp, ignore_errors=True)
        (self.tmp / "weapons").mkdir()
        (self.tmp / "weapons" / "gun.tres").write_text('[resource]\nfire_sound = &"shot_gun"\n', encoding="utf-8")
        slots = [
            {"id": "P-WPN-001", "domain": "WPN", "kind": "sfx", "target": "shot_gun", "name": "槍射擊", "category": "GUN", "current": ["GUN-0001"], "proc": {"split": 2, "max_len": 0.7}},
            {"id": "P-WPN-002", "domain": "WPN", "kind": "sfx", "target": "shot_other", "name": "其他射擊", "category": "GUN", "current": ["GUN-0001"], "proc": {}},
            {"id": "P-HIT-001", "domain": "HIT", "kind": "sfx", "target": "hit_metal", "name": "命中金屬", "category": "IMP", "current": ["IMP-0001"]},
            {"id": "P-BGM-001", "domain": "BGM", "kind": "music", "target": "menu_dark", "name": "主選單", "category": "MUS", "current": ["MUS-0001"]},
            {"id": "P-HIT-002", "domain": "HIT", "kind": "sfx", "target": "hit_wood", "name": "命中木", "category": "IMP", "current": ["IMP-0001"]},
        ]
        (self.tmp / "slots.json").write_text(json.dumps({"slots": slots}, ensure_ascii=False), encoding="utf-8")
        assets = {f"GUN-000{i}": {"pack": "packA", "file": f"g{i}.wav", "dur": 1.0} for i in (1, 2, 3)}
        assets.update({"IMP-0001": {"pack": "packA", "file": "i1.wav", "dur": 0.5}, "IMP-0002": {"pack": "packA", "file": "i2.wav", "dur": 0.5},
                       "MUS-0001": {"pack": "packM", "file": "m1.mp3", "dur": 90.0}, "MUS-0002": {"pack": "packM", "file": "m2.mp3", "dur": 200.0}})
        (self.tmp / "catalog.json").write_text(json.dumps({"assets": assets}), encoding="utf-8")
        pipeline = {"sfx": {"shot_gun": {"category": "gun", "speeds": [1.25, 2.0], "choke_ms": 70, "variants": []}}, "music": {"menu_dark": {"pack": "packM", "file": "m1.mp3"}}}
        (self.tmp / "pipeline.json").write_text(json.dumps(pipeline), encoding="utf-8")
        self.doc = self.tmp / "PLACEMENTS.md"
        self.write_doc([row("P-WPN-001", "槍射擊", "GUN-0001", "GUN-0002、GUN-0003"), row("P-HIT-001", "命中金屬", "IMP-0001", "IMP-0002")])
        for name, value in {"SLOTS": self.tmp / "slots.json", "CATALOG": self.tmp / "catalog.json", "PIPELINE": self.tmp / "pipeline.json", "WEAPONS": self.tmp / "weapons"}.items():
            patcher = mock.patch.object(ap, name, value)
            patcher.start()
            self.addCleanup(patcher.stop)

    def write_doc(self, rows):
        self.doc.write_text(HEADER + "".join(rows), encoding="utf-8")

    def run_main(self, *args):
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.object(sys, "argv", ["apply_placements.py", "--doc", str(self.doc), *args]), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = ap.main()
        return code, out.getvalue(), err.getvalue()

    def test_plan_lists_changes_and_keeps_other_pipeline_keys(self):
        changes, problems, pipeline = ap.plan(self.doc)
        self.assertEqual([c["slot"] for c in changes], ["P-WPN-001", "P-HIT-001"])
        self.assertEqual(problems, [])
        gun = pipeline["sfx"]["shot_gun"]
        self.assertEqual([v["file"] for v in gun["variants"]], ["g2.wav", "g3.wav"])
        self.assertEqual((gun["speeds"], gun["choke_ms"], gun["variants"][0]["split"]), ([1.25, 2.0], 70, 2))

    def test_manual_same_and_empty_are_skipped(self):
        self.write_doc([row("P-WPN-001", "槍射擊", "GUN-0001", "GUN-0002", "[x]"), row("P-HIT-001", "命中金屬", "IMP-0001", "IMP-0001"), row("P-HIT-002", "命中木", "IMP-0001", "")])
        changes, problems, _ = ap.plan(self.doc)
        self.assertEqual((changes, problems), ([], []))

    def test_unknown_asset_and_unreadable_ids_are_problems(self):
        self.write_doc([row("P-WPN-001", "槍射擊", "GUN-0001", "GUN-9999、GUN-0002"), row("P-HIT-001", "命中金屬", "IMP-0001", "亂寫")])
        changes, problems, _ = ap.plan(self.doc)
        self.assertEqual(changes, [])
        self.assertTrue(any("GUN-9999" in p for p in problems) and any("看不出素材編號" in p for p in problems))

    def test_weapon_fire_sound_needs_two_variants(self):
        self.write_doc([row("P-WPN-001", "槍射擊", "GUN-0001", "GUN-0002"), row("P-WPN-002", "其他射擊", "GUN-0001", "GUN-0003")])
        changes, problems, _ = ap.plan(self.doc)
        by_slot = {c["slot"]: c for c in changes}
        self.assertTrue(by_slot["P-WPN-001"]["warnings"] and "2 個變體" in by_slot["P-WPN-001"]["warnings"][0])
        self.assertEqual(by_slot["P-WPN-002"]["warnings"], [])  # 不是任何武器的射擊音效
        self.assertEqual(problems, [])  # 警告在各位置的 warnings 裡，不重複算成問題

    def test_music_uses_the_first_id_and_warns(self):
        self.write_doc([row("P-BGM-001", "主選單", "MUS-0001", "MUS-0002、MUS-0001")])
        changes, _, pipeline = ap.plan(self.doc)
        self.assertEqual(changes[0]["warnings"][0].startswith("音樂位置只用第一個編號"), True)
        entry = pipeline["music"]["menu_dark"]
        self.assertEqual((entry["file"], entry["end"]), ("m2.mp3", 150.0))

    def test_only_filters_the_slots(self):
        changes, _, _ = ap.plan(self.doc, ["P-HIT-001"])
        self.assertEqual([c["slot"] for c in changes], ["P-HIT-001"])

    def test_dry_run_json_changes_nothing(self):
        before = (self.tmp / "pipeline.json").read_text(encoding="utf-8")
        code, out, _ = self.run_main("--dry-run", "--json")
        data = json.loads(out.strip().splitlines()[-1])
        self.assertEqual((code, [c["slot"] for c in data["changes"]]), (0, ["P-WPN-001", "P-HIT-001"]))
        self.assertTrue(out.isascii(), "--json 輸出只含 ASCII：Windows 上 Godot 用系統碼頁讀工具輸出，中文會亂碼")
        self.assertEqual(data["changes"][0]["name"], "槍射擊")
        self.assertEqual((self.tmp / "pipeline.json").read_text(encoding="utf-8"), before)

    def test_apply_writes_the_pipeline_and_the_result_file(self):
        result_file = self.tmp / "result.json"
        code, out, _ = self.run_main("--no-build", "--json", "--slots", "P-HIT-001", "--result", str(result_file))
        self.assertEqual(code, 0)
        result = json.loads(result_file.read_text(encoding="utf-8"))
        self.assertEqual((result["ok"], result["applied"], result["error"]), (True, ["P-HIT-001"], ""))
        pipeline = json.loads((self.tmp / "pipeline.json").read_text(encoding="utf-8"))
        self.assertEqual(pipeline["sfx"]["hit_metal"]["variants"][0]["file"], "i2.wav")
        self.assertEqual(pipeline["sfx"]["shot_gun"]["variants"], [])  # 沒勾的位置沒被動

    def test_nothing_to_apply_is_a_success(self):
        self.write_doc([row("P-HIT-001", "命中金屬", "IMP-0001", "IMP-0001")])
        result_file = self.tmp / "result.json"
        code, _, _ = self.run_main("--result", str(result_file))
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(result_file.read_text(encoding="utf-8"))["applied"], [])

    def test_a_broken_catalog_is_reported_not_raised(self):
        (self.tmp / "catalog.json").write_text("{ not json", encoding="utf-8")
        result_file = self.tmp / "result.json"
        code, out, _ = self.run_main("--dry-run", "--json", "--result", str(result_file))
        self.assertEqual(code, 1)
        self.assertIn("error", json.loads(out.strip().splitlines()[-1]))
        self.assertFalse(json.loads(result_file.read_text(encoding="utf-8"))["ok"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
