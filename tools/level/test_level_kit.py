"""CPU-only generator height/state contracts; never runs Godot or writes shipping data."""
import contextlib
import io
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import build_ch1 as kit
from level_kit import Grid, RouteState


class HeightTests(unittest.TestCase):
    def test_independent_height_and_default(self):
        tall = kit.Area('tower', 'Tower', 24, 43, height=48)
        short = kit.Area('short', 'Short', 24, 12, height=16)
        with patch.object(kit, 'H', 99):
            default = kit.Area('default', 'Default', 24, 20)
        self.assertEqual((tall.h, short.h, default.h), (48, 16, 24))
        self.assertEqual((tall.grid.h, short.grid.h, default.grid.h), (48, 16, 24))
        tall.put(3, 42, 'P')
        self.assertEqual(short.grid.at(3, 11), '.')
        self.assertEqual(tall.check(), [])

    def test_bounds_rejected_before_mutation(self):
        grid = Grid(8, 12)
        for x, y in ((-1, 0), (8, 0), (0, -1), (0, 12), (True, 0), (1.5, 0)):
            with self.subTest(point=(x, y)), self.assertRaises(ValueError):
                grid.put(x, y, '#')
        before = grid.rows()
        for rect in ((0, 8, 0, 5), (0, 5, -1, 5), (4, 2, 0, 5)):
            with self.subTest(rect=rect), self.assertRaises(ValueError):
                grid.fill(*rect, '#')
        self.assertEqual(before, grid.rows())
        for dimensions in ((0, 12), (8, 0), (8, -1), (8, 12.0), (True, 12)):
            with self.subTest(dimensions=dimensions), self.assertRaises(ValueError):
                Grid(*dimensions)
        with self.assertRaises(ValueError):
            kit.Area('bad', 'Bad', 10, 24, height=24)

    def test_slice_keeps_height_and_condition_coordinates(self):
        area = kit.Area('tower', 'Tower', 24, 43, height=48)
        area.put(9, 42, 'P')
        area.platform(4, 12, 31)
        area.route_gate('disk', (8, 8, 4, 42), flag='ledger_disk_obtained')
        area.route_platform('raft', (10, 12, 30, 30), mechanism='flood_c')
        cut = kit.slice_area(area, 'cut', 'Cut', 4, 18, 2, 2)
        self.assertEqual(cut.h, 48)
        self.assertEqual(cut.grid.at(7, 42), 'P')
        self.assertEqual(cut.grid.at(7, 31), '=')
        self.assertEqual(cut.route_gates[0]['rect'], (6, 6, 4, 42))
        self.assertEqual(cut.route_supports[0]['rect'], (8, 10, 30, 30))
        with self.assertRaisesRegex(ValueError, 'route region cut'):
            kit.slice_area(area, 'bad', 'Bad', 9, 11, 2, 2)

    def test_json_level_render_and_report_use_instance_height(self):
        area = kit.Area('tower', 'Tower', 24, 43, height=48)
        area.put(3, 42, 'P')
        area.combat = True
        with tempfile.TemporaryDirectory() as folder, contextlib.redirect_stdout(io.StringIO()) as output:
            area.grid.write('tower', (folder, 'map.json'))
            rows = json.loads((Path(folder) / 'map.json').read_text(encoding='utf8'))['segments'][0]
            self.assertEqual(len(rows), 48)
            self.assertEqual(rows[42][3], 'P')
            with patch.object(kit, 'LEVEL_DIR', folder):
                kit.write_level(area, theme=False, theme_path='res://data/environment/themes/ch1_street.tres')
            self.assertIn('height = 48', (Path(folder) / 'ch1_tower.tres').read_text(encoding='utf8'))
            # Pillow is optional in the generator; assert its public output
            # dimensions without introducing a new CI package dependency.
            image = Mock()
            image_api = Mock()
            image_api.new.return_value = image
            pillow = SimpleNamespace(Image=image_api, ImageDraw=Mock(), ImageFont=Mock())
            with patch.dict('sys.modules', {'PIL': pillow}):
                kit.render_overview([area], folder)
            image_api.new.assert_called_once_with('RGB', (24 * 6, 48 * 6 + 28), (18, 20, 28))
            image.save.assert_called_once_with(str(Path(folder) / 'ST-11-map-tower.png'))
            kit.report([area])
            self.assertIn('tower: 24x48', output.getvalue())


