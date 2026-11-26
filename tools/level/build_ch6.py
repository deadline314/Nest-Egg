#!/usr/bin/env python3
"""Emit the Chapter Six plaza, braced overpass, and relay forecourt."""

from pathlib import Path
import argparse

import build_ch1 as kit
import ch6_control_station as control
import ch6_relay_water as water
import ch6_studio_trial as studio
from npc_prompt_translations import TRANSLATIONS
from portal_translations import LOCKS, PROMPTS


PREFIX = "ch6"
CHAPTER = "ch6_unmooring"
GROUND = 20
WITNESS = "ch6_su_approach_confirmed"
REQUEST = "ch5_ledger_broadcast_requested"
LOCK_TEXT = "先到廣場喇叭和蘇確認維修路線。"
PORTALS = (
    ("ⅰ", "plaza_phone", "ch5_phone_alley", "phone_plaza", "hidden", "", "",
     ("回電話亭巷", "Return to Phone Booth Alley", "電話ボックス横丁に戻る")),
    ("ⅱ", "plaza_overpass", "ch6_broadcast_overpass", "overpass_plaza", "hidden", WITNESS, LOCK_TEXT,
     ("上廣播站高架", "Take the broadcast overpass", "放送局の高架に上る")),
    ("ⅲ", "overpass_plaza", "ch6_harbor_plaza", "plaza_overpass", "hidden", "", "",
     ("回港區廣場", "Return to the harbor plaza", "港の広場に戻る")),
    ("ⅳ", "overpass_relay", "ch6_broadcast_outside", "relay_overpass", "door", "", "",
     ("進廣播站前庭", "Enter the relay yard", "中継所前庭に入る")),
    ("ⅴ", "relay_overpass", "ch6_broadcast_overpass", "overpass_relay", "door", "", "",
     ("回高架維修道", "Return to the maintenance overpass", "高架の保守路に戻る")),
    *water.PORTALS,
)
OBJECTS = (
    ("Ⓢ", "plaza_intercom", "廣場廣播喇叭", "harbor_plaza", 30, 19,
     ("聯絡廣播站", "Call the broadcast station", "放送局に連絡する")),
    ("ⓐ", "relay_signal", "高架線況表", "broadcast_overpass", 34, 15,
     ("查看中繼站線況", "Read the relay signal", "中継の信号を確認する")),
    ("ⓖ", "yard_gauge", "前庭水位尺", "broadcast_outside", 24, 19,
     ("查看前庭水位", "Check the yard water level", "前庭の水位を調べる")),
    *water.OBJECTS,
    *studio.OBJECTS,
    *control.OBJECTS,
)
POINTS = {name: (room, x, row) for _, name, _, room, x, row, _ in OBJECTS}
THEMES = {
    "recording_booth": (*water.THEME[:-1], [*water.THEME[-1], "control_room"]),
    "harbor_plaza": ("asphalt", ["shopfront", "shutter_block"], None, 0.14, "sky_storm",
                    ["harbor_plaza", "anchor_phone_booth", "mezzanine"]),
    "broadcast_overpass": ("steel_plate", ["facility_wall", "shutter_block"], "facility_panel", 0.0, "sky_storm",
                           ["harbor_plaza", "sluice_hall", "broadcast_outside"]),
    "broadcast_outside": ("concrete", ["facility_wall"], "facility_panel", 0.10, "sky_storm",
                          ["broadcast_outside", "harbor_plaza", "sluice_hall", "abandoned_factory"]),
}


def configure():
    kit.PREFIX = PREFIX
    kit.CHAPTER = CHAPTER
    kit.STORY = {}
    kit.CURVE = {}
    kit.NPCS = {}
    kit.RES = {}
    kit.PORTALS = {}
    kit.THEMES = THEMES
    LOCKS[LOCK_TEXT] = ("Check the maintenance route with Wake at the plaza speaker first.",
                       "先に広場のスピーカーで蘇と保守路を確認する。")
    LOCKS[water.LOCK_TEXT] = water.LOCK_COPY
    for glyph, name, target, mate, style, gate, locked, (zh, en, ja) in PORTALS:
        PROMPTS[zh] = (en, ja)
        kit.PORTALS[glyph] = dict(id=name, to=f"res://data/levels/{target}.tres", target=mate,
                                  mode=0, style=style, w=30, h=63, prompt=f"{{interact}} {zh}",
                                  requires=gate, locked=locked)
    for glyph, name, label, _, _, _, (zh, en, ja) in OBJECTS:
        key = f"{PREFIX}_{name}"
        TRANSLATIONS[zh] = (en, ja)
        kit.NPCS[key] = dict(name=label, speaker="label", facing=1, rig="", loop="", kind=1,
                              prompt=f"{{interact}} {zh}", talks=[(f"ch6_dispatch_{name}", 0)])
        if name in studio.PEOPLE:
            kit.NPCS[key].update(speaker="su", rig="su", kind=0, **studio.PEOPLE[name])
        kit.RES[glyph] = f"res://data/npcs/{key}.tres"


