"""The evidence surfaces downstairs from Chapter Five's stair landing."""

AREA = "basement_archive"
OBJECTS = {
    "anchor_counterfoil": ("☰", 20, "搬運回單", "查看搬運回單"),
    "anchor_chair": ("♮", 34, "錨椅記錄板", "比對錨椅記錄"),
    "life_notebook": ("▤", 48, "生活筆記", "翻開生活筆記"),
}
POINTS = {name: (AREA, x, 19) for name, (_, x, _, _) in OBJECTS.items()}
PROMPTS = {
    "查看搬運回單": ("Look at the hauling counterfoil", "運搬控えを見る"),
    "比對錨椅記錄": ("Compare the anchor chair record", "錨の椅子の記録を照合する"),
    "翻開生活筆記": ("Open the household notebook", "暮らしの手帳を開く"),
}


def configure(kit):
    for name, (glyph, _, display_name, prompt) in OBJECTS.items():
        ident = f"ch5_{name}"
        if glyph in kit.RES or glyph in kit.PORTALS:
            raise ValueError(f"{AREA}/{name}: chapter glyph {glyph} already in use")
        kit.RES[glyph] = f"res://data/npcs/{ident}.tres"
        kit.NPCS[ident] = dict(name=display_name, speaker="label", rig="", loop="", facing=1, kind=1,
                               prompt=f"{{interact}} {prompt}", talks=[(f"ch5_dispatch_{name}", 0)])


def furnish(areas):
    """Keep the previous ticket's doorway and light by the landing."""
    room = next(area for area in areas if area.id == AREA)
    for name, (glyph, x, _, _) in OBJECTS.items():
        room.stand(x, glyph, row=POINTS[name][2])
    room.zone(14, "basement_amber", 5)
    room.prop("basement__army_cot", 12)
    # The notebook desk sprite includes a raised lamp. Its usable top is
    # 16 units above the floor, below the resource's full sprite bounds.
    for x, paper in ((20, "fee_ledger"), (27, "cash_envelopes")):
        room.prop("basement__notebook_desk", x)
        room.prop(f"basement__{paper}", x, dy=-16, support="prop",
                  support_id="basement__notebook_desk", support_x=x, support_dy=9.5)
    room.prop("basement__name_list_board", 24, y=14, support="wall")
    room.prop("basement__anchor_chair", 34)
    room.prop("basement__anchor_helmet", 37)
    room.prop("basement__kerosene_heater", 41)
    room.prop("basement__notebook_desk", 48)
    room.prop("basement__chip_reader", 57)
    for x in (20, 34, 48):
        room.lamp(x, 11)
    room.features["landmark"] = "過了搬運回單，暖燈下有一張高背錨椅。"
