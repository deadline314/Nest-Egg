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
    "ali": ("revival_lounge", 33, GROUND - 1),
    "shift_board": ("factory_approach", 58, GROUND - 1),
    "rail_release": ("factory_loading", 37, 13),
    "workbench": ("factory_loading", 67, GROUND - 1),
    "sweep_console": ("factory_loading", 71, GROUND - 1),
    "safety_instruction": ("factory_safety", 23, GROUND - 1),
    "safety_catch": ("factory_safety", 35, 13),
    "work_observation": ("factory_work", 81, GROUND - 1),
    "egret_at_rail": ("factory_cleaning", 47, 13),
    "office_release": ("factory_cleaning", 77, GROUND - 1),
    "original_ledger": ("factory_office", 20, GROUND - 1),
}
PEOPLE = {
    "old_k": ("老 K", "old_k", "wipe_hands"),
    "egret": ("鷺", "egret", "glance"),
    "ali": ("阿梨", "ali", "wipe_hands"),
    "egret_at_rail": ("鷺", "egret", ""),
}
STATIONS = {
    "linden": "棠", "desk_demo": "桌緣示範", "voice_demo": "收音示範",
    "cabinet": "床頭櫃", "staff_switch": "內廊開門鍵",
    "shift_board": "舊廠班表", "rail_release": "維修棘輪", "workbench": "裝卸帶工作臺",
    "sweep_console": "清掃試車台",
    "safety_instruction": "安全臺喇叭", "safety_catch": "員工門栓", "work_observation": "清理線讀數", "office_release": "工作帶終端",
    "original_ledger": "讀取原帳",
}
GLYPHS = dict(zip(POINTS, "ⓞⓔⓣⓓⓥⓒⓢⓐⓑⓡⓦⓧⓘⓤⓟⓙⓩⓛ", strict=True))


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
    "Ⅶ": ("reception_lounge", "revival_lounge", "lounge_reception", "沿連廊前往復原館", "ch4_collection_slip_saved",
          "先在床頭櫃拿到公用取件聯，再去復原館找阿梨。"),
    "Ⅷ": ("lounge_reception", "ward_reception", "reception_lounge", "回病房外櫃檯", "", ""),
    "Ⅸ": ("lounge_factory", "factory_approach", "approach_lounge", "前往舊廠房", "ch4_shift_tip_known",
          "先找吧台旁的阿梨，問清楚舊廠換班的入口。"),
    "Ⅹ": ("approach_lounge", "revival_lounge", "lounge_factory", "回復原館", "", ""),
    "Ⅺ": ("approach_loading", "factory_loading", "loading_approach", "進舊廠裝卸帶", "ch4_factory_batch_matched",
          "比對公用取件聯與外門的班表，才能通過貨門。"),
    "Ⅻ": ("loading_approach", "factory_approach", "approach_loading", "從貨門回外廊", "", ""),
    "Ⅼ": ("approach_rail", "factory_loading", "loading_rail", "沿維修高架進裝卸帶", "ch4_loader_rail_released",
          "先從貨門進去，再放開廠內的維修棘輪。"),
    "Ⅾ": ("loading_relay", "factory_relay", "relay_loading", "往清理線前的安全臺", "ch4_demo_cover_cleared",
          "先在固定地面試跑一次清掃裝置。"),
    "Ⅿ": ("relay_loading", "factory_loading", "loading_relay", "回舊廠裝卸帶", "", ""),
    "↟": ("relay_safe", "factory_safety", "safety_relay", "進安全臺", "", ""),
    "↦": ("safety_work", "factory_work", "work_safety", "進清理工作帶", "ch4_cleaning_briefing_read",
          "先在安全臺聽完廠內廣播。"),
    "↪": ("work_arena", "factory_cleaning", "arena_work", "確認進入清掃工作廊", "ch4_factory_work_crossed",
          "先到工作帶另一端核對讀數。"),
    "↩": ("arena_work", "factory_work", "work_arena", "退回工作帶", "", ""),
    "↥": ("arena_office", "factory_office", "office_arena", "上樓進原帳辦公室", "ch4_office_access",
          "等清理隊長撤出工作廊。"),
    "↧": ("office_arena", "factory_cleaning", "arena_office", "下樓回工作廊", "", ""),
    "↤": ("work_safety", "factory_safety", "safety_work", "退回清理線安全臺", "", ""),
    "↡": ("safety_relay", "factory_relay", "relay_safe", "回廠房接線廊", "", ""),
    "⤒": ("loading_service", "factory_safety", "safety_service", "走高架員工捷徑", "ch4_safety_shortcut_open",
          "員工門要從安全臺內側開啟。"),
    "⤓": ("safety_service", "factory_loading", "loading_service", "沿員工捷徑回裝卸帶", "ch4_safety_shortcut_open",
          "先放開安全臺的門栓。"),
    "Ⅽ": ("loading_rail", "factory_approach", "approach_rail", "沿維修高架回外廊", "ch4_loader_rail_released",
          "先放開內側的維修棘輪。"),
}

