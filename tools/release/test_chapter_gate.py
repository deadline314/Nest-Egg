"""chapter_gate 的測試：全部使用暫存的假 repo，不碰真實 pm/。"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import chapter_gate as cg  # noqa: E402

# 假票模板：內文與測試流程各有一個 - [ ]，都不該計入；第二個 Blocked by 也不該被讀到
TEMPLATE = """# [{code}] 測試票

> 狀態：{status}

## 內文

- [ ] 內文的待辦，不算驗收

### 驗收條件
{checks}

### 測試流程
- [ ] 這行不是驗收條件，不能計入

# 跟其他票的關係

- Blocked by：{blocked}

## 交接紀錄
- Blocked by：NE-999
"""


def write_ticket(root, folder, code, title, status, blocked="無", checks=("- [x] a", "- [ ] b")):
    d = root / "pm" / folder
    d.mkdir(parents=True, exist_ok=True)
    p = d / f"[{code}]{title}.md"
    p.write_text(
        TEMPLATE.format(code=code, status=status, checks="\n".join(checks), blocked=blocked),
        encoding="utf-8",
    )
    return p


class FakeRepoTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name)


class ParseTest(FakeRepoTest):
    def test_parse_reads_status_blockers_and_acceptance_only(self):
        p = write_ticket(self.root, "Nest-Egg", "NE-233", "驗收", "待辦", blocked="ST-16、ST-2", checks=("- [x] a", "- [ ] b", "- [ ] c"))
        info = cg.parse_ticket(p, self.root)
        self.assertEqual(info["status"], "待辦")
        self.assertEqual(info["blocked_by"], ["ST-16", "ST-2"])  # 不讀到交接紀錄裡的 NE-999
        self.assertEqual((info["checked"], info["unchecked"]), (1, 2))  # 內文與測試流程的 - [ ] 不計
        self.assertEqual(info["path"], "pm/Nest-Egg/[NE-233]驗收.md")

    def test_no_blockers_when_none(self):
        p = write_ticket(self.root, "Nest-Egg", "NE-233", "驗收", "待辦", blocked="無")
        self.assertEqual(cg.parse_ticket(p, self.root)["blocked_by"], [])


class GateTest(FakeRepoTest):
    def test_done_open_cancelled_blockers(self):
        write_ticket(self.root, "Nest-Egg", "NE-233", "驗收", "待辦", blocked="ST-16、ST-2、NE-178")
        write_ticket(self.root, "ST", "ST-16", "完成的票", "完成")
        write_ticket(self.root, "ST", "ST-2", "進行中的票", "進行中", checks=("- [x] a", "- [x] b", "- [ ] c"))
        write_ticket(self.root, "Nest-Egg", "NE-178", "取消的票", "取消")
        g = cg.gate(self.root, "NE-233")
        self.assertEqual({b["code"]: b["state"] for b in g["blockers"]}, {"ST-16": "done", "ST-2": "open", "NE-178": "done"})
        st2 = g["blockers"][1]
        self.assertEqual((st2["status"], st2["checked"], st2["unchecked"]), ("進行中", 2, 1))
        self.assertEqual(st2["paths"], ["pm/ST/[ST-2]進行中的票.md"])
        self.assertFalse(g["ready_to_verify"])

    def test_review_status_counts_as_done(self):
        write_ticket(self.root, "Nest-Egg", "NE-233", "驗收", "待辦", blocked="ST-16")
        write_ticket(self.root, "ST", "ST-16", "審查中的票", "審查中")
        g = cg.gate(self.root, "NE-233")
        self.assertEqual(g["blockers"][0]["state"], "done")
        self.assertTrue(g["ready_to_verify"])

    def test_status_remark_in_parentheses_is_still_done(self):
        write_ticket(self.root, "Nest-Egg", "NE-233", "驗收", "待辦", blocked="ST-16")
        write_ticket(self.root, "ST", "ST-16", "完成的票", "完成（倉庫過長另開 ST-14）")
        self.assertTrue(cg.gate(self.root, "NE-233")["ready_to_verify"])

    def test_none_blocker_means_ready(self):
        write_ticket(self.root, "Nest-Egg", "NE-233", "驗收", "待辦", blocked="無")
        g = cg.gate(self.root, "NE-233")
        self.assertEqual(g["blockers"], [])
        self.assertTrue(g["ready_to_verify"])

    def test_missing_blocker(self):
        write_ticket(self.root, "Nest-Egg", "NE-233", "驗收", "待辦", blocked="BG-99")
        g = cg.gate(self.root, "NE-233")
        self.assertEqual(g["blockers"], [{"code": "BG-99", "state": "missing", "status": "", "checked": 0, "unchecked": 0, "paths": []}])
        self.assertFalse(g["ready_to_verify"])

    def test_ambiguous_blocker_lists_all_paths(self):
        write_ticket(self.root, "Nest-Egg-BG", "BG-11", "背景包", "完成")
        write_ticket(self.root, "Nest-Egg-BG", "BG-11", "床", "完成")
        write_ticket(self.root, "Nest-Egg", "NE-233", "驗收", "待辦", blocked="BG-11")
        b = cg.gate(self.root, "NE-233")["blockers"][0]
        self.assertEqual(b["state"], "ambiguous")
        self.assertEqual(sorted(b["paths"]), ["pm/Nest-Egg-BG/[BG-11]床.md", "pm/Nest-Egg-BG/[BG-11]背景包.md"])
        self.assertFalse(cg.gate(self.root, "NE-233")["ready_to_verify"])

    def test_missing_or_ambiguous_ticket_raises(self):
        with self.assertRaisesRegex(ValueError, "NE-233"):
            cg.gate(self.root, "NE-233")
        write_ticket(self.root, "Nest-Egg", "NE-233", "驗收甲", "待辦")
        write_ticket(self.root, "Nest-Egg", "NE-233", "驗收乙", "待辦")
        with self.assertRaisesRegex(ValueError, "同號檔案"):
            cg.gate(self.root, "NE-233")

    def test_ne23_does_not_match_ne233(self):
        write_ticket(self.root, "Nest-Egg", "NE-23", "舊票", "完成")
        write_ticket(self.root, "Nest-Egg", "NE-233", "驗收", "待辦", blocked="NE-2")
        self.assertEqual([p.name for p in cg.find_tickets(self.root, "NE-23")], ["[NE-23]舊票.md"])
        self.assertEqual([p.name for p in cg.find_tickets(self.root, "NE-233")], ["[NE-233]驗收.md"])
        # NE-2 不應該命中 NE-23 或 NE-233
        self.assertEqual(cg.gate(self.root, "NE-233")["blockers"][0]["state"], "missing")
        # NE-23 完整比對得到
        write_ticket(self.root, "Nest-Egg", "NE-234", "下一章", "待辦", blocked="NE-23")
        self.assertEqual(cg.gate(self.root, "NE-234")["blockers"][0]["state"], "done")


class CliTest(FakeRepoTest):
    def run_cli(self, *args):
        cmd = [sys.executable, str(HERE / "chapter_gate.py"), *args, "--root", str(self.root)]
        return subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")

    def test_json_output_parses(self):
        write_ticket(self.root, "Nest-Egg", "NE-233", "驗收", "待辦", blocked="ST-16、BG-99")
        write_ticket(self.root, "ST", "ST-16", "完成的票", "完成")
        r = self.run_cli("NE-233", "--json")
        self.assertEqual(r.returncode, 0, r.stderr)
        data = json.loads(r.stdout)
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0]["ticket"], "NE-233")
        self.assertFalse(data[0]["ready_to_verify"])
        self.assertEqual([b["state"] for b in data[0]["blockers"]], ["done", "missing"])

    def test_text_output_summary(self):
        write_ticket(self.root, "Nest-Egg", "NE-233", "驗收", "待辦", blocked="ST-16、ST-2")
        write_ticket(self.root, "ST", "ST-16", "完成的票", "完成")
        write_ticket(self.root, "ST", "ST-2", "進行中的票", "進行中", checks=("- [x] a", "- [ ] b", "- [ ] c"))
        r = self.run_cli("NE-233")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(r.stdout.splitlines(), [
            "NE-233 待辦 1/2：還有 1 張擋住",
            "  ST-2 進行中 1/3 pm/ST/[ST-2]進行中的票.md",
        ])

    def test_text_output_ready(self):
        write_ticket(self.root, "Nest-Egg", "NE-233", "驗收", "待辦", blocked="無")
        r = self.run_cli("NE-233")
        self.assertEqual(r.stdout.splitlines(), ["NE-233 待辦 1/2：可開始驗收"])

    def test_missing_ticket_exits_2(self):
        r = self.run_cli("NE-404")
        self.assertEqual(r.returncode, 2)
        self.assertIn("NE-404", r.stderr)
        self.assertEqual(r.stdout, "")


if __name__ == "__main__":
    unittest.main()
