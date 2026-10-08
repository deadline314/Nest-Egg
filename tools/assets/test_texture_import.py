"""Import policy must preserve UIDs, avoid unrelated art and handle new output."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import texture_import
from PIL import Image


class ImportPolicyTest(unittest.TestCase):
    def test_minimum_prop_resolution_and_parallax_metadata(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for sub in ['art/environment/props', 'art/environment/backdrop', 'data/environment/themes', 'data/cutscene/stages']:
                (root / sub).mkdir(parents=True)
            for name in ['plant.png', 'plant_n.png', 'plant_glow.png']:
                Image.new('RGBA', (64, 32)).save(root / 'art/environment/props' / name)
            Image.new('RGBA', (256, 128)).save(root / 'art/environment/backdrop/sky.webp')
            (root / 'data/environment/plant.tres').write_text('texture = "res://art/environment/props/plant.png"\nsize = Vector2(14, 8)\n')
            theme = root / 'data/environment/themes/test.tres'
            theme.write_text('[sub_resource type="Resource" id="sky"]\ntexture = "res://art/environment/backdrop/sky.webp"\ntexture_scale = 2\n')
            stage = root / 'data/cutscene/stages/test.json'
            stage.write_text(json.dumps({'layers': [{'kind': 'sprite', 'path': 'res://art/environment/props/plant.png', 'scale': 0.25, 'pos': [10, 30]}]}))
            with patch.multiple(texture_import, ROOT=root, ART=root / 'art/environment'):
                texture_import.apply_policy()
                sprite = json.loads(stage.read_text())['layers'][0]
                self.assertEqual(sprite['source_width'], 64)
                self.assertEqual(sprite['pos'], [10, 30])
                self.assertEqual(sprite['scale'], 0.25)
                for name in ['plant.png', 'plant_n.png', 'plant_glow.png']:
                    self.assertIn('process/size_limit=0', (root / 'art/environment/props' / (name + '.import')).read_text())
                self.assertIn('source_width = 256', theme.read_text())
                self.assertEqual(texture_import.apply_policy(check=True), 0)

    def test_new_output_normal_and_scope(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            art = root / 'art/environment/props'
            art.mkdir(parents=True)
            policy = root / 'policy.json'
            policy.write_text(texture_import.POLICY.read_text())
            Image.new('RGBA', (64, 32)).save(art / 'new.png')
            Image.new('RGBA', (64, 32)).save(art / 'new_n.png')
            outside = root / 'art/characters'
            outside.mkdir()
            Image.new('RGBA', (64, 32)).save(outside / 'rin.png')
            with patch.multiple(texture_import, ROOT=root, ART=root / 'art/environment', POLICY=policy):
                self.assertEqual(texture_import.apply_policy(check=True), 2)
                self.assertFalse((art / 'new.png.import').exists())
                self.assertEqual(texture_import.apply_policy(), 2)
                self.assertIn('process/size_limit=32', (art / 'new_n.png.import').read_text())
                self.assertEqual(texture_import.apply_policy(check=True), 0)
                self.assertFalse((outside / 'rin.png.import').exists())

    def test_preserve_uid_and_unrelated_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'art/environment').mkdir(parents=True)
            image = root / 'art/environment/old.webp'
            Image.new('RGBA', (64, 32)).save(image)
            sidecar = image.with_name(image.name + '.import')
            sidecar.write_text('[remap]\nuid="uid://existing"\n[params]\ncompress/mode=2\nprocess/size_limit=0\n')
            with patch.multiple(texture_import, ROOT=root, ART=root / 'art/environment'):
                texture_import.apply_policy()
                text = sidecar.read_text()
                self.assertIn('uid="uid://existing"', text)
                self.assertIn('process/size_limit=0', text)
                self.assertIn('compress/mode=0', text)
                self.assertEqual(texture_import.apply_policy(), 0)


if __name__ == '__main__':
    unittest.main()