THEMES = {
    "pawnshop": ("concrete", ["shopfront", "brick_block"], "brick", 0.0, "sky_storm",
                 ["pawnshop_front", "pawnshop_kitchen", "basement_door", "harbor_street"]),
    "ward_reception": ("facility_floor", ["facility_wall"], "facility_panel", 0.0, "sky_storm", ["clinic", "mezzanine"]),
    "nursing_ward": ("facility_floor", ["facility_wall"], "facility_panel", 0.0, "sky_storm", ["nursing_ward", "clinic"]),
    "revival_lounge": ("facility_floor", ["facility_wall"], "facility_panel", 0.0, "sky_storm", ["revival_lounge"]),
    "factory_approach": ("asphalt", ["shutter_block", "warehouse"], "hangar_wall", 0.19, "sky_storm",
                         ["abandoned_factory", "factory_office"]),
    "factory_relay": ("steel_plate", ["warehouse"], "hangar_wall", 0.0, "sky_storm", ["abandoned_factory"]),
    "factory_cleaning": ("steel_plate", ["warehouse"], "hangar_wall", 0.0, "sky_storm", ["abandoned_factory", "factory_office"]),
    "factory_office": ("facility_floor", ["facility_wall"], "facility_panel", 0.0, "sky_storm", ["factory_office"]),
    "factory_work": ("steel_plate", ["warehouse"], "hangar_wall", 0.0, "sky_storm", ["abandoned_factory", "factory_office"]),
    "factory_safety": ("steel_plate", ["warehouse"], "facility_panel", 0.0, "sky_storm", ["abandoned_factory", "factory_office"]),
    "factory_loading": ("steel_plate", ["warehouse"], "hangar_wall", 0.0, "sky_storm",
                        ["abandoned_factory", "factory_office"]),
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
        "original_ledger": "核對原帳",
        "old_k": "和老 K 說話",
        "egret": "和鷺說話",
        "linden": "和棠說話",
        "desk_demo": "看桌緣示範",
        "voice_demo": "看收音示範",
        "cabinet": "操作床頭櫃",
        "staff_switch": "解鎖內廊的門",
        "ali": "和阿梨說話",
        "shift_board": "核對舊廠班表",
        "rail_release": "放開維修棘輪",
        "workbench": "查看清理線",
        "sweep_console": "試一次清掃線",
        "safety_instruction": "聽清理線廣播", "safety_catch": "放開員工門栓",
        "work_observation": "核對白線的讀數",
        "egret_at_rail": "查看鷺的狀況",
        "office_release": "核對工作廊終端",
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
    kit.RES["Ƶ"] = "res://data/props/ch4_sweep_sample.tres"
    kit.NPCS["ch4_egret"].update(spawn_unless_flag="ch4_egret_departed")
    kit.NPCS["ch4_egret_at_rail"].update(spawn_requires_flag="ch4_atropos_midpoint_ready", spawn_unless_flag="ch4_egret_departed")
    kit.NPCS["ch4_office_release"].update(spawn_requires_flag="ch4_atropos_retreat_ready", spawn_unless_flag="ch4_office_access")
    kit.RES.update({
        "⦿": "res://data/enemies/atropos.tres",
        "g": "res://data/enemies/sweeper.tres",
        "b": "res://data/enemies/slasher.tres",
        "d": "res://data/enemies/searchlight_drone.tres",
        "⭙": "res://data/props/ch4_lower_sweep.tres",
        "⭗": "res://data/props/ch4_upper_sweep.tres",
        "⧈": "res://data/props/ch4_work_test_cover.tres",
        "⏚": "res://data/props/ch4_arena_lower_sweep.tres",
        "⏛": "res://data/props/ch4_arena_upper_sweep.tres",
        "▧": "res://data/props/ch4_arena_cover.tres",
    })
    kit.ENEMY_NAMES.update({"b": "切割者", "d": "探照無人機"})
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
    area.stand(43, "Ⅵ")
    area.stand(49, "Ⅶ")
    area.prop("clinic__waiting_chairs", 13)
    area.prop("clinic__reception_window", 23, y=15, support="wall")
    area.prop("clinic__reading_desk", 23)
    area.prop("clinic__fern_pot", 37)
    area.prop("clinic__water_dispenser", 39)
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


def _lounge():
    area = kit.Area("revival_lounge", "復原館的換班口", 61, GROUND, indoor=True)
    area.ceiling(1, 59, 10)
    area.zone(0, "lounge_safe")
    area.stand(4, "Ⅷ")
    area.stand(8, "P")
    area.stand(56, "Ⅸ")
    area.prop("revival_lounge__booth_sofa", 9)
    area.prop("revival_lounge__round_table_stools", 16)
    area.prop("revival_lounge__jukebox", 22)
    area.prop("revival_lounge__bar_counter", 30)
    area.prop("revival_lounge__bottle_wall_shelf", 31, y=14, support="wall")
    area.prop("revival_lounge__menu_board", 43, y=14, support="wall")
    area.prop("revival_lounge__hat_coat_rack", 51)
    for x in (10, 24, 41, 53):
        area.lamp(x, 11)
    return area


def _factory_approach():
    area = kit.Area("factory_approach", "舊廠外廊", 70, GROUND)
    area.zone(0, "factory_rust")
    area.stand(4, "Ⅹ")
    area.stand(8, "P")
    area.stand(63, "Ⅺ")
    area.platform(39, 42, 18)
    area.platform(44, 47, 16)
    area.platform(49, 62, 14)
    area.stand(57, "Ⅼ", row=13)
    area.prop("abandoned_factory__rust_tank", 15)
    area.prop("abandoned_factory__scrap_pile", 23)
    area.prop("abandoned_factory__oil_drum_spill", 30)
    area.ceiling(52, 68, 4)
    area.prop("factory_office__stopped_clock", 58, y=11, support="wall")
    area.prop("factory_office__bulletin_board", 58, y=15, support="wall")
    area.prop("abandoned_factory__broken_conveyor", 48)
    for x in (12, 37, 61):
        area.lamp(x, 9)
    area.features = {"landmark": "外門班表與沿牆升高的維修架。", "loop": "裝卸帶的上層可返回外廊。"}
    return area


def _factory_loading():
    area = kit.Area("factory_loading", "舊廠裝卸帶", 82, GROUND, indoor=True)
    area.ceiling(1, 80, 4)
    area.zone(0, "ch4_loading_bay")
    area.stand(4, "Ⅻ")
    area.stand(7, "P")
    area.stand(12, "C")
    area.stand(76, "Ƶ")
    area.platform(19, 22, 18)
    area.platform(24, 27, 16)
    area.platform(29, 48, 14)
    area.stand(44, "Ⅽ", row=13)
    area.stand(31, "⤒", row=13)
    area.stand(78, "Ⅾ")
    area.platform(51, 53, 16)
    area.platform(55, 58, 18)
    area.prop("abandoned_factory__press_machine", 13)
    area.prop("abandoned_factory__cleaner_gear_case", 60)
    area.prop("hazard_sign", 65, y=15, support="wall")
    area.prop("abandoned_factory__scrap_pile", 67)
    area.prop("abandoned_factory__power_panel", 71, y=15, support="wall")
    for x in (10, 25, 45, 58, 72):
        area.lamp(x, 5)
    area.features = {"landmark": "入口可見的鏽蝕沖壓機。", "loop": "維修棘輪通往外廊上層。",
                     "vertical": "固定地板與兩側階梯連成環路。"}
    return area




def _factory_relay():
    area = kit.Area("factory_relay", "廠房接線廊", 94, GROUND, indoor=True)
    area.zone(0, "ch4_loading_bay")
    area.ceiling(1, 92, 4)
    area.stand(4, "Ⅿ")
    area.stand(8, "P")
    area.stand(89, "↟")
    for x0, x1, y in ((12, 16, 18), (18, 22, 16), (24, 39, 14), (43, 59, 14),
                      (62, 72, 14), (74, 78, 16), (80, 84, 18)):
        area.platform(x0, x1, y)
    area.combat = True
    area.encounter("下層巡查", 29, 42, [(33, "g"), (40, "b")])
    area.encounter("高處探頭", 58, 73, [(63, "d", 10), (70, "d", 11)])
    area.prop("abandoned_factory__broken_conveyor", 39, y=GROUND - 1)
    area.prop("abandoned_factory__rust_tank", 51)
    area.prop("hazard_sign", 69, y=15, support="wall")
    area.prop("abandoned_factory__power_panel", 80, y=13, support="wall")
    for x in (10, 28, 47, 69, 87):
        area.lamp(x, 5)
    area.features = {"landmark": "管線跨過分段的維修架。", "loop": "兩側階梯連接上層，底層可不停步穿過。",
                     "vertical": "上層有探頭，地面有看守。", "reward": "可抵達能回裝卸帶的安全臺。"}
    return area


def _factory_safety():
    area = kit.Area("factory_safety", "清理線安全臺", 45, GROUND, indoor=True)
    area.zone(0, "ch4_loading_bay")
    area.ceiling(1, 43, 4)
    area.stand(4, "↡")
    area.stand(8, "P")
    area.stand(18, "C")
    area.platform(22, 25, 18)
    area.platform(27, 30, 16)
    area.platform(32, 41, 14)
    area.stand(39, "⤓", row=13)
    area.stand(41, "↦")
    area.prop("abandoned_factory__cleaner_gear_case", 14)
    area.prop("abandoned_factory__power_panel", 19, y=13, support="wall")
    area.prop("hazard_sign", 24, y=14, support="wall")
    area.prop("floor_marking", 30, y=GROUND - 1)
    area.prop("factory_office__bulletin_board", 36, y=9, support="wall")
    for x in (9, 20, 31, 39):
        area.lamp(x, 5)
    area.features = {"landmark": "黃標線旁的檢查點。", "loop": "上層員工門回裝卸帶，原路可回接線廊。"}
    return area


def _factory_work():
    area = kit.Area("factory_work", "清理工作帶", 88, GROUND, indoor=True)
    area.zone(0, "ch4_loading_bay")
    area.ceiling(1, 86, 4)
    area.stand(4, "↤")
    area.stand(8, "P")
    area.stand(42, "C")
    for x0, x1, y in ((10, 14, 18), (16, 20, 16), (22, 37, 14), (40, 48, 14),
                      (51, 72, 14), (74, 78, 16), (80, 85, 18)):
        area.platform(x0, x1, y)
    area.stand(29, "⭙")
    area.stand(30, "⧈")
    area.stand(60, "⭗", row=13)
    area.stand(84, "↪")
    area.prop("hazard_sign", 22, y=15, support="wall")
    area.prop("floor_marking", 24, y=GROUND - 1)
    area.prop("floor_marking", 34, y=GROUND - 1)
    area.prop("floor_marking", 55, y=13)
    area.prop("abandoned_factory__press_machine", 45, y=GROUND - 1)
    area.prop("abandoned_factory__power_panel", 80, y=14, support="wall")
    for x in (10, 27, 42, 60, 78):
        area.lamp(x, 5)
    area.features = {"landmark": "亮線間隔顯示的固定工作帶。", "loop": "低處和高架交錯，可從另一層繞過白線。",
                     "vertical": "前段掃底層、後段掃上層。", "reward": "另一端能看見頭目工作廊。"}
    return area


def _factory_cleaning():
    area = kit.Area("factory_cleaning", "清掃工作廊", 94, GROUND, indoor=True)
    area.zone(0, "ch4_loading_bay")
    area.ceiling(1, 92, 4)
    area.stand(4, "↩")
    area.stand(8, "P")
    area.stand(88, "↥")
    for x0, x1, y in ((22, 28, 18), (30, 36, 16), (38, 52, 14), (55, 59, 16), (61, 67, 18)):
        area.platform(x0, x1, y)
    area.stand(64, "⦿")
    area.stand(52, "⏚")
    area.stand(53, "▧")
    area.stand(42, "⏛", row=13)
    area.prop("floor_marking", 16, y=GROUND - 1)
    area.prop("abandoned_factory__press_machine", 30, y=GROUND - 1)
    area.prop("abandoned_factory__power_panel", 76, y=16, support="wall")
    area.prop("hazard_sign", 85, y=14, support="wall")
    for x in (10, 26, 47, 64, 86):
        area.lamp(x, 5)
    area.features = {"landmark": "鷺所在的固定上層欄杆。", "vertical": "工作帶上層保有可到達的支撐。",
                     "loop": "可退回清掃工作帶。"}
    return area


def _factory_office():
    area = kit.Area("factory_office", "原帳辦公室", 42, GROUND, indoor=True)
    area.zone(0, "clinic_ward")
    area.ceiling(1, 40, 5)
    area.stand(4, "↧")
    area.stand(8, "P")
    area.prop("factory_office__blinds_rain_window", 13, y=13, support="wall")
    area.prop("factory_office__desk_with_ledger", 20)
    area.prop("factory_office__toppled_chair", 23)
    area.prop("factory_office__filing_cabinet", 35)
    area.prop("factory_office__stopped_clock", 24, y=12, support="wall")
    area.prop("factory_office__bulletin_board", 28, y=14, support="wall")
    area.prop("floor_marking", 30, y=GROUND - 1)
    for x in (10, 22, 34):
        area.lamp(x, 7)
    area.features = {"landmark": "停在下班時間的時鐘和月報板。"}
    return area


def main():
    _configure()
    areas = [_pawnshop(), _reception(), _ward(), _lounge(), _factory_approach(), _factory_loading(),
             _factory_relay(), _factory_safety(), _factory_work(), _factory_cleaning(), _factory_office()]
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
        options = {"safe_resume_level": '"res://data/levels/ch4_factory_safety.tres"'} if area.id in ("factory_cleaning", "factory_safety") else {}
        kit.write_level(area, show_card=area.id == "pawnshop", **options)


if __name__ == "__main__":
    main()
