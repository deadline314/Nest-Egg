"""Check OS lock exclusion and the common lock path used by linked worktrees."""
import subprocess
import sys
import unittest
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent


class GpuLockTest(unittest.TestCase):
    def test_exclusion_and_release(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        lock_path = str(Path(temporary.name) / "comfy.lock")
        prefix = f"import sys; from pathlib import Path; sys.path.insert(0, {str(HERE)!r}); import comfy_guard; comfy_guard.LOCK_PATH=Path({lock_path!r}); "
        holder = subprocess.Popen([sys.executable, '-u', '-c', prefix +
            "\nwith comfy_guard.server_lock():\n print('locked', flush=True)\n input()"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        contender = None
        try:
            self.assertEqual(holder.stdout.readline().strip(), 'locked')
            contender = subprocess.Popen([sys.executable, '-u', '-c', prefix +
                "\nwith comfy_guard.server_lock():\n print('acquired', flush=True)"],
                stdout=subprocess.PIPE, text=True)
            with self.assertRaises(subprocess.TimeoutExpired):
                contender.communicate(timeout=0.3)
            holder.communicate('\n', timeout=5)
            output, _ = contender.communicate(timeout=6)
            self.assertIn('acquired', output)
            self.assertEqual(contender.returncode, 0)
        finally:
            for process in [holder, contender]:
                if process is not None and process.poll() is None:
                    process.kill()
                    process.wait()

    def test_common_checkout(self):
        import comfy_guard
        common = subprocess.check_output(['git', 'rev-parse', '--path-format=absolute',
                                          '--git-common-dir'], cwd=HERE, text=True).strip()
        self.assertEqual(comfy_guard.LOCK_PATH, Path(common).parent / 'assets_src/work/comfy.lock')


if __name__ == '__main__':
    unittest.main()
