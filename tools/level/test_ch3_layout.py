"""NE-300: chapter-three vertical transport keeps every original cell and story gate.

Grid checks only; real player input, lighting and old-save loading are covered by the Godot suites.
用法：python -m unittest test_ch3_layout（在 tools/level 底下）
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

TALL = ('plaza', 'pump', 'mezzanine')
TERRAIN = '.#='


class ChapterThreeLayoutTests(unittest.TestCase):
    def setUp(self):
        stack = contextlib.ExitStack()
        self.addCleanup(stack.close)
        for name in ('PREFIX', 'CHAPTER', 'PORTALS', 'NPCS', 'THEMES', 'STORY', 'placement_id'):
            stack.enter_context(patch.object(kit, name, getattr(kit, name)))
        stack.enter_context(patch.dict(kit.RES))
        stack.enter_context(patch.dict(kit.ENEMY_NAMES))
        self.ch3 = importlib.import_module('build_ch3')
        kit.PREFIX = 'ch3'
        self.ch3.configure()

    def build(self, ident):
        return getattr(self.ch3, f'build_{ident}')()

    def start(self, area):
        return next((x, y) for y in range(area.h) for x in range(area.w) if area.grid.at(x, y) == 'P')

    def test_every_original_cell_moves_by_the_declared_offset(self):
        for ident in TALL:
            with self.subTest(area=ident):
                old = getattr(self.ch3, f'_build_{ident}_v1')()
                new = self.build(ident)
                self.assertEqual(new.legacy_layout['cell_offset'], [0, 16])
                self.assertEqual(new.legacy_layout['cells'], {})
                for y, row in enumerate(old.grid.rows()):
                    for x, char in enumerate(row):
                        if char not in TERRAIN:
                            self.assertEqual(new.grid.at(x, y + 16), char, (ident, x, y))

    def test_shaft_doors_are_reciprocal_and_follow_the_freight_lift(self):
        ports = {}
        for ident in TALL:
            area = self.build(ident)
            for y, row in enumerate(area.grid.rows()):
                for x, char in enumerate(row):
                    if char in kit.PORTALS:
                        ports[kit.PORTALS[char]['id']] = (area, x, y, kit.PORTALS[char])
        for one, two in (('pump_shaft', 'mezz_shaft'), ('mezz_shaft', 'pump_shaft')):
            area, x, y, port = ports[one]
            self.assertEqual(port['target'], two)
            self.assertEqual(ports[two][3]['to'], f'res://data/levels/ch3_{area.id}.tres')
            self.assertEqual(port['requires'], ports['plaza_lift'][3]['requires'])
            self.assertIn(area.grid.at(x, y + 1), '#=')
        # Outer ladder and care passage loops keep their original unlocks.
        self.assertEqual(ports['plaza_ladder'][3]['requires'], 'ch3_outer_ladder_down')
        self.assertEqual(ports['pump_ladder'][3]['requires'], 'ch3_outer_ladder_down')
        self.assertEqual(ports['mezz_care'][3]['requires'], 'ch3_care_passage_open')

    def test_new_layers_need_only_ordinary_jumps_and_rewards_need_the_air_jump(self):
        cases = {'plaza': ([('deck', (60, 23))], (31, 15)), 'pump': ([('gallery', (4, 15))], (41, 7)),
                 'mezzanine': ([('gallery', (74, 15))], (57, 7))}
        for ident, (goals, reward) in cases.items():
            with self.subTest(area=ident):
                area = self.build(ident)
                start = self.start(area)
                self.assertEqual(kit.reachable(area, start, goals, state=RouteState('ordinary')), [])
                self.assertTrue(kit.reachable(area, start, [('reward', reward)], state=RouteState('ordinary')))
                self.assertEqual(kit.reachable(area, start, [('reward', reward)], state=RouteState('late', jump_tiles=10)), [])
                self.assertEqual(area.capability_targets[f'{reward[0]},{reward[1]}']['ability'], 'air_jump')

    def test_indoor_rooms_keep_a_full_roof(self):
        for ident in ('pump', 'mezzanine'):
            area = self.build(ident)
            self.assertTrue(all(area.grid.at(x, 0) == '#' for x in range(area.w)), ident)

    def test_quest_locations_point_at_real_content(self):
        sys.path.insert(0, os.path.join(kit.ROOT, 'tools', 'story'))
        try:
            source = importlib.import_module('ch3_source')
        finally:
            sys.path.pop(0)
        for key, (ident, x, y) in source.QUEST_LOCATIONS.items():
            if ident in TALL:
                with self.subTest(step=key):
                    self.assertNotIn(self.build(ident).grid.at(x, y), TERRAIN)


if __name__ == '__main__':
    unittest.main()
