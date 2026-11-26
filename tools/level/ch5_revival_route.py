"""Scene 5.03's walkable quay and Restoration Hall."""

import build_ch1 as kit

LEDGER_COMPARED = "ch5_fee_ledger_compared"
PEAR = ("revival_lounge", 38, 19)
PEAR_GLYPH = "ⓟ"
PAWN_EXIT = ("Ⅰ", 77)
AREA_PATH = "res://data/levels/ch5_{}.tres"
LOCKED = "先到當舖的盤點板核對舊收據和存款總帳。"


def configure():
    for glyph, ident, target, arrival, text, gate in (
        ("Ⅰ", "pawn_street", "harbor_street", "street_pawn", "前往港區街道", LEDGER_COMPARED),
        ("Ⅱ", "street_pawn", "pawnshop", "pawn_street", "回當舖", ""),
        ("Ⅲ", "street_hall", "revival_lounge", "hall_street", "進復原館", ""),
        ("Ⅳ", "hall_street", "harbor_street", "street_hall", "回港區街道", ""),
    ):
        kit.PORTALS[glyph] = dict(
            id=ident, to=AREA_PATH.format(target), target=arrival, w=32, h=68,
            mode=0, style="door", prompt=f"{{interact}} {text}",
            requires=gate, locked=LOCKED if gate else "",
        )
    kit.NPCS["ch5_pear"] = dict(
        name="阿梨", speaker="ali", rig="ali", loop="wipe_hands", facing=-1,
        prompt="{interact} 和阿梨說話", talks=[("ch5_dispatch_pear", 0)],
    )
    kit.RES[PEAR_GLYPH] = "res://data/npcs/ch5_pear.tres"
    kit.THEMES.update({
        "harbor_street": ("asphalt", ["shopfront", "shutter_block"], None, 0.12, "sky_storm",
                          ["harbor_street"]),
        "revival_lounge": ("facility_floor", ["facility_wall"], "facility_panel", 0.0, "sky_storm",
                           ["revival_lounge"]),
    })


def _street(ground):
    area = kit.Area("harbor_street", "港區街道", 57, ground)
    area.stand(5, "Ⅱ")
    area.stand(10, "P")
    area.stand(51, "Ⅲ")
    area.prop("harbor_street__fish_cart", 17)
    area.prop("harbor_street__steam_manhole", 28)
    area.prop("harbor_street__restore_queue_sign", 46)
    area.features = {"landmark": "復原服務的排隊牌立在復原館入口外。"}
    return area


def _hall(ground):
    area = kit.Area("revival_lounge", "復原館", 61, ground, indoor=True)
    area.ceiling(1, 59, 10)
    area.zone(0, "lounge_safe")
    area.stand(4, "Ⅳ")
    area.stand(8, "P")
    area.stand(PEAR[1], PEAR_GLYPH, row=PEAR[2])
    area.prop("revival_lounge__booth_sofa", 9)
    area.prop("revival_lounge__round_table_stools", 16)
    area.prop("revival_lounge__jukebox", 22)
    area.prop("revival_lounge__bar_counter", 30)
    area.prop("revival_lounge__bottle_wall_shelf", 31, y=14, support="wall")
    area.prop("revival_lounge__menu_board", 44, y=14, support="wall")
    area.prop("revival_lounge__hat_coat_rack", 51)
    for x in (10, 24, 40, 53):
        area.lamp(x, 11)
    area.features = {"landmark": "阿梨站在吧台末端的暖燈下。"}
    return area


def areas(pawnshop, ground):
    glyph, x = PAWN_EXIT
    if pawnshop.grid.at(x, ground - 1) != ".":
        raise ValueError(f"Pawnshop street exit overlaps map cell at {x},{ground - 1}")
    pawnshop.stand(x, glyph)
    return [pawnshop, _street(ground), _hall(ground)]
