"""Install the street and service passages with separate real return portals."""

GROUND = 20
DECLINED = "ch5_ye_offer_declined"
PAID = "ch5_gray_first_wage_paid"
LATCH = "ch5_gray_return_unlatched"
BROADCAST_REQUEST = "ch5_ledger_broadcast_requested"
PLAZA_PORTAL = "Ⅻ"
PLAZA_PROMPT = "上港區廣場"
PLAZA_LOCK = "先在電話亭聯絡燈，確認公開帳本的請託。"
ROUTE_LOCKS = {
    "先回當舖談清楚那份要約。": ("Settle the offer at the pawnshop first.", "先に質屋で申し出について話をつける。"),
    "可付本期工錢，或從港區街道前往電話亭。": ("Pay this wage or use Harbor Street to reach the booth.", "今回の賃金を払うか、港の通りから電話ボックスへ行く。"),
    "先從灰道小桌那一側打開回口。": ("Release the latch from the service table side first.", "先に灰道の小机側から留め金を外す。"),
}

PORTALS = (
    ("Ⅵ", "archive_gray", "gray_path", "gray_archive", "進灰道", "Enter the service passage", "灰道へ入る",
     PAID, "可付本期工錢，或從港區街道前往電話亭。"),
    ("Ⅶ", "gray_archive", "basement_archive", "archive_gray", "回當舖地下室", "Return to the pawnshop basement", "質屋の地下室に戻る", "", ""),
    ("Ⅷ", "street_phone", "phone_alley", "phone_street", "前往電話亭巷", "Go to Phone Booth Alley", "電話ボックス横丁へ",
     DECLINED, "先回當舖談清楚那份要約。"),
    ("Ⅸ", "phone_street", "harbor_street", "street_phone", "回港區街道", "Return to Harbor Street", "港の通りに戻る", "", ""),
    ("Ⅹ", "gray_phone", "phone_alley", "phone_gray", "從灰道走到電話亭", "Take the passage to the phone booth", "灰道から電話ボックスへ",
     LATCH, "先從灰道小桌那一側打開回口。"),
    ("Ⅺ", "phone_gray", "gray_path", "gray_phone", "從灰道回小桌", "Return to the service table", "灰道の小机に戻る",
     LATCH, "先從灰道小桌那一側打開回口。"),
)
OBJECTS = {
    "paymaster_phone": ("☎", "phone_alley", 29, "電話亭話筒", "拿起電話", "Pick up the phone", "受話器を取る"),
    "gray_wage_notice": ("▧", "basement_archive", 52, "本期交班單", "查看本期工錢", "Read the wage notice", "今回の賃金を確認する"),
    "gray_return_latch": ("⊞", "gray_path", 46, "回口滑扣", "打開回口滑扣", "Release the return latch", "帰り口の留め金を外す"),
}
POINTS = {name: (room, x, GROUND - 1) for name, (_, room, x, _, _, _, _) in OBJECTS.items()}


def configure(kit, npc_prompts, portal_prompts, portal_locks):
    glyphs = {row[0] for row in PORTALS} | {row[0] for row in OBJECTS.values()} | {PLAZA_PORTAL}
    conflict = glyphs & (set(kit.RES) | set(kit.PORTALS))
    if conflict:
        raise ValueError(f"Chapter Five service passage glyphs already used: {sorted(conflict)}")
    portal_locks.update(ROUTE_LOCKS)
    for glyph, ident, target, mate, zh, en, ja, gate, locked in PORTALS:
        portal_prompts[zh] = (en, ja)
        kit.PORTALS[glyph] = dict(id=ident, to=f"res://data/levels/ch5_{target}.tres", target=mate,
                                  mode=0, style="door", w=30, h=63, prompt=f"{{interact}} {zh}",
                                  requires=gate, locked=locked)
    portal_prompts[PLAZA_PROMPT] = ("Take the stairs to Harbor Plaza", "階段で港の広場へ")
    portal_locks[PLAZA_LOCK] = ("Call Lamp about publishing the ledger first.",
                                "先に電話ボックスから灯に帳簿公開を頼む。")
    kit.PORTALS[PLAZA_PORTAL] = dict(
        id="phone_plaza", to="res://data/levels/ch6_harbor_plaza.tres", target="plaza_phone",
        mode=0, style="hidden", w=30, h=63, prompt=f"{{interact}} {PLAZA_PROMPT}",
        requires=BROADCAST_REQUEST, locked=PLAZA_LOCK)
    for name, (glyph, _, _, label, zh, en, ja) in OBJECTS.items():
        npc_prompts[zh] = (en, ja)
        kit.NPCS[f"ch5_{name}"] = dict(name=label, speaker="label", rig="", loop="", facing=1,
                                      kind=1, prompt=f"{{interact}} {zh}", talks=[(f"ch5_dispatch_{name}", 0)])
        kit.RES[glyph] = f"res://data/npcs/ch5_{name}.tres"
    kit.THEMES.update({
        "gray_path": ("concrete", ["facility_wall"], "facility_panel", 0.0, "sky_storm",
                      ["basement", "basement_door", "dock_warehouse"]),
        "phone_alley": ("asphalt", ["shopfront", "shutter_block"], None, 0.12, "sky_storm",
                        ["anchor_phone_booth", "harbor_street", "mezzanine"]),
    })


def extend(kit, prior):
    gray = kit.Area("gray_path", "灰道換班廊", 57, GROUND, indoor=True)
    gray.ceiling(1, 55, 8)
    gray.stand(4, "Ⅶ")
    gray.stand(8, "P")
    gray.stand(51, "Ⅹ")
    gray.prop("basement_door__storage_rack", 14)
    gray.prop("basement__notebook_desk", 32)
    gray.prop("basement__kerosene_heater", 35)
    gray.prop("dock_warehouse__bridge_lever", 46, y=17, support="wall")
    gray.lamp(32, 11)
    gray.lamp(47, 11)
    gray.features = {"landmark": "暖燈下的換班小桌。", "loop": "從內側扳動滑扣可往返電話亭。"}

    phone = kit.Area("phone_alley", "電話亭巷", 58, GROUND)
    phone.stand(4, "Ⅸ")
    phone.stand(8, "P")
    phone.stand(44, "Ⅺ")
    phone.stand(53, PLAZA_PORTAL)
    phone.prop("mezzanine__grating_stairs", 51, dx=11.2)
    phone.prop("anchor_phone_booth__flicker_lamp_post", 14)
    phone.prop("anchor_phone_booth__phone_booth", 29)
    phone.prop("anchor_phone_booth__news_rack", 34)
    phone.prop("anchor_phone_booth__leaning_bicycle", 39)
    phone.features = {"landmark": "亭門玻璃後的一盞暖燈。", "loop": "地面返回港區街道，開通後也可走灰道。打完電話可從東側維修階到廣場。"}

    rooms = {room.id: room for room in [*prior, gray, phone]}
    for room, x, glyph in (("basement_archive", 60, "Ⅵ"), ("harbor_street", 54, "Ⅷ")):
        _place(rooms[room], x, glyph)
    for glyph, room, x, _, _, _, _ in OBJECTS.values():
        _place(rooms[room], x, glyph)
    return [*prior, gray, phone]


def _place(room, x, glyph):
    row = room.ground - 1
    if room.grid.at(x, row) != ".":
        raise ValueError(f"{room.id}: service route overlaps the authored cell {x},{row}")
    room.stand(x, glyph, row=row)
