"""受影響測試挑選工具（tools/select_tests.py）與 tools/run_tests_changed.sh 的測試（NE-263）。

在暫存資料夾建一個小 git repo，不動專案本身：
  - 檔名含中文、系統編碼是 cp950（繁中 Windows）時仍能正確挑選
  - git 指令失敗、基準不存在、工具當掉時以失敗結束，不會當成「沒有受影響的測試」
  - 只改文件或票時仍回報沒有受影響的測試並以成功結束
用法：python tools/test_select_tests.py（殼層腳本的測試需要 bash 與 git；沒有時略過）
"""
import contextlib
import io
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parent))
import select_tests as st  # noqa: E402

TOOLS = Path(__file__).resolve().parent
HAVE_GIT = shutil.which("git") is not None
HAVE_BASH = shutil.which("bash") is not None
CHINESE_CODE = "game/道具/中文道具.gd"
CHINESE_TICKET = "pm/Nest-Egg/[NE-1]中文票.md"


def git(repo, *args):
    subprocess.run(["git", *args], cwd=repo, check=True, capture_output=True)


def write(repo, rel, text):
    path = Path(repo) / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def make_repo(root):
    """一個最小的專案：一個中文檔名的遊戲程式、一個用到它的測試套件、一張中文檔名的票。回傳基準 commit。"""
    git(root, "init", "-q")
    for key, value in (("user.name", "Test"), ("user.email", "test@example.com"), ("core.quotepath", "false"), ("core.autocrlf", "false")):
        git(root, "config", key, value)
    write(root, "project.godot", "[application]\n")
    write(root, CHINESE_CODE, "extends Node\nvar power := 1\n")
    write(root, "tests/suite/prop_suite.gd", 'class_name PropSuite\nextends Node\nconst PROP := preload("res://game/道具/中文道具.gd")\n')
    write(root, "tests/suite/other_suite.gd", "class_name OtherSuite\nextends Node\n")
    write(root, CHINESE_TICKET, "# 票\n")
    git(root, "add", "-A")
    git(root, "commit", "-q", "-m", "init")
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, check=True, capture_output=True, text=True).stdout.strip()


# 在子程序裡模擬繁中 Windows：關掉 UTF-8 模式、系統編碼回報 cp950，再照常執行挑選工具。
CP950_PRELUDE = (
    "import locale, runpy, sys\n"
    "locale.getencoding = locale.getpreferredencoding = lambda *a: 'cp950'\n"
    "sys.argv = sys.argv[1:]\n"
    "runpy.run_path(sys.argv[0], run_name='__main__')\n"
)


def run_cli_cp950(root, *argv):
    """以 cp950 為系統編碼執行 root 底下那份 select_tests.py，回傳（結束代碼, stdout, stderr）。"""
    env = {k: v for k, v in os.environ.items() if k not in ("PYTHONUTF8", "PYTHONIOENCODING")}
    result = subprocess.run([sys.executable, "-X", "utf8=0", "-c", CP950_PRELUDE, str(Path(root) / "tools" / "select_tests.py"), *argv], cwd=root, capture_output=True, env=env)
    return result.returncode, result.stdout.decode("utf-8", "replace").strip(), result.stderr.decode("utf-8", "replace")


def copy_tools(root):
    (Path(root) / "tools").mkdir(exist_ok=True)
    for name in ("run_tests_changed.sh", "select_tests.py"):
        shutil.copy(TOOLS / name, Path(root) / "tools" / name)


def run_main(*argv):
    """在目前的 ROOT 上執行 select_tests.main()，回傳（結束代碼, stdout, stderr）。"""
    out, err = io.StringIO(), io.StringIO()
    with mock.patch.object(sys, "argv", ["select_tests.py", *argv]), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
        code = st.main()
    return code, out.getvalue().strip(), err.getvalue()


