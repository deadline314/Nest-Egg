#!/usr/bin/env python3
"""Generate the playable Chapter Five pawnshop inventory route."""

import sys

sys.dont_write_bytecode = True
import build_ch1 as kit

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
    kit.RES = {glyph: f"res://data/npcs/ch5_{ident}.tres"
               for ident, (glyph, _, _, _) in OBJECTS.items()}
    kit.THEMES = {
        "pawnshop": ("concrete", ["shopfront", "brick_block"], "brick", 0.0, "sky_storm",
                     ["pawnshop_front", "pawnshop_kitchen", "basement_door", "harbor_street"]),
    }
    kit.CURVE = {}
    kit.STORY = {}
    kit.placement_id = lambda _ident: "ch1_pawnshop"


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
    area.features = {"landmark": "櫃台黃燈下的格號和盤點板。"}
    goals = [(glyph, (x, GROUND - 1)) for glyph, x, _, _ in OBJECTS.values()]
    issues = area.check() + kit.reachable(area, spawn, goals)
    if issues:
        raise SystemExit("\n".join(issues))
    kit.write_npc_files()
    kit.write_design([area])
    area.grid.write(area.id, (kit.LEVEL_DIR, "ch5_pawnshop_map.json"), kit._map_extra(area))
    kit.write_level(area, show_card=True)


if __name__ == "__main__":
    main()
