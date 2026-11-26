"""Chapter Five stair encounter and the lower landing that it protects."""

COAT_KNOWN = "ch5_bian_coat_identified"
COAT = "bian_coat"
COAT_POINT = ("basement_stair", 30, 19)
TO_ARCHIVE = "⇘"
TO_STAIR = "⇖"
COAT_GLYPH = "♧"
ACTIVITY = "res://data/encounters/ch5_stair_avoidance.tres"
ARCHIVE = "地下室檔案間"


def configure(kit, npc_prompts, portal_prompts, lock_text):
    kit.PORTALS.update({
        TO_ARCHIVE: dict(id="stair_basement", to="res://data/levels/ch5_basement_archive.tres",
                         target="basement_stair", mode=0, style="door", w=28, h=64,
                         prompt="{interact} 下樓進地下室", requires=COAT_KNOWN,
                         locked="先查看灰衣人留下的外套。"),
        TO_STAIR: dict(id="basement_stair", to="res://data/levels/ch5_basement_stair.tres",
                       target="stair_basement", mode=0, style="door", w=28, h=64,
                       prompt="{interact} 上樓回梯口"),
    })
    npc_prompts["翻看外套衣領"] = ("Examine the coat collar", "コートの襟を調べる")
    portal_prompts.update({
        "下樓進地下室": ("Descend into the basement", "地下室へ下りる"),
        "上樓回梯口": ("Go back up to the stairwell", "階段口へ戻る"),
    })
    lock_text["先查看灰衣人留下的外套。"] = ("Examine the coat left by the person in gray.", "灰色のコートの人物が残した服を調べよう。")
    kit.AREA_NAMES[ARCHIVE] = {"en": "Basement archive", "ja": "地下の書庫"}
    kit.NPCS[f"ch5_{COAT}"] = dict(name="灰外套", speaker="label", rig="", loop="", facing=1, kind=1,
                                    prompt="{interact} 翻看外套衣領", talks=[("ch5_dispatch_bian_coat", 0)])
    kit.RES[COAT_GLYPH] = f"res://data/npcs/ch5_{COAT}.tres"
    kit.THEMES.update({
        "basement_stair": ("concrete", ["facility_wall"], "facility_panel", 0.0, "sky_storm",
                           ["basement_door", "ch2_medic_transport"]),
        "basement_archive": ("concrete", ["facility_wall"], "facility_panel", 0.0, "sky_storm",
                             ["basement_door", "basement"]),
    })


def extend(kit, rooms):
    stair = next(room for room in rooms if room.id == "basement_stair")
    stair.stand(COAT_POINT[1], COAT_GLYPH)
    stair.stand(33, TO_ARCHIVE)
    for span in ((12, 16, 17), (18, 24, 16), (26, 30, 15)):
        stair.platform(*span)
    for prop in stair.props:
        if prop["id"] in {"basement_door__storage_rack", "basement_door__concrete_steps"}:
            prop.pop("ground", None)
            prop["y"] = stair.ground - 1
        if prop["id"] == "basement_door__storage_rack":
            prop["x"] = 12
    stair.prop("ch2_medic_transport__stretcher", 8)
    stair.prop("basement_door__grey_coat_on_steps", 29, y=stair.ground - 1)
    stair.features.update({"loop": "穿過下層或跳上維修架，都能抵達梯口並返回後巷。",
                           "vertical": "維修架越過地面的繩圈和圍堵。"})

    archive = kit.Area("basement_archive", ARCHIVE, 64, 20, indoor=True)
    archive.ceiling(1, 62, 8)
    archive.stand(4, TO_STAIR)
    archive.stand(8, "P")
    archive.prop("basement_door__caged_bulb", 9, y=12, support="wall")
    archive.lamp(9, 8)
    archive.features = {"landmark": "下樓後的籠燈照著原路出口。"}
    return [*rooms, archive]


def options(room_id):
    if room_id != "basement_stair":
        return {}
    return {"avoidance_resource": ACTIVITY, "safe_resume_level": '"res://data/levels/ch5_back_alley.tres"'}
