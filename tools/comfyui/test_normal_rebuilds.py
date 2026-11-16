"""CPU regression for recipe normal callbacks; no ComfyUI or Godot process is started."""
import contextlib
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import build_character as build


class NormalRebuildsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.work = self.root / 'art_src/characters/example'
        self.work.mkdir(parents=True)
        self.parts = self.root / 'art/characters/example/parts'
        self.parts.mkdir(parents=True)
        self.normal = self.parts / 'leg_n.png'
        self.character = build.Build.__new__(build.Build)
        self.character.id = 'example'
        self.character.char_dir = self.parts.parent
        self.character.recipe = {}
        self.root_patch = patch.object(build, 'ROOT', self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)
        self.output = contextlib.redirect_stdout(io.StringIO())
        self.output.__enter__()
        self.addCleanup(self.output.__exit__, None, None, None)

    def test_unregistered_recipe_keeps_standard_call_and_output(self):
        with patch.object(build, 'godot', return_value='standard done') as godot, patch.object(build, 'run') as run:
            self.assertEqual(self.character.step_normals(), [self.parts])
        godot.assert_called_once_with('--headless', 'res://tools/art/paint_normals.tscn', '--', '--only=example')
        run.assert_not_called()

    def test_invalid_sources_are_rejected_before_standard_normals(self):
        outside = self.root / 'outside.py'
        outside.write_text('raise AssertionError("must not execute")')
        wrong_type = self.work / 'callback.txt'
        wrong_type.write_text('pass')
        for item in ['outside.py', 'art_src/characters/example/../../../outside.py', str(outside), str(wrong_type), 'art_src/characters/example/missing.py']:
            with self.subTest(item=item), patch.object(build, 'godot') as godot, patch.object(build, 'run') as run:
                self.character.recipe = {'normal_rebuilds': [item]}
                with self.assertRaisesRegex(SystemExit, 'invalid registered normal rebuild'):
                    self.character.step_normals()
                godot.assert_not_called()
                run.assert_not_called()

    def test_malformed_registration_is_rejected(self):
        for value in ['callback.py', [None], ['']]:
            with self.subTest(value=value), patch.object(build, 'godot') as godot:
                self.character.recipe = {'normal_rebuilds': value}
                with self.assertRaisesRegex(SystemExit, 'normal_rebuilds must be a list'):
                    self.character.step_normals()
                godot.assert_not_called()

    def test_real_callback_executes_after_standard_normals(self):
        callback = self.work / 'normal.py'
        callback.write_text('from pathlib import Path\np=Path(' + repr(str(self.normal)) + ')\nassert p.read_text()=="standard"\np.write_text("registered")\nprint("custom done")\n')
        self.character.recipe = {'normal_rebuilds': [str(callback)]}
        def standard(*args):
            self.normal.write_text('standard')
            return 'standard done'
        with patch.object(build, 'godot', side_effect=standard):
            self.character.step_normals()
        self.assertEqual(self.normal.read_text(), 'registered')

    def test_callback_failure_is_propagated(self):
        callback = self.work / 'failure.py'
        callback.write_text('import sys\nprint("normal source rejected", file=sys.stderr)\nsys.exit(7)\n')
        self.character.recipe = {'normal_rebuilds': [str(callback)]}
        with patch.object(build, 'godot', return_value='standard done'):
            with self.assertRaisesRegex(SystemExit, 'registered normals.*failed'):
                self.character.step_normals()


if __name__ == '__main__':
    unittest.main()
