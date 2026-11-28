#!/usr/bin/env python3
"""tools/bounded_run.sh 的檢查（NE-431）：log 有大小上限、執行有時間上限、停掉時連子程序一起停、不留背景程序。
用法：python -m unittest tools.test_bounded_run
"""
import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# Windows 上 subprocess 找 "bash" 會先找到 System32 的 WSL bash；用 PATH 上的（Git Bash；CI 是 /usr/bin/bash）。
BASH = shutil.which("bash") or "bash"


def bash(script, env_extra=None, timeout=60):
    env = dict(os.environ)
    env.update(env_extra or {})
    started = time.monotonic()
    result = subprocess.run([BASH, "-c", f"source tools/bounded_run.sh\n{script}"], cwd=ROOT, env=env,
                            capture_output=True, timeout=timeout)
    return result.returncode, result.stdout.decode("utf-8", "replace"), time.monotonic() - started


def alive(pid):
    code, out, _ = bash(f"kill -0 {pid} 2>/dev/null && echo alive || echo gone", timeout=10)
    return out.strip() == "alive"


class BoundedRunTest(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())

    def tearDown(self):
        for path in self.tmp.glob("*"):
            path.unlink(missing_ok=True)
        self.tmp.rmdir()

    def test_runaway_output_is_stopped_and_trimmed(self):
        log = (self.tmp / "spam.log").as_posix()
        code, out, took = bash(f'run_bounded "{log}" bash -c "yes spam-line"; echo "status=$?"', {"BOUNDED_LOG_MB": "1"})
        self.assertIn("status=124", out)
        size = Path(log).stat().st_size
        self.assertLess(size, 2 * 1024 * 1024, "the log is trimmed back near its limit (%d bytes)" % size)
        self.assertIn("BOUNDED_RUN: stopped (log exceeded 1 MB)", Path(log).read_text(errors="replace")[-400:])

    def test_overtime_run_is_stopped(self):
        log = (self.tmp / "slow.log").as_posix()
        code, out, took = bash(f'run_bounded "{log}" sleep 60; echo "status=$?"', {"BOUNDED_SECONDS": "2"})
        self.assertIn("status=124", out)
        self.assertLess(took, 20, "an overtime run stops close to its limit (%.1f s)" % took)

    def test_stopping_leaves_no_grandchild(self):
        log = (self.tmp / "tree.log").as_posix()
        pid_file = (self.tmp / "child.pid").as_posix()
        # 命令開一個背景孫程序再等它，模擬 Godot console 再開一個 Godot。
        script = f'run_bounded "{log}" bash -c "sleep 120 & echo \\$! > {pid_file}; wait"; echo "status=$?"'
        code, out, took = bash(script, {"BOUNDED_SECONDS": "2"})
        self.assertIn("status=124", out)
        child = Path(pid_file).read_text().strip()
        time.sleep(1)
        self.assertFalse(alive(child), "the grandchild process is stopped with its parent")

    def test_normal_run_keeps_its_exit_code_and_output(self):
        log = (self.tmp / "ok.log").as_posix()
        code, out, took = bash(f'run_bounded "{log}" bash -c "echo hello; exit 3"; echo "status=$?"')
        self.assertIn("status=3", out)
        self.assertEqual(Path(log).read_text().strip(), "hello")


if __name__ == "__main__":
    unittest.main()
