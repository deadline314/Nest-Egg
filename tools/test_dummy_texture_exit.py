"""Known original engine messages and fail-closed full-log integration."""
import pathlib
import subprocess
import sys
import tempfile
import unittest
from check_dummy_texture_exit import scan_logs

SCRIPT = pathlib.Path(__file__).with_name("check_dummy_texture_exit.py")
ORIGINAL = "ERROR: 1 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were leaked at exit.\n"


class FullTextureDiagnostics(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = pathlib.Path(self.directory.name)

    def cli(self, path=None):
        return subprocess.run([sys.executable, str(SCRIPT), str(path or self.root)],
                              capture_output=True, text=True)

    def test_original_zero_exit_style_message_fails_complete_log_check(self):
        (self.root / "shard_0.log").write_text("checks: 7, failures: 0\n" + ORIGINAL)
        result = self.cli()
        self.assertEqual(result.returncode, 1)
        self.assertIn("diagnostics=1", result.stdout)
        self.assertIn("shard_0.log:2:", result.stdout)

    def test_all_shards_are_checked_and_other_owners_keep_their_own_gate(self):
        (self.root / "shard_0.log").write_text("checks: 7, failures: 0\n")
        (self.root / "shard_1.log").write_text("ERROR: 1 RID allocations of type 'P11GodotArea2D' were leaked at exit.\n")
        self.assertEqual(self.cli().returncode, 0)
        (self.root / "shard_1.log").write_text(ORIGINAL)
        self.assertEqual(self.cli().returncode, 1)

    def test_missing_or_empty_logs_cannot_pass(self):
        self.assertNotEqual(self.cli().returncode, 0)
        self.assertNotEqual(self.cli(self.root / "missing").returncode, 0)
        with self.assertRaises(OSError):
            scan_logs([self.root / "missing.log"])

    def test_diagnostics_are_counted_without_unbounded_output(self):
        path = self.root / "shard_0.log"
        path.write_text(ORIGINAL * 100)
        count, samples = scan_logs([path])
        self.assertEqual(count, 100)
        self.assertEqual(len(samples), 32)


if __name__ == "__main__":
    unittest.main()
