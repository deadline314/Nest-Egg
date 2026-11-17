"""Import policy must preserve UIDs, avoid unrelated art and handle new output."""
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
import texture_import
from PIL import Image


class ImportPolicyTest(unittest.TestCase):
    def test_stage_prop_states_keep_four_pixels_per_world_pixel_in_scoped_builds(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'art/items/world/paper.png'
            source.parent.mkdir(parents=True)
            Image.new('RGBA', (96, 96)).save(source)
            output = root / 'art/environment/scene_props/contact'
            output.mkdir(parents=True)
            for name in ['paper_lay.png', 'paper_lay_n.png', 'paper_lay_glow.png']:
                Image.new('RGBA', (96, 192)).save(output / name)
            Image.new('RGBA', (32, 32)).save(output / 'unused.png')
            backdrop = root / 'art/environment/backdrop/sky.webp'
            backdrop.parent.mkdir(parents=True)
            Image.new('RGBA', (2048, 512)).save(backdrop)
            stage = root / 'data/cutscene/stages/contact.json'
            stage.parent.mkdir(parents=True)
            authored = {'layers': [{'kind': 'sprite', 'path': 'res://art/environment/backdrop/sky.webp',
                                   'source_width': 2048, 'scale': .5},
                                  {'kind': 'sprite', 'path': 'res://art/items/world/paper.png',
                                   'source_width': 96, 'scale': 18.5 / 96,
                                   'states': {'lay': {'path': 'res://art/environment/scene_props/contact/paper_lay.png'}}}]}
            stage.write_text(json.dumps(authored))
            with patch.multiple(texture_import, ROOT=root, ART=root / 'art/environment'):
                texture_import.apply_policy()
                for name in ['paper_lay.png', 'paper_lay_n.png', 'paper_lay_glow.png']:
                    self.assertIn('process/size_limit=0', (output / (name + '.import')).read_text())
                self.assertIn('process/size_limit=16', (output / 'unused.png.import').read_text())
                self.assertIn('process/size_limit=1024', backdrop.with_name('sky.webp.import').read_text())
                self.assertEqual(json.loads(stage.read_text()), authored)
                self.assertEqual(texture_import.apply_policy(check=True), 0)
            with patch.multiple(texture_import, ROOT=root, ART=output):
                self.assertEqual(texture_import.apply_policy(check=True), 0)

    def test_authored_contact_canvas_survives_art_resize(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            art = root / 'art/environment/props'
            art.mkdir(parents=True)
            image = art / 'contact.png'
            Image.new('RGBA', (64, 32)).save(image)
            stage = root / 'data/cutscene/stages/contact.json'
            stage.parent.mkdir(parents=True)
            authored = {'layers': [{'kind': 'sprite', 'path': 'res://art/environment/props/contact.png',
                                   'source_width': 32, 'scale': .25, 'pos': [10, 30],
                                   'region': [0, 0, 32, 16], 'pivot': [4, 8]}]}
            stage.write_text(json.dumps(authored))
            theme = root / 'data/environment/themes/contact.tres'
            theme.parent.mkdir(parents=True)
            theme.write_text('[sub_resource type="Resource" id="contact"]\ntexture = "res://art/environment/backdrop/contact.webp"\ntexture_scale = 2\nsource_width = 32\n')
            backdrop = root / 'art/environment/backdrop/contact.webp'
            backdrop.parent.mkdir(parents=True)
            Image.new('RGBA', (64, 32)).save(backdrop)
            with patch.multiple(texture_import, ROOT=root, ART=root / 'art/environment'):
                texture_import.apply_policy()
                self.assertEqual(json.loads(stage.read_text()), authored)
                self.assertIn('source_width = 32', theme.read_text())
                Image.new('RGBA', (128, 64)).save(image)
                Image.new('RGBA', (128, 64)).save(backdrop)
                texture_import.apply_policy()
                self.assertEqual(json.loads(stage.read_text()), authored)
                self.assertIn('source_width = 32', theme.read_text())
                self.assertEqual(texture_import.apply_policy(check=True), 0)

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
