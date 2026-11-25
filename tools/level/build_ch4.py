#!/usr/bin/env python3
"""Generate the opening of Hollow Shell from the chapter map authoring kit."""

import re
import sys

sys.dont_write_bytecode = True
import build_ch1 as kit

CHAPTER = "ch4_hollow"
GROUND = 20
POINTS = {
    "old_k": ("pawnshop", 49, GROUND - 1),
    "egret": ("ward_reception", 20, GROUND - 1),
    "linden": ("nursing_ward", 26, GROUND - 1),
    "desk_demo": ("nursing_ward", 14, GROUND - 1),
    "voice_demo": ("nursing_ward", 42, 15),
    "cabinet": ("nursing_ward", 31, GROUND - 1),
    "staff_switch": ("nursing_ward", 55, GROUND - 1),
}
PEOPLE = {"old_k": ("老 K", "old_k", "wipe_hands"), "egret": ("鷺", "egret", "glance")}
STATIONS = {
    "linden": "棠", "desk_demo": "桌緣示範", "voice_demo": "收音示範",
    "cabinet": "床頭櫃", "staff_switch": "內廊開門鍵",
}
GLYPHS = dict(zip(POINTS, "ⓞⓔⓣⓓⓥⓒⓢ", strict=True))


def area_path(area):
    return f"res://data/levels/ch4_{area}.tres"


PORTALS = {
    "Ⅰ": ("pawn_ward", "ward_reception", "reception_pawn", "走往夾層病房", "ch4_documents_wrapped",
          "先到當舖櫃檯把回執包好，以免紙張在路上淋濕。"),
    "Ⅱ": ("reception_pawn", "pawnshop", "pawn_ward", "回當舖", "", ""),
    "Ⅲ": ("reception_ward", "nursing_ward", "ward_entry", "進安養病房", "ch4_visit_signed",
          "先找外櫃檯旁的鷺簽訪客簿，再進病房。"),
    "Ⅳ": ("ward_entry", "ward_reception", "reception_ward", "回病房外櫃檯", "", ""),
    "Ⅴ": ("ward_staff", "ward_reception", "reception_staff", "從內廊回外櫃檯", "", ""),
    "Ⅵ": ("reception_staff", "nursing_ward", "ward_staff", "從內廊進病房", "ch4_inner_exit_open",
          "內廊的門要從病房裡面打開，可以先走訪客入口。"),
}

THEMES = {
    "pawnshop": ("concrete", ["shopfront", "brick_block"], "brick", 0.0, "sky_storm",
                 ["pawnshop_front", "pawnshop_kitchen", "basement_door", "harbor_street"]),
    "ward_reception": ("facility_floor", ["facility_wall"], "facility_panel", 0.0, "sky_storm", ["clinic", "mezzanine"]),
    "nursing_ward": ("facility_floor", ["facility_wall"], "facility_panel", 0.0, "sky_storm", ["nursing_ward", "clinic"]),
}


def _configure():
    kit.PREFIX = "ch4"
    kit.CHAPTER = CHAPTER
    kit.PORTALS = {
        glyph: dict(id=ident, to=area_path(target), target=target_id, mode=0, style="door", w=32, h=68,
                    prompt=f"{{interact}} {prompt}", requires=requires, locked=locked)
        for glyph, (ident, target, target_id, prompt, requires, locked) in PORTALS.items()
    }
    prompts = {
        "old_k": "和老 K 說話",
        "egret": "和鷺說話",
        "linden": "和棠說話",
        "desk_demo": "看桌緣示範",
        "voice_demo": "看收音示範",
        "cabinet": "操作床頭櫃",
        "staff_switch": "解鎖內廊的門",
    }
    kit.NPCS = {}
    kit.RES = {}
    for binding, glyph in GLYPHS.items():
        ident = f"ch4_{binding}"
        name, speaker, loop = PEOPLE[binding] if binding in PEOPLE else (STATIONS[binding], "label", "")
        kit.NPCS[ident] = dict(name=name, speaker=speaker, rig=speaker if binding in PEOPLE else "",
                              loop=loop, facing=-1, kind=0 if binding in PEOPLE else 1,
                              prompt=f"{{interact}} {prompts[binding]}", talks=[(f"ch4_dispatch_{binding}", 0)])
        kit.RES[glyph] = f"res://data/npcs/{ident}.tres"
    kit.THEMES = THEMES
    kit.STORY = {}
    kit.placement_id = lambda ident: "ch1_pawnshop" if ident == "pawnshop" else f"ch4_{ident}"


