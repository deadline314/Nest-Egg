"""Ye and the paperwork laid out at the existing pawnshop workbench."""

CLAUSE_READ = "ch5_redemption_clause_read"
YE = "ye_offer"
PAPERS = "ye_offer_papers"
OBJECTS = {
    YE: ("♢", 66, "葉", "聽葉的條件", "ye", 0),
    PAPERS: ("▥", 62, "保密要約", "查看桌上的報價", "", 1),
}
POINTS = {name: ("pawnshop", x, 19) for name, (_, x, _, _, _, _) in OBJECTS.items()}
PROMPTS = {
    "聽葉的條件": ("Hear Ye's terms", "葉の条件を聞く"),
    "查看桌上的報價": ("Read the offer on the desk", "机の提示額を確認する"),
}


def configure(kit):
    for name, (glyph, _, display_name, prompt, rig, kind) in OBJECTS.items():
        ident = f"ch5_{name}"
        if glyph in kit.RES or glyph in kit.PORTALS:
            raise ValueError(f"pawnshop/{name}: glyph {glyph} already in use")
        kit.RES[glyph] = f"res://data/npcs/{ident}.tres"
        kit.NPCS[ident] = dict(
            name=display_name, speaker="ye" if rig else "label", rig=rig, loop="", facing=-1,
            kind=kind, prompt=f"{{interact}} {prompt}", spawn_requires_flag=CLAUSE_READ,
            talks=[(f"ch5_dispatch_{name}", 0)],
        )
    material, facades, interior, holes, sky, props = kit.THEMES["pawnshop"]
    kit.THEMES["pawnshop"] = (material, facades, interior, holes, sky, [*props, "recording_booth"])


def furnish(areas):
    room = next(area for area in areas if area.id == "pawnshop")
    for name, (glyph, x, _, _, _, _) in OBJECTS.items():
        room.stand(x, glyph, row=POINTS[name][2])
    # Measure the lower, usable workbench surface below its lamp and tool rack.
    room.prop("recording_booth__script_sheets", POINTS[PAPERS][1], dy=-16.0, support="prop",
              support_id="pawnshop_front__arms_workbench", support_x=61, support_dy=15.5)