class RouteTests(unittest.TestCase):
    def setUp(self):
        self.area = kit.Area('test', 'Test', 30, 20)
        self.area.put(3, 19, 'P')
        self.target = [('exit', (25, 19))]

    def test_flags_mechanisms_and_abilities_block_without_implicit_open(self):
        for kind in ('flag', 'mechanism', 'ability'):
            with self.subTest(kind=kind):
                area = kit.Area(kind, kind, 30, 20)
                area.route_gate('door', (14, 15, 0, 19), **{kind: 'actual_condition'})
                facts = {'flags' if kind == 'flag' else 'mechanisms' if kind == 'mechanism' else 'abilities': {'actual_condition': False}}
                closed = RouteState('before', **facts)
                self.assertTrue(kit.reachable(area, (3, 19), self.target, state=closed))
                facts[next(iter(facts))]['actual_condition'] = True
                # The already-created snapshot must not change with its caller.
                self.assertTrue(kit.reachable(area, (3, 19), self.target, state=closed))
                self.assertEqual(kit.reachable(area, (3, 19), self.target, state=RouteState('after', **facts)), [])
                with self.assertRaisesRegex(ValueError, 'not specified'):
                    kit.reachable(area, (3, 19), self.target, state=RouteState('missing'))
                with self.assertRaisesRegex(ValueError, 'explicit RouteState'):
                    kit.reachable(area, (3, 19), self.target)

    def test_missing_raft_is_not_implicitly_flooded(self):
        self.area.clear(7, 21, 20, 23)
        self.area.route_platform('raft', (7, 21, 20, 20), mechanism='flood_c')
        dry = RouteState('dry', mechanisms={'flood_c': False}, jump_tiles=0, jump_span=1)
        wet = RouteState('flooded', mechanisms={'flood_c': True}, jump_tiles=0, jump_span=1)
        self.assertTrue(kit.reachable(self.area, (3, 19), self.target, state=dry))
        self.assertEqual(kit.reachable(self.area, (3, 19), self.target, state=wet), [])

    def test_multiple_standing_nodes_in_same_column_and_drop_through(self):
        area = kit.Area('tower', 'Tower', 24, 43, height=48)
        for index, y in enumerate(range(38, 7, -5)):
            area.platform(3 if index % 2 == 0 else 9, 8 if index % 2 == 0 else 14, y)
        state = RouteState('normal')
        self.assertEqual(kit.reachable(area, (3, 42), [('top', (6, 7))], state=state), [])
        area.platform(1, 22, 20)
        self.assertEqual(kit.reachable(area, (18, 19), [('below', (18, 42))], state=state), [])
        area.block(1, 22, 20, 20)
        self.assertTrue(kit.reachable(area, (18, 19), [('below', (18, 42))], state=state))

    def test_landing_is_not_allowed_through_wall_or_ceiling(self):
        self.area.block(14, 15, 0, 19)
        self.assertTrue(kit.reachable(self.area, (3, 19), self.target, state=RouteState('wall')))
        with self.assertRaisesRegex(ValueError, 'invalid standing start'):
            kit.reachable(self.area, (14, 19), self.target, state=RouteState('embedded'))
        with self.assertRaisesRegex(ValueError, 'outside bounds'):
            kit.reachable(self.area, (3, 19), [('bad', (30, 19))], state=RouteState('bad'))

    def test_explicit_movement_bounds_change_reachability(self):
        self.area.platform(16, 25, 12)
        goal = [('ledge', (20, 11))]
        self.assertTrue(kit.reachable(self.area, (3, 19), goal, state=RouteState('base')))
        self.assertEqual(kit.reachable(self.area, (3, 19), goal, state=RouteState('calibrated', jump_tiles=9)), [])

    def test_malformed_conditions_and_state_refused(self):
        for condition in ({}, {'flag': 'a', 'mechanism': 'b'}, {'unknown': 'x'}, {'flag': ''}):
            with self.subTest(condition=condition), self.assertRaises(ValueError):
                self.area.route_gate('bad', (10, 10, 0, 19), **condition)
        with self.assertRaises(ValueError):
            self.area.route_gate('outside', (10, 10, 0, 24), flag='x')
        for raw in ({'flags': {'x': 1}}, {'mechanisms': {'x': None}}, {'jump_tiles': -1}, {'jump_span': 3.5}):
            with self.subTest(raw=raw), self.assertRaises(ValueError):
                RouteState('bad', **raw)


if __name__ == '__main__':
    unittest.main()