def plaza():
    room = kit.Area("harbor_plaza", "港區廣場（廣播前）", 68, GROUND)
    room.stand(4, "ⅰ")
    room.stand(8, "P")
    room.stand(62, "ⅱ")
    room.prop("mezzanine__grating_stairs", 2, dx=11.2, flip=True)
    room.prop("harbor_plaza__hot_drink_kiosk", 14)
    room.prop("harbor_plaza__plaza_benches", 23)
    room.prop("harbor_plaza__loudspeaker_pole", 30, dx=-3.45)
    room.prop("harbor_plaza__queue_barriers", 41)
    room.prop("harbor_plaza__plaza_screen", 51)
    room.prop("harbor_plaza__freight_lift", 62, dx=-12.55, react="ch6_approach_lift")
    room.features = {"landmark": "廣場喇叭與貨梯", "loop": "貨梯上高架，出口仍可返回電話亭。"}
    return room


def overpass():
    room = kit.Area("broadcast_overpass", "廣播站高架維修道", 67, GROUND)
    room.stand(4, "ⅲ")
    room.stand(8, "P")
    room.stand(62, "ⅳ")
    room.prop("harbor_plaza__freight_lift", 4, dx=-12.55, react="ch6_approach_lift")
    # The protected bays have a solid backing for the bolted rail and control box.
    room.ceiling(16, 47, 2)
    room.platform(12, 18, 18)
    room.platform(17, 23, 16)
    room.platform(23, 46, 16)
    room.platform(46, 52, 17)
    room.platform(51, 57, 18)
    # The tread is at pixel 150 of 288 in both atlas regions, 23 world units
    # above the texture bottom. The authored path and deck therefore meet at y=256.
    room.prop("sluice_hall__catwalk_section", 17, y=16, dy=7, support="wall")
    span_pitch = 72
    span_start = 17 * kit.TILE + 93.4
    for index in range(5):
        left = span_start + index * span_pitch
        col = int(left // kit.TILE)
        room.prop("sluice_hall__catwalk_span", col, y=16, dx=round(left - col * kit.TILE, 2), dy=7,
                  support="wall")
    room.prop("harbor_plaza__lift_control_box", 34, y=14, dx=3.7, support="wall")
    # The maintenance floor runs underneath the optional upper route.
    for ident, x in (("cable_reel", 15), ("sandbag_barrier", 52)):
        room.prop(f"broadcast_outside__{ident}", x, y=GROUND - 1, support="ground")
    room.lamp(31, 14)
    room.lamp(38, 18)
    room.lamp(57, 13)
    room.features = {"landmark": "鋼桁架與線況表", "loop": "平台和橋下維修道互通。", "vertical": "上層可看線況，下層可直接前往前庭。"}
    return room


def relay():
    room = kit.Area("broadcast_outside", "廣播站前庭", 56, GROUND)
    room.stand(4, "ⅴ")
    room.stand(8, "P")
    room.prop("broadcast_outside__antenna_tower", 15)
    room.prop("broadcast_outside__pond_gauge_pole", 24, dx=-3.25, react="ch6_cooling_gauge")
    room.prop("broadcast_outside__cable_reel", 32)
    room.prop("broadcast_outside__pump_hut", 42, y=GROUND - 1, support="ground")
    room.prop("broadcast_outside__lamp_mast", 47, y=GROUND - 1, support="ground")
    room.prop("broadcast_outside__studio_door", 50, react="ch6_recording_door")
    water.extend_forecourt(room)
    room.features = {"landmark": "水位尺與前庭泵房", "loop": "乾台與前庭地面相通，入口可原路退回高架。"}
    return room


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="validate walkway reachability without writing output")
    options = parser.parse_args()
    configure()
    yard = relay()
    booth = water.recording_booth(kit, GROUND)
    studio.extend_canopy(yard)
    studio.extend_booth(booth)
    control.extend_booth(booth)
    areas = [plaza(), overpass(), yard, booth]
    for area in areas:
        for glyph, _, _, room, col, row, _ in OBJECTS:
            if room == area.id:
                area.stand(col, glyph, row)
        goals = [(area.grid.at(x, y), (x, y)) for y in range(area.h) for x in range(area.w)
                 if area.grid.at(x, y) in {*kit.PORTALS, *(r[0] for r in OBJECTS)}]
        errors = area.check() + kit.reachable(area, (8, GROUND - 1), goals)
        if errors:
            raise SystemExit("\n".join(errors))
    if options.check:
        print("Chapter Six walkable areas and all local stations validated.")
        return
    control.write_stage(Path(__file__).resolve().parents[2])
    kit.write_npc_files()
    kit.write_design(areas)
    for room in areas:
        room.grid.write(room.id, (kit.LEVEL_DIR, f"{PREFIX}_{room.id}_map.json"), kit._map_extra(room))
        kit.write_level(room, show_card=room.id == "harbor_plaza")


if __name__ == "__main__":
    main()
