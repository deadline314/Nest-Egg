import contextlib
from datetime import datetime, timezone
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
from tempfile import TemporaryDirectory
import time
import unittest
from zipfile import ZipFile

from evidence_retention import PUBLISHED, RETENTION_DAYS, SECONDS_PER_DAY, sweep


class EvidenceRetentionTest(unittest.TestCase):
    def setUp(self):
        sandbox = TemporaryDirectory()
        self.addCleanup(sandbox.cleanup)
        self.parent = Path(sandbox.name).resolve()
        self.repo = self.parent / 'evidence-checkout'
        self.repo.mkdir()
        self.root = self.parent / '證據 evidence'
        self.root.mkdir()
        self.folder = self.root / 'evidence-delivered'
        self.old = time.time() - (RETENTION_DAYS + 3) * SECONDS_PER_DAY
        self.archive = self.repo / 'pm/Nest-Egg/attachments/NE-302/evidence.zip'
        self.archive.parent.mkdir(parents=True)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Evidence test')
        self.git('config', 'user.email', 'evidence@example.invalid')
        self.git('config', 'commit.gpgsign', 'false')

    def git(self, *args):
        env = os.environ.copy()
        date = datetime.fromtimestamp(self.old, timezone.utc).isoformat()
        env.update(GIT_AUTHOR_DATE=date, GIT_COMMITTER_DATE=date)
        return subprocess.check_output(['git', *args], cwd=self.repo, env=env).decode().strip()

    def add_archive(self, records, *, publish=True):
        with ZipFile(self.archive, 'w') as archive:
            for name, value in records.items():
                archive.writestr(name, value)
        return self.commit_archive(publish)

    def commit_archive(self, publish=True):
        self.git('add', 'pm')
        self.git('commit', '-qm', 'Record archived evidence')
        commit = self.git('rev-parse', 'HEAD')
        if publish:
            self.git('update-ref', PUBLISHED, commit)
        return commit

    def local(self, name, value, *, fresh=False, folder=None):
        path = (folder or self.folder) / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(value)
        if not fresh:
            os.utime(path, (self.old, self.old))
        return path

    def receipt(self, commit, *, fresh=False, folder=None):
        return self.local('publish/result.json', json.dumps({'commit': commit, 'main_origin_head_equal': True}).encode(),
                          fresh=fresh, folder=folder)

    def run_sweep(self, apply=True):
        output, diagnostics = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(diagnostics):
            code = sweep(self.repo, self.root, RETENTION_DAYS, apply)
        return code, output.getvalue(), diagnostics.getvalue()

    def test_dry_run_then_delete_byte_for_byte_match(self):
        commit = self.add_archive({'shards/舊.log': b'abc', 'changed.log': b'abc', 'fresh.log': b'abc'})
        receipt = self.receipt(commit)
        matching = self.local('shards/舊.log', b'abc')
        changed = self.local('changed.log', b'def')
        fresh = self.local('fresh.log', b'abc', fresh=True)
        unarchived = self.local('notes.txt', b'only local')
        self.archive.unlink()  # The verification worktree may not materialize the published ZIP.
        code, listing, errors = self.run_sweep(apply=False)
        self.assertEqual((0, ''), (code, errors))
        self.assertIn(str(matching), listing)
        self.assertTrue(matching.is_file())
        self.assertEqual(0, self.run_sweep()[0])
        self.assertFalse(matching.exists())
        self.assertTrue(all(path.is_file() for path in (changed, fresh, unarchived, receipt)))
        self.assertEqual((0, '', ''), self.run_sweep())

    def test_requires_the_same_archive_on_current_origin_main(self):
        original = self.add_archive({'sample.log': b'first'})
        replacement = self.add_archive({'sample.log': b'next'})
        self.receipt(original)
        stale_copy = self.local('sample.log', b'first')
        other = self.root / 'evidence-unpushed'
        unpublished = self.add_archive({'sample.log': b'candidate'}, publish=False)
        self.assertNotEqual(replacement, unpublished)
        self.receipt(unpublished, folder=other)
        waiting = self.local('sample.log', b'candidate', folder=other)
        unregistered = self.local('sample.log', b'next', folder=self.root/'evidence-in-progress')
        self.assertEqual((0, '', ''), self.run_sweep())
        self.assertTrue(all(path.is_file() for path in (stale_copy, waiting, unregistered)))

    def test_fresh_receipt_protects_old_bytes(self):
        self.receipt(self.add_archive({'old.log': b'abc'}), fresh=True)
        matching = self.local('old.log', b'abc')
        self.assertEqual((0, '', ''), self.run_sweep())
        self.assertTrue(matching.is_file())

    def test_root_can_contain_a_verification_worktree_without_cleaning_it(self):
        self.root = self.parent
        self.folder = self.root / 'evidence-delivered'
        commit = self.add_archive({'run.log': b'duplicate'})
        self.receipt(commit)
        self.receipt(commit, folder=self.repo)
        disposable = self.local('run.log', b'duplicate')
        protected = self.local('run.log', b'duplicate', folder=self.repo)
        self.assertEqual(0, self.run_sweep()[0])
        self.assertFalse(disposable.exists())
        self.assertTrue(protected.is_file())

    def test_path_traversal_case_collisions_and_nested_worktrees_are_ignored(self):
        commit = self.add_archive({'../outside.log': b'important', 'Case.LOG': b'same', 'case.log': b'same',
                                   'embedded/notes.log': b'important', 'valid.log': b'abc', 'file:stream': b'bad'})
        self.receipt(commit)
        protected = self.local('outside.log', b'important', folder=self.root)
        collision = self.local('case.log', b'same')
        git_file = self.local('embedded/.git', b'gitdir: ../other')
        nested = self.local('embedded/notes.log', b'important')
        valid = self.local('valid.log', b'abc')
        self.assertEqual(0, self.run_sweep()[0])
        self.assertTrue(all(path.is_file() for path in (protected, collision, git_file, nested)))
        self.assertFalse(valid.exists())

    def test_does_not_follow_directory_links(self):
        self.receipt(self.add_archive({'linked/file.log': b'important'}))
        outside = self.local('file.log', b'important', folder=self.parent/'external')
        link = self.folder / 'linked'
        if os.name == 'nt':
            env = dict(os.environ, NEST_EGG_TEST_LINK=str(link), NEST_EGG_TEST_DEST=str(outside.parent))
            subprocess.run(['powershell.exe','-NoProfile','-Command',
                            "$ErrorActionPreference='Stop'; New-Item -ItemType Junction -Path $env:NEST_EGG_TEST_LINK -Target $env:NEST_EGG_TEST_DEST | Out-Null"],
                           env=env,check=True,capture_output=True)
            self.addCleanup(link.rmdir)
        else:
            link.symlink_to(outside.parent, target_is_directory=True)
        self.assertEqual((0, '', ''), self.run_sweep())
        self.assertTrue(outside.is_file())

    def test_corrupt_archive_reports_context_and_preserves_original(self):
        self.archive.write_bytes(b'corrupted archive')
        self.receipt(self.commit_archive())
        local = self.local('only.log', b'local evidence')
        code, output, errors = self.run_sweep()
        self.assertEqual((1, ''), (code, output))
        self.assertIn('evidence-delivered', errors)
        self.assertIn('attachments/NE-302/evidence.zip', errors)
        self.assertTrue(local.is_file())

    def test_affected_runner_cleans_before_handling_no_affected_suites(self):
        executable = shutil.which('bash')
        git_path = shutil.which('git')
        if os.name == 'nt' and git_path:
            git_bash = Path(git_path).parent.parent / 'bin' / 'bash.exe'
            if git_bash.is_file():
                executable = str(git_bash)
        if executable is None:
            self.skipTest('Bash is unavailable')
        self.receipt(self.add_archive({'run.log': b'abc'}))
        removable = self.local('run.log', b'abc')
        tool_dir = self.repo / 'tools'
        tool_dir.mkdir()
        source_dir = Path(__file__).resolve().parent
        for name in ('run_tests_changed.sh', 'evidence_retention.py'):
            (tool_dir / name).write_bytes((source_dir / name).read_bytes().replace(b'\r\n', b'\n'))
        (tool_dir / 'select_tests.py').write_text('print("")\n', encoding='utf-8')
        self.git('config', 'nestegg.evidenceRoot', self.root.as_posix())
        env = dict(os.environ, PATH=str(Path(sys.executable).parent) + os.pathsep + os.environ.get('PATH', ''),
                   PYTHONUTF8='1')
        result = subprocess.run([executable, 'tools/run_tests_changed.sh'], cwd=self.repo, env=env,
                                capture_output=True, text=True, encoding='utf-8', timeout=30)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertFalse(removable.exists(), result.stdout + result.stderr)
        self.assertIn('沒有受影響的測試要跑', result.stdout)
        self.receipt('invalid',folder=self.root/'evidence-damaged')
        result = subprocess.run([executable, 'tools/run_tests_changed.sh'], cwd=self.repo, env=env,
                                capture_output=True, text=True, encoding='utf-8', timeout=30)
        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn('evidence-damaged', result.stderr)
        self.assertIn('繼續執行受影響測試', result.stderr)
        self.assertIn('沒有受影響的測試要跑', result.stdout)


if __name__ == '__main__':
    unittest.main()
