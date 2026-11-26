"""Old K's standing conversation and the separate appendix on a supported desk."""

AREA = "basement_archive"
OLD_K = "archive_old_k"
APPENDIX = "redemption_appendix"
CONFIRMED = "ch5_anchor_identity_confirmed"
OBJECTS = {
    OLD_K: ("♜", 16, "老 K", "向老 K 問備份交易"),
    APPENDIX: ("◫", 44, "記憶贖回附頁", "翻讀記憶贖回附頁"),
}
POINTS = {name: (AREA, x, 19) for name, (_, x, _, _) in OBJECTS.items()}
PROMPTS = {
    "向老 K 問備份交易": ("Ask Old K about the backup deal", "バックアップの取引を老Kに聞く"),
    "翻讀記憶贖回附頁": ("Read the memory redemption appendix", "記憶買い戻しの付則を読む"),
}


def configure(kit):
    for name, (glyph, _, display_name, prompt) in OBJECTS.items():
        ident = f"ch5_{name}"
        if glyph in kit.RES or glyph in kit.PORTALS:
            raise ValueError(f"{AREA}/{name}: chapter glyph {glyph} already in use")
        kit.RES[glyph] = f"res://data/npcs/{ident}.tres"
        kit.NPCS[ident] = dict(name=display_name, speaker="label", rig="", loop="", facing=1, kind=1,
                               prompt=f"{{interact}} {prompt}", talks=[(f"ch5_dispatch_{name}", 0)])
    kit.NPCS[f"ch5_{OLD_K}"].update(speaker="old_k", rig="old_k", loop="wipe_hands", kind=0,
                                    spawn_requires_flag=CONFIRMED, pause_work_near_player=True)


def furnish(room):
    for name, (glyph, x, _, _) in OBJECTS.items():
        row = POINTS[name][2]
        if room.grid.at(x, row) != ".":
            raise ValueError(f"{AREA}/{name}: interaction overlaps cell {x},{row}")
        room.stand(x, glyph, row=row)
    x = POINTS[APPENDIX][1]
    room.prop("basement__notebook_desk", x)
    # Land the book on the tabletop below the desk sprite's raised lamp.
    room.prop("basement__fee_ledger", x, dy=-16, support="prop",
              support_id="basement__notebook_desk", support_x=x, support_dy=9.5)
