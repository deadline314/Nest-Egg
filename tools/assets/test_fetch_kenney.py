"""Pinned assets must reject corrupt caches and unsupported licence evidence."""
import hashlib
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import fetch_assets


class KenneyFetchTest(unittest.TestCase):
    def test_corrupt_existing_cache_is_rejected(self):
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / 'model.glb'
            target.write_bytes(b'wrong')
            with self.assertRaisesRegex(IOError, 'cached sha256 mismatch'):
                fetch_assets.download('https://raw.githubusercontent.com/KenneyNL/test/x/a', target,
                                      sha256=hashlib.sha256(b'right').hexdigest())
            self.assertEqual(target.read_bytes(), b'wrong')

    def test_asset_cc0_evidence_required_before_model_download(self):
        entry = {'repo': 'KenneyNL/Starter-Kit-FPS', 'revision': 'a' * 40, 'asset': 'test',
                 'files': [{'path': 'models/a.glb', 'dest': 'a.glb', 'sha256': 'b' * 64}]}
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder)
            (target / 'SOURCE_README.md').write_text('MIT applies to software only. No asset licence.')
            calls = []
            with patch.object(fetch_assets, 'download', side_effect=lambda url, path, **kw: calls.append(url)):
                with self.assertRaisesRegex(ValueError, 'explicitly license'):
                    fetch_assets.fetch_kenney(entry, target)
            self.assertEqual(len(calls), 1)
            self.assertFalse((target / 'a.glb').exists())

    def test_mutable_revision_and_unsafe_destinations_are_rejected(self):
        for revision, dest in [('main', 'a.glb'), ('a' * 40, '../a.glb')]:
            entry = {'repo': 'KenneyNL/Starter-Kit-FPS', 'revision': revision,
                     'files': [{'path': 'models/a.glb', 'dest': dest, 'sha256': 'b' * 64}]}
            with patch.object(fetch_assets, 'download') as download:
                with self.assertRaises(ValueError):
                    fetch_assets.fetch_kenney(entry, Path('/unused'))
                download.assert_not_called()


if __name__ == '__main__':
    unittest.main()
