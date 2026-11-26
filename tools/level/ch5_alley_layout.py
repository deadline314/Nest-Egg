"""Build the rain alley and a returnable landing beyond the voice lock."""

GROUND = 20
LOCK = "ch5_basement_voice_unlocked"
OBJECT = "◈"
POINT = ("back_alley", 41, GROUND - 1)
PAWNSHOP_EXIT_X = 23
STREET_EXIT_X = 40
PORCH_GATE = "⟲"
STREET_GATE = "⇲"
PORTALS = {
    PORCH_GATE: ("pawnshop_back", "back_alley", "alley_pawnshop", "前往當舖後巷", "", ""),
    STREET_GATE: ("street_back", "back_alley", "alley_street", "轉進當舖後巷", "", ""),
    "⇵": ("alley_pawnshop", "pawnshop", "pawnshop_back", "回當舖", "", ""),
    "⇄": ("alley_street", "harbor_street", "street_back", "回港區街道", "", ""),
    "⤋": ("alley_stair", "basement_stair", "stair_alley", "下地下室樓梯", LOCK,
          "先回答牆邊的聲音鎖。"),
    "⤊": ("stair_alley", "back_alley", "alley_stair", "回當舖後巷", "", ""),
}
THEMES = {
    "back_alley": ("concrete", ["shutter_block", "brick_block"], "brick", 0.0,
                  "sky_storm", ["basement_door", "harbor_street"]),
    "basement_stair": ("concrete", ["facility_wall"], "facility_panel", 0.0,
                       "sky_storm", ["basement_door"]),
}


def configure(kit):
    conflicts = set(PORTALS).union({OBJECT}).intersection(set(kit.PORTALS).union(kit.RES))
    if conflicts:
        raise ValueError(f"Chapter 5 voice lock glyphs already used: {sorted(conflicts)}")
    for glyph, (ident, area, reciprocal, label, flag, lock) in PORTALS.items():
        kit.PORTALS[glyph] = dict(id=ident, to=f"res://data/levels/ch5_{area}.tres",
                                  target=reciprocal, mode=0, style="door", w=30, h=64,
                                  prompt=f"{{interact}} {label}", requires=flag, locked=lock)
    kit.NPCS["ch5_voice_lock"] = dict(
        name="聲音鎖", speaker="label", rig="", loop="", facing=-1, kind=1,
        prompt="{interact} 操作聲音鎖", talks=[("ch5_dispatch_voice_lock", 0)],
    )
    kit.RES[OBJECT] = "res://data/npcs/ch5_voice_lock.tres"
    kit.THEMES.update(THEMES)


def join(kit, rooms):
    pawnshop, harbor, _lounge = rooms
    for room, x, glyph in ((pawnshop, PAWNSHOP_EXIT_X, PORCH_GATE),
                           (harbor, STREET_EXIT_X, STREET_GATE)):
        row = room.ground - 1
        if room.grid.at(x, row) != ".":
            raise ValueError(f"{room.id} back-alley exit overlaps map cell at {x},{row}")
        room.stand(x, glyph)
    return [*rooms, *build(kit)]


def build(kit):
    alley = kit.Area("back_alley", "當舖後巷", 52, GROUND)
    alley.stand(4, "⇄")
    alley.stand(8, "P")
    alley.stand(30, "⇵")
    alley.stand(POINT[1], OBJECT)
    alley.stand(47, "⤋")
    alley.ceiling(16, 23, 3)
    for segment in ((12, 16, 18), (18, 22, 16), (23, 29, 14), (31, 35, 16), (37, 40, 18)):
        alley.platform(*segment)
    alley.prop("basement_door__leaking_pipe", 20, y=16, support="wall")
    alley.prop("basement_door__wet_floor_sign", 36)
    alley.prop("basement_door__voice_lock", POINT[1], y=16, support="wall",
              react="ch5_voice_lock_status")
    alley.prop("basement_door__caged_bulb", 43, y=14, support="wall")
    alley.features = {
        "landmark": "聲音鎖在隊尾的籠燈下。",
        "loop": "後巷可通往當舖後門和港區街道。",
        "vertical": "抬高的維修架避開地面的積水，兩端都能下來。",
    }
    stair = kit.Area("basement_stair", "地下室樓梯口", 36, GROUND, indoor=True)
    stair.ceiling(1, 34, 5)
    stair.stand(4, "⤊")
    stair.stand(8, "P")
    stair.prop("basement_door__concrete_steps", 17)
    stair.prop("basement_door__storage_rack", 27)
    stair.prop("basement_door__caged_bulb", 21, y=12, support="wall")
    stair.lamp(21, 8)
    stair.features = {"landmark": "下行臺階和牆上的籠燈。", "loop": "沿原門返回後巷。"}
    return alley, stair
