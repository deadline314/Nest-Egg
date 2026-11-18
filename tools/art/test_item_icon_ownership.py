"""An older icon producer must not overwrite adopted weapon artwork."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
from PIL import Image
import build_item_icons as icons


class ItemIconOwnership(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.pipeline = self.root/'assets_src/pipeline/melee_weapons.json'
        self.runtime = self.root/'data/weapon_art/melee.json'
        for path, data in [(self.pipeline, {'weapons': [{'id': 'fixture_weapon', 'profile': 'pistol'}]}),
                           (self.runtime, {'weapons': {'fixture_weapon': {}}})]:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps(data), encoding='utf-8')
        self.icon_dir = self.root/'icons'
        self.icon_dir.mkdir()
        for suffix in icons.SIZES:
            Image.new('RGBA', (2,2), 'red').save(self.icon_dir/('pistol'+suffix+'.png'))
        self.settings = patch.multiple(icons, ROOT=str(self.root), ICON_DIR=str(self.icon_dir), WORLD_DIR=str(self.root/'world'))
        self.settings.start()

    def tearDown(self):
        self.settings.stop()
        self.directory.cleanup()

    def test_adopted_weapon_keeps_both_existing_icons(self):
        original = {path.name:path.read_bytes() for path in self.icon_dir.iterdir()}
        with patch.object(icons, 'render', side_effect=AssertionError('wrong producer')), contextlib.redirect_stdout(io.StringIO()):
            icons.main(['pistol'])
        self.assertEqual(original, {path.name:path.read_bytes() for path in self.icon_dir.iterdir()})

    def test_planned_weapon_still_uses_original_vector_producer(self):
        self.runtime.write_text('{"weapons":{}}', encoding='utf-8')
        with contextlib.redirect_stdout(io.StringIO()):
            icons.main(['pistol'])
        with Image.open(self.icon_dir/'pistol_hd.png') as image:
            self.assertEqual(image.size, (384,384))

    def test_bad_ownership_data_refuses_without_overwriting_icons(self):
        original = {path.name:path.read_bytes() for path in self.icon_dir.iterdir()}
        self.pipeline.write_text('{', encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'melee_weapons.json'):
            icons.main(['pistol'])
        self.assertEqual(original, {path.name:path.read_bytes() for path in self.icon_dir.iterdir()})

    def test_missing_adopted_icon_names_the_actual_producer(self):
        (self.icon_dir/'pistol_hd.png').unlink()
        original = (self.icon_dir/'pistol.png').read_bytes()
        with self.assertRaisesRegex(FileNotFoundError, 'tools/assets/melee_art.py'):
            icons.main(['pistol'])
        self.assertEqual(original, (self.icon_dir/'pistol.png').read_bytes())

    def test_duplicate_adopted_profile_is_rejected(self):
        data = json.loads(self.pipeline.read_text(encoding='utf-8'))
        data['weapons'].append(dict(data['weapons'][0]))
        self.pipeline.write_text(json.dumps(data), encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'duplicate icon profile pistol'):
            icons.main(['pistol'])

    def test_missing_adopted_outputs_restore_registered_masters(self):
        sources = {}
        for suffix, size in icons.SIZES.items():
            path = self.root/'masters'/('pistol'+suffix+'.png')
            path.parent.mkdir(exist_ok=True)
            Image.new('RGBA', (size,size), 'blue').save(path)
            sources[suffix] = path.relative_to(self.root).as_posix()
            (self.icon_dir/('pistol'+suffix+'.png')).unlink()
        self.pipeline.write_text(json.dumps({'weapons':[{'id':'fixture_weapon','profile':'pistol','icon_sources':sources}]}), encoding='utf-8')
        with contextlib.redirect_stdout(io.StringIO()):
            icons.main(['pistol'])
        for suffix in icons.SIZES:
            with Image.open(self.icon_dir/('pistol'+suffix+'.png')) as actual, Image.open(self.root/sources[suffix]) as expected:
                self.assertEqual(actual.tobytes(), expected.tobytes())

    def test_icon_master_cannot_escape_the_project(self):
        (self.icon_dir/'pistol_hd.png').unlink()
        self.pipeline.write_text(json.dumps({'weapons':[{'id':'fixture_weapon','profile':'pistol','icon_sources':{'_hd':'../outside.png'}}]}), encoding='utf-8')
        with self.assertRaisesRegex(ValueError, 'inside the project'):
            icons.main(['pistol'])


if __name__ == '__main__':
    unittest.main()