@unittest.skipUnless(HAVE_GIT, "需要 git")
class SelectTestsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.addCleanup(self.tmp.cleanup)
        copy_tools(self.root)
        self.base = make_repo(self.root)
        for patch in (mock.patch.object(st, "ROOT", self.root), mock.patch.object(st, "_files_cache", None)):
            patch.start()
            self.addCleanup(patch.stop)

    def test_chinese_paths_are_listed(self):
        files = st.tracked_files()
        self.assertIn(CHINESE_CODE, files)
        self.assertNotIn(CHINESE_TICKET, files, "pm/ 仍要排除")
        write(self.root, CHINESE_TICKET, "# 改過的票\n")
        self.assertIn(CHINESE_TICKET, st.changed_files(self.base))

    def test_changed_chinese_code_selects_its_suite_under_cp950(self):
        write(self.root, CHINESE_CODE, "extends Node\nvar power := 2\n")
        self.assertEqual(run_cli_cp950(self.root, "--base", self.base), (0, "PropSuite", ""))

    def test_paths_survive_default_quotepath(self):
        """core.quotePath 預設開啟時 git 會把中文檔名加上引號與跳脫；挑選結果不能因此改變。"""
        git(self.root, "config", "core.quotepath", "true")
        write(self.root, CHINESE_CODE, "extends Node\nvar power := 3\n")
        self.assertEqual(run_main("--base", self.base)[:2], (0, "PropSuite"))

    def test_only_ticket_changed_selects_nothing_under_cp950(self):
        write(self.root, CHINESE_TICKET, "# 改過的票\n")
        self.assertEqual(run_cli_cp950(self.root, "--base", self.base), (0, "", ""))

    def test_missing_base_fails_with_reason(self):
        code, out, err = run_main("--base", "不存在的基準")
        self.assertEqual(code, 2)
        self.assertEqual(out, "")
        self.assertIn("不存在的基準", err)

    def test_not_a_git_repo_fails_with_reason(self):
        with tempfile.TemporaryDirectory() as empty, mock.patch.object(st, "ROOT", Path(empty)):
            code, out, err = run_main("--base", "HEAD")
        self.assertEqual((code, out), (2, ""))
        self.assertIn("git 指令失敗", err)

    def test_git_not_installed_fails_with_reason(self):
        with mock.patch.object(st.subprocess, "run", side_effect=FileNotFoundError("git")):
            code, out, err = run_main("--base", self.base)
        self.assertEqual((code, out), (2, ""))
        self.assertIn("無法執行 git", err)


@unittest.skipUnless(HAVE_GIT and HAVE_BASH, "需要 git 與 bash")
class RunTestsChangedTest(unittest.TestCase):
    """用假的 run_tests_parallel.sh 記錄被要求跑哪些套件，只驗證挑選與結束代碼。"""

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        copy_tools(self.root)
        write(self.root, "tools/run_tests_parallel.sh", '#!/usr/bin/env bash\necho "RUN $*"\n')
        (self.root / "tools" / "run_tests_parallel.sh").chmod(0o755)
        self.base = make_repo(self.root)

    def run_script(self, *args):
        env = {k: v for k, v in os.environ.items() if k not in ("PYTHONUTF8", "PYTHONIOENCODING")}
        result = subprocess.run(["bash", "tools/run_tests_changed.sh", *args], cwd=self.root, capture_output=True, env=env)
        return SimpleNamespace(code=result.returncode, out=result.stdout.decode("utf-8", "replace"), err=result.stderr.decode("utf-8", "replace"))

    def test_code_change_runs_selected_suite(self):
        write(self.root, CHINESE_CODE, "extends Node\nvar power := 2\n")
        result = self.run_script(self.base)
        self.assertEqual(result.code, 0, result.err)
        self.assertIn("RUN --only=PropSuite", result.out)

    def test_ticket_only_change_reports_nothing_to_run(self):
        write(self.root, CHINESE_TICKET, "# 改過的票\n")
        result = self.run_script(self.base)
        self.assertEqual(result.code, 0, result.err)
        self.assertIn("沒有受影響的測試要跑", result.out)
        self.assertNotIn("RUN", result.out)

    def test_missing_base_fails(self):
        result = self.run_script("不存在的基準")
        self.assertNotEqual(result.code, 0)
        self.assertNotIn("沒有受影響的測試要跑", result.out)
        self.assertIn("不存在的基準", result.err)

    def test_selector_crash_fails(self):
        write(self.root, "tools/select_tests.py", 'raise RuntimeError("模擬挑選工具當掉")\n')
        result = self.run_script(self.base)
        self.assertNotEqual(result.code, 0)
        self.assertNotIn("沒有受影響的測試要跑", result.out)
        self.assertNotIn("RUN", result.out)
        self.assertIn("模擬挑選工具當掉", result.err)


if __name__ == "__main__":
    unittest.main()
