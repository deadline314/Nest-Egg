"""CPU-only generator height/state contracts; never runs Godot or writes shipping data."""
import contextlib
import io
import json
import sys
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import Mock, patch

import build_ch1 as kit
from level_kit import Grid, RouteState


class HeightTests(unittest.TestCase):
    def test_revision_scalar_and_cell_mapping_keep_existing_list_format(self):
        grid = Grid(3, 2)
        metadata = {'props': [{'id': 'sample', 'x': 1}], 'layout_revision': 2,
                    'legacy_layout': {'revision': 1, 'cell_offset': [0, 32], 'cells': {'1,1': [1,33]}}}
        with tempfile.TemporaryDirectory() as folder, contextlib.redirect_stdout(io.StringIO()):
            path = Path(folder) / 'map.json'
            grid.write('test', (str(path),), metadata)
            text = path.read_text(encoding='utf8')
            self.assertIn('"props": [\n    {"id": "sample", "x": 1}\n  ]', text)
            parsed = json.loads(text)
            self.assertEqual(parsed['layout_revision'], 2)
            self.assertEqual(parsed['legacy_layout'], metadata['legacy_layout'])

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


class ChapterOneLayoutTests(unittest.TestCase):
    def setUp(self):
        self.context = contextlib.ExitStack()
        self.addCleanup(self.context.close)
        self.context.enter_context(patch.object(kit, 'DYN_POOL', list(kit.DYN_POOL)))
        self.context.enter_context(patch.dict(kit.DYN_RES))
        self.context.enter_context(patch.dict(kit.PORTALS))

    def areas(self):
        roof, street = kit.build_rooftop(), kit.build_street()
        warehouse, vault = kit.build_warehouse_pair()
        return {a.id: a for a in (roof, street, warehouse, vault)}

    def test_original_spawns_and_persistent_keys_have_exact_destinations(self):
        fixture = Path(kit.ROOT) / 'tests/fixtures/ch1_layout_v1_cells.json'
        old = json.loads(fixture.read_text(encoding='utf8'))
        for name, area in self.areas().items():
            self.assertEqual((area.w, area.h), (old['areas'][name]['size_tiles'][0], 56))
            self.assertEqual(area.legacy_layout['cell_offset'], [0, 32])
            occupied = {}
            for spawn in old['areas'][name]['spawns']:
                x, y = spawn['old_cell']
                nx, ny = area.legacy_layout['cells'].get(f'{x},{y}', [x, y + 32])
                if spawn['id'].startswith('ch1_arena_'):
                    self.assertNotIn(spawn['glyph'], ''.join(area.grid.rows()))
                else:
                    self.assertEqual(area.grid.at(nx, ny), spawn['glyph'], (name, spawn))
                self.assertNotIn((nx, ny), occupied, (name, spawn))
                occupied[nx, ny] = spawn['id']

    def test_main_route_must_climb_and_descend(self):
        street = kit.build_street()
        self.assertEqual(street.grid.at(64, 51), '#')
        self.assertEqual(street.grid.at(160, 51), '#')
        self.assertTrue(kit.reachable(street, (4, 51), [('warehouse', (204,51))], state=RouteState('no_jump', jump_tiles=0)))
        self.assertEqual(kit.reachable(street, (4,51), [('warehouse',(204,51))], state=RouteState('ordinary')), [])
        self.assertEqual(street.grid.at(64, 32), '#')
        self.assertEqual(street.grid.at(133, 52), '#')
        self.assertEqual(street.grid.at(160, 37), '#')

    def test_dry_and_watchdog_states_cannot_reach_cargo_exit(self):
        warehouse, _vault = kit.build_warehouse_pair()
        for states in ({'watchdog_gate':False,'flood_a':True,'flood_b':True,'flood_c':True},
                       {'watchdog_gate':True,'flood_a':True,'flood_b':True,'flood_c':False}):
            self.assertTrue(kit.reachable(warehouse, (4,48), [('exit',(162,16))], state=RouteState('closed', mechanisms=states)))
        opened = RouteState('after_flood', mechanisms={k:True for k in ('watchdog_gate','flood_a','flood_b','flood_c')})
        self.assertEqual(kit.reachable(warehouse, (4,48), [('exit',(162,16))], state=opened), [])

    def test_late_reward_is_not_part_of_ordinary_route(self):
        street = kit.build_street()
        goal = [('reward', (100,23))]
        self.assertTrue(kit.reachable(street, (4,51), goal, state=RouteState('ordinary')))
        self.assertEqual(kit.reachable(street, (4,51), goal, state=RouteState('post_grid_upper_bound', jump_tiles=10)), [])
        self.assertEqual(street.capability_targets['100,23'], {'ability':'air_jump','flag':'ledger_disk_obtained'})

    def test_loop_ports_are_reciprocal_and_both_sides_have_real_flag(self):
        areas = self.areas()
        ports = {}
        for area in areas.values():
            for y, row in enumerate(area.grid.rows()):
                for x, c in enumerate(row):
                    if c in kit.PORTALS:
                        port = kit.PORTALS[c]
                        if port['id'] in ('vault_street','street_vault','street_roof','roof_maintenance'):
                            ports[port['id']] = (area, x, y, port)
        self.assertEqual(len(ports), 4)
        for ident, (area, x, y, port) in ports.items():
            other = ports[port['target']]
            self.assertEqual(other[3]['target'], ident)
            self.assertEqual(port['requires'], 'ledger_disk_obtained')
            self.assertIn(area.grid.at(x,y+1), '#=')
            self.assertEqual(other[3]['to'], 'res://data/levels/ch1_'+area.id+'.tres')

    def test_binding_and_quest_locations_match_actual_spawn_cells(self):
        root = Path(kit.ROOT)
        with patch.object(sys, 'path', [str(root/'tools/story'), *sys.path]):
            import ch1_closure
            import ch1_runtime_backend
            source = ch1_closure.build_source()
        areas = self.areas()
        for binding, name, x, y in [('brief','rooftop',54,49),('street_clear','street',167,36),
                                    ('watchdog','warehouse',58,48),('flood','warehouse',123,54),('disk_pickup','vault',40,28)]:
            self.assertEqual(ch1_runtime_backend.QUEST_LOCATIONS[binding], (name,x,y))
            self.assertEqual(source.bindings[binding].location_candidate, {'level':'res://data/levels/ch1_'+name+'.tres','cell':[x,y]})
            self.assertNotIn(areas[name].grid.at(x,y), '.#=')
            if binding == 'street_clear':
                self.assertEqual(kit.DYN_RES[areas[name].grid.at(x,y)],
                                 'res://data/props/ch1_enc_street_blockade.tres')


    def test_multilevel_props_keep_their_actual_floor_and_ceiling(self):
        areas = self.areas()
        warehouse = kit._map_extra(areas['warehouse'])['props']
        chain = next(p for p in warehouse if p['id']=='dock_warehouse__hoist_chain')
        self.assertEqual(chain['ceiling_row'], 36)
        vault = kit._map_extra(areas['vault'])['props']
        floors = {p['id']:p['y']+1 for p in vault}
        self.assertEqual(floors['dock_warehouse__wrapped_pallets'], 29)
        self.assertEqual(floors['dock_warehouse__rotating_beacon'], 29)
        self.assertEqual(floors['dock_warehouse__searchlight_post'], 17)
        container = next(p for p in vault if p['id']=='dock_warehouse__open_container')
        self.assertEqual(container['x'], 65)

    def test_bad_legacy_mapping_refuses_without_silent_identity_fallback(self):
        authored = json.loads((Path(kit.LEVEL_DIR)/'ch1_layout_v2.json').read_text(encoding='utf8'))
        old = kit._build_street_v1()
        for kind in ('offset', 'missing_cell', 'merged_cell'):
            broken = json.loads(json.dumps(authored))
            legacy = broken['areas']['street']['legacy_layout']
            if kind == 'offset':
                legacy['cell_offset'] = [0, True]
            elif kind == 'missing_cell':
                legacy['cells']['999,19'] = [2, 3]
            else:
                legacy['cells']['66,19'] = [84, 31]
            with tempfile.TemporaryDirectory() as folder:
                (Path(folder)/'ch1_layout_v2.json').write_text(json.dumps(broken), encoding='utf8')
                with patch.object(kit, 'LEVEL_DIR', folder), self.subTest(kind=kind), self.assertRaises(ValueError):
                    kit._v2_area(old)

    def test_extra_jump_practice_has_a_retry_floor_without_local_enemies(self):
        _warehouse, vault = kit.build_warehouse_pair()
        target = [('practice', (40, 12))]
        self.assertTrue(kit.reachable(vault, (46, 20), target, state=RouteState('before')))
        self.assertEqual(kit.reachable(vault, (46, 20), target, state=RouteState('after', jump_tiles=10)), [])
        self.assertEqual(kit.reachable(vault, (4,48), [('practice_entry',(46,20))], state=RouteState('entry')), [])
        self.assertTrue(all(vault.grid.at(x,21)=='#' for x in range(27,51)))
        self.assertTrue(all(vault.grid.at(51,y)=='#' for y in range(14)))
        self.assertTrue(all(vault.grid.at(57,y)=='#' for y in range(15,33)))
        enemy_glyphs = {glyph for glyph, path in kit.RES.items() if path.startswith('res://data/enemies/')}
        self.assertFalse(any(vault.grid.at(x,y) in enemy_glyphs | {'^','!','~'}
                             for y in range(1,21) for x in range(27,51)))
        self.assertEqual(vault.legacy_layout['cells']['52,9'], [60,44])

    def test_retired_gates_are_removed_but_actual_combat_gates_are_preserved(self):
        area = SimpleNamespace(encounters=[{'key':'ordinary','gate_char':'a'}, {'key':'real','gate_char':'b'}])
        with tempfile.TemporaryDirectory() as folder:
            for key, lock in [('ordinary',False),('real',True)]:
                (Path(folder)/f'ch1_arena_{key}.tres').write_text(
                    f'kind = 1\narena_gate = true\nlock_combat_area = {str(lock).lower()}\n', encoding='utf8')
            with patch.object(kit, 'ENCOUNTER_DIR', folder):
                self.assertEqual(kit._retired_gate_glyphs(area), {'a'})

    def test_secret_credit_has_a_real_drop_route_through_the_upper_walkway(self):
        _warehouse, vault = kit.build_warehouse_pair()
        self.assertTrue(all(vault.grid.at(x,13)=='.' for x in range(111,114)))
        self.assertEqual(kit.reachable(vault, (4,48), [('secret',(118,28))], state=RouteState('ordinary')), [])

    def test_existing_indoor_rooms_keep_a_full_roof_above_the_new_layers(self):
        warehouse, vault = kit.build_warehouse_pair()
        for area in [warehouse, vault]:
            self.assertTrue(all(area.grid.at(x,0)=='#' for x in range(area.w)))
            self.assertTrue(all(area.grid.at(x,y)=='#' for y in range(4) for x in range(area.w)))
            for y in range(4):
                self.assertFalse(any(c not in '#.' for c in area.grid.rows()[y]))
        self.assertEqual(vault.legacy_layout['cells']['90,6'], [90,6])
        self.assertEqual(vault.grid.at(90,6), 'd')


if __name__ == '__main__':
    unittest.main()
