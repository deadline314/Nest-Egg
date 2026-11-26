#!/usr/bin/env python3
"""Generate the playable Chapter Five pawnshop inventory route."""

import sys

sys.dont_write_bytecode = True
import build_ch1 as kit
import ch5_anchor_layout as anchor_layout
import ch5_revival_route as revival
import ch5_alley_layout as alley
import ch5_stair_layout as stair
from portal_translations import PROMPTS as PORTAL_PROMPTS, LOCKS as PORTAL_LOCKS
import ch5_fee_layout as fee_layout
from npc_prompt_translations import TRANSLATIONS

CHAPTER = "ch5_paymaster"
GROUND = 20
OBJECTS = {
    "watch": ("ⓦ", 34, "懷錶的標籤", "讀懷錶的標籤"),
    "raincoat": ("ⓡ", 37, "雨衣的標籤", "讀雨衣的標籤"),
    "fare": ("ⓕ", 45, "船錢罐的標籤", "讀船錢罐的標籤"),
    "guitar": ("ⓖ", 48, "吉他的標籤", "讀吉他的標籤"),
    "shelf_index": ("ⓘ", 52, "抽屜格號", "查看抽屜格號"),
    "inventory_board": ("ⓑ", 56, "盤點板", "核對空白標籤"),
}
OBJECTS = fee_layout.with_fee_objects(OBJECTS)
POINTS = {ident: ("pawnshop", x, GROUND - 1) for ident, (_, x, _, _) in OBJECTS.items()}


def _configure():
    kit.PREFIX = "ch5"
    kit.CHAPTER = CHAPTER
    kit.PORTALS = {}
    kit.NPCS = {
        f"ch5_{ident}": dict(name=name, speaker="label", rig="", loop="", facing=1, kind=1,
                            prompt=f"{{interact}} {prompt}", talks=[(f"ch5_dispatch_{ident}", 0)])
        for ident, (_, _, name, prompt) in OBJECTS.items()
    }
    fee_layout.gate_counter_objects(kit.NPCS)
    TRANSLATIONS.update(fee_layout.PROMPTS)
    kit.RES = {glyph: f"res://data/npcs/ch5_{ident}.tres"
               for ident, (glyph, _, _, _) in OBJECTS.items()}
    kit.THEMES = {
        "pawnshop": ("concrete", ["shopfront", "brick_block"], "brick", 0.0, "sky_storm",
                     ["pawnshop_front", "pawnshop_kitchen", "basement_door", "harbor_street", "factory_office", "basement"]),
    }
    kit.CURVE = {}
    kit.STORY = {}
    kit.placement_id = lambda ident: {"pawnshop": "ch1_pawnshop", "harbor_street": "ch1_street",
                                      "revival_lounge": "ch4_revival_lounge"}.get(ident, f"ch5_{ident}")
    revival.configure()
    alley.configure(kit)
    stair.configure(kit, TRANSLATIONS, PORTAL_PROMPTS, PORTAL_LOCKS)

    anchor_layout.configure(kit)
    TRANSLATIONS.update(anchor_layout.PROMPTS)


def main():
    _configure()
    area = kit.Area("pawnshop", "當舖（貨架盤點）", 112, GROUND, indoor=True)
    kit.pawnshop_shell(area)
    spawn = (41, GROUND - 1)
    area.stand(spawn[0], "P")
    for glyph, x, _, _ in OBJECTS.values():
        area.stand(x, glyph)

    # Put the inventory board at an existing lit, reachable section of the counter.
    area.prop("pawnshop_front__range_tally_board", POINTS["inventory_board"][1], y=16, support="wall")
    fee_layout.stage_counter(area)
    area.features = {"landmark": "櫃台黃燈下的格號和盤點板。"}
    areas = stair.extend(kit, alley.join(kit, revival.areas(area, GROUND)))
    anchor_layout.furnish(areas)
    targets = set(kit.RES) | set(kit.PORTALS)
    for room in areas:
        marks = [(room.grid.at(x, GROUND - 1), (x, GROUND - 1)) for x in range(room.w)]
        start = next(cell for glyph, cell in marks if glyph == "P")
        goals = [(glyph, cell) for glyph, cell in marks if glyph in targets]
        issues = room.check() + kit.reachable(room, start, goals)
        if issues:
            raise SystemExit("\n".join(issues))
    kit.write_npc_files()
    kit.write_design(areas)
    for room in areas:
        room.grid.write(room.id, (kit.LEVEL_DIR, f"ch5_{room.id}_map.json"), kit._map_extra(room))
        kit.write_level(room, show_card=room.id == "pawnshop", **stair.options(room.id))


if __name__ == "__main__":
    main()