def _pawnshop():
    area = kit.Area("pawnshop", "當舖（赴約）", 112, GROUND, indoor=True)
    kit.pawnshop_shell(area)
    area.stand(41, "P")
    area.stand(74, "Ⅰ")
    return area


def _reception():
    area = kit.Area("ward_reception", "病房外櫃檯", 53, GROUND, indoor=True)
    area.ceiling(1, 51, 7)
    area.zone(0, "reception_white")
    for x in (8, 20, 38):
        area.lamp(x, 8)
    area.stand(3, "Ⅱ")
    area.stand(8, "P")
    area.stand(32, "Ⅲ")
    area.stand(48, "Ⅵ")
    area.prop("clinic__waiting_chairs", 13)
    area.prop("clinic__reception_window", 23, y=15, support="wall")
    area.prop("clinic__reading_desk", 23)
    area.prop("clinic__fern_pot", 37)
    area.prop("clinic__water_dispenser", 42)
    return area


def _ward():
    area = kit.Area("nursing_ward", "安養病房", 65, GROUND, indoor=True)
    area.ceiling(1, 63, 6)
    area.zone(0, "clinic_ward")
    for x in (10, 26, 42, 57):
        area.lamp(x, 7)
    area.stand(3, "Ⅳ")
    area.stand(6, "P")
    area.stand(60, "Ⅴ")
    area.platform(34, 36, 18)
    area.platform(38, 47, 16)
    area.platform(49, 51, 18)
    area.prop("clinic__queue_number_display", 14, y=14, support="wall")
    area.prop("nursing_ward__rain_window_wide", 25, y=13, support="wall")
    area.prop("nursing_ward__ward_bed", 20)
    area.prop("nursing_ward__linden_seated", 26, dx=-4)
    area.prop("nursing_ward__bedside_locker", 31)
    area.prop("nursing_ward__bedside_radio", 42, y=15)
    area.prop("nursing_ward__nurse_cart", 53)
    area.prop("clinic__queue_number_display", 55, y=15, support="wall")
    area.features = {"loop": "病房內廊回外櫃檯。", "landmark": "雨窗與棠的床位。", "vertical": "上層靠窗的收音座。"}
    return area


def main():
    _configure()
    areas = [_pawnshop(), _reception(), _ward()]
    targets = set(GLYPHS.values()) | set(PORTALS)
    for area in areas:
        for binding, (area_id, x, y) in POINTS.items():
            if area_id == area.id:
                area.stand(x, GLYPHS[binding], row=y)
        start = next((x, y) for y in range(area.h) for x in range(area.w) if area.grid.at(x, y) == "P")
        goals = [(area.grid.at(x, y), (x, y)) for y in range(area.h)
                 for x in range(area.w) if area.grid.at(x, y) in targets]
        issues = area.check() + kit.reachable(area, start, goals)
        if issues:
            raise SystemExit("\n".join(issues))
    kit.write_npc_files()
    kit.write_design(areas)
    for area in areas:
        area.grid.write(area.id, (kit.LEVEL_DIR, f"ch4_{area.id}_map.json"), kit._map_extra(area))
        kit.write_level(area, show_card=area.id == "pawnshop")


if __name__ == "__main__":
    main()
