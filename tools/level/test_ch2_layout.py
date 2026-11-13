"""NE-299: chapter-two vertical routes keep every original cell and story gate.

Grid checks only; real player input, lighting and old-save loading are covered by the Godot suites.
用法：python -m unittest test_ch2_layout（在 tools/level 底下）
"""
import contextlib
import importlib
import os
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.dirname(__file__))
sys.dont_write_bytecode = True
import build_ch1 as kit  # noqa: E402
from level_kit import RouteState  # noqa: E402

TALL = ('harbor_street', 'market_gate', 'market', 'loading')
TERRAIN = '.#='


class ChapterTwoLayoutTests(unittest.TestCase):
    def setUp(self):
        stack = contextlib.ExitStack()
        self.addCleanup(stack.close)
        for name in ('PREFIX', 'CHAPTER', 'PORTALS', 'NPCS', 'THEMES', 'STORY', 'placement_id'):
            stack.enter_context(patch.object(kit, name, getattr(kit, name)))
        stack.enter_context(patch.dict(kit.RES))
        stack.enter_context(patch.dict(kit.ENEMY_NAMES))
        self.ch2 = importlib.import_module('build_ch2')
        kit.PREFIX, kit.CHAPTER = 'ch2', 'ch2_heron'
        self.ch2.configure()

    def build(self, ident):
        area = getattr(self.ch2, f'build_{ident}')()
        for name, x0, x1, _use, members in self.ch2.COMBAT_ZONES.get(area.id, []):
            area.encounter(name, x0, x1, members)
        return area

    def test_every_original_cell_moves_by_the_declared_offset(self):
        for ident in TALL:
            with self.subTest(area=ident):
                old = getattr(self.ch2, f'_build_{ident}_v1')()
                new = getattr(self.ch2, f'build_{ident}')()
                self.assertEqual(new.legacy_layout['cell_offset'], [0, 16])
                self.assertEqual(new.legacy_layout['cells'], {})
                self.assertEqual(new.h, 40)
                for y, row in enumerate(old.grid.rows()):
                    for x, char in enumerate(row):
                        if char not in TERRAIN:
                            self.assertEqual(new.grid.at(x, y + 16), char, (ident, x, y))

    def test_new_doors_are_reciprocal_and_keep_the_story_gate(self):
        ports = {}
        areas = {ident: self.build(ident) for ident in (*TALL, 'ali_home')}
        for area in areas.values():
            for y, row in enumerate(area.grid.rows()):
                for x, char in enumerate(row):
                    if char in kit.PORTALS:
                        ports[kit.PORTALS[char]['id']] = (area, x, y, kit.PORTALS[char])
        pairs = {'street_upper': 'gate_upper', 'market_roof': 'home_roof', 'market_canopy': 'loading_canopy'}
        for one, two in pairs.items():
            for ident, other in ((one, two), (two, one)):
                area, x, y, port = ports[ident]
                self.assertEqual(port['target'], other)
                self.assertEqual(ports[other][3]['to'], f'res://data/levels/ch2_{area.id}.tres')
                self.assertIn(area.grid.at(x, y + 1), '#=', ident)
        # The canopy route reaches the same cargo lane as market_cargo, so it must wait for the same question.
        self.assertEqual(ports['market_canopy'][3]['requires'], ports['market_cargo'][3]['requires'])
        self.assertEqual(ports['loading_canopy'][3]['requires'], 'ch2_market_contact_done')
        # Existing shortcut and family exit keep their original conditions.
        self.assertEqual(ports['market_sc1'][3]['requires'], 'ch2_sc1_open')
        self.assertEqual(ports['loading_sc1'][3]['requires'], 'ch2_sc1_open')
        self.assertEqual(ports['gate_family'][3]['requires'], 'ch2_egret_transport_done')

    def test_high_rewards_need_the_air_jump(self):
        for ident, cell in (('harbor_street', (27, 15)), ('market_gate', (47, 21)), ('market', (89, 15)), ('loading', (61, 20))):
            with self.subTest(area=ident):
                area = self.build(ident)
                start = next((x, y) for y in range(area.h) for x in range(area.w) if area.grid.at(x, y) == 'P')
                self.assertEqual(area.grid.at(*cell), 'c')
                self.assertTrue(kit.reachable(area, start, [('reward', cell)], state=RouteState('ordinary')))
                self.assertEqual(kit.reachable(area, start, [('reward', cell)], state=RouteState('late', jump_tiles=10)), [])
                self.assertEqual(area.capability_targets[f'{cell[0]},{cell[1]}'], {'ability': 'air_jump', 'flag': 'ledger_disk_obtained'})

    def test_upper_routes_are_reachable_with_the_ordinary_jump(self):
        goals = {'harbor_street': [('upper', (61, 23))], 'market_gate': [('upper', (3, 25))],
                 'market': [('roof', (116, 23)), ('canopy', (136, 23))], 'loading': [('canopy', (14, 28))]}
        for ident, targets in goals.items():
            with self.subTest(area=ident):
                area = self.build(ident)
                start = next((x, y) for y in range(area.h) for x in range(area.w) if area.grid.at(x, y) == 'P')
                self.assertEqual(kit.reachable(area, start, targets, state=RouteState('ordinary')), [])

    def test_quest_locations_point_at_real_content(self):
        sys.path.insert(0, os.path.join(kit.ROOT, 'tools', 'story'))
        try:
            source = importlib.import_module('ch2_source')
        finally:
            sys.path.pop(0)
        for key, (ident, x, y) in source.QUEST_LOCATIONS.items():
            if ident in TALL:
                with self.subTest(step=key):
                    self.assertNotIn(self.build(ident).grid.at(x, y), TERRAIN)

    def test_loading_bay_keeps_a_full_roof(self):
        loading = self.build('loading')
        for x in range(104, 149):
            self.assertTrue(all(loading.grid.at(x, y) == '#' for y in range(0, 26)), x)


if __name__ == '__main__':
    unittest.main()
