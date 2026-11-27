"""Scene 6.05's eaves, public route and return from Ali's porch."""

from pathlib import Path

KNOWN = "knows_ali_address"
ARRIVED = "ch6_ali_rain_arrival_resolved"
ON_TIME = "ch6_ali_rain_arrived_on_time"
RELAYED = "ali_call_relayed"
START = "rain_route_board"
DOOR = "ali_eaves_door"
PORCH = "ali_porch_note"

PORTALS = (
    ("ⅷ", "relay_rain", "ch6_rain_chase_alley", "rain_relay", "door", RELAYED,
     "先從錄音室接到燈轉來的電話。", ("往市集外街", "Enter the market side street", "市場の外通りへ")),
    ("ⅸ", "rain_relay", "ch6_broadcast_outside", "relay_rain", "door", "", "",
     ("回廣播站前庭", "Return to the relay yard", "中継所前庭に戻る")),
    ("ⅹ", "rain_public_porch", "ch6_ali_homefront", "porch_public_rain", "door", "", "",
     ("走外街到門廊", "Take the public street to the porch", "外通りから玄関先へ")),
    ("ⅺ", "porch_public_rain", "ch6_rain_chase_alley", "rain_public_porch", "door", "", "",
     ("回市集外街", "Return to the side street", "市場の外通りへ戻る")),
    ("ⅻ", "rain_eaves_porch", "ch6_ali_homefront", "porch_eaves_rain", "hidden", ON_TIME,
     "沿乾台到便門應聲，先和阿梨確認去哪裡。", ("從便門到門廊", "Take the eaves gate to the porch", "軒下の勝手口から玄関先へ")),
    ("◈", "porch_eaves_rain", "ch6_rain_chase_alley", "rain_eaves_porch", "hidden", ON_TIME,
     "便門依阿梨的回覆開放。", ("回屋簷便門", "Return to the eaves gate", "軒下の勝手口へ戻る")),
    ("◇", "porch_market", "ch6_rain_chase_alley", "rain_market", "door", ARRIVED,
     "先在亮處確認阿梨的回覆。", ("從後門回市集路口", "Take the rear door to the market corner", "裏口から市場の角へ")),
    ("◆", "rain_market", "ch6_ali_homefront", "porch_market", "door", ARRIVED,
     "後門在阿梨回覆後才開放。", ("從市集路口回門廊", "Return to the porch from the market corner", "市場の角から玄関先へ")),
)
LOCKS = {
    "先從錄音室接到燈轉來的電話。": ("Receive the forwarded call from Lamp in the booth first.", "まず録音室で灯からの転送電話を受ける。"),
    "沿乾台到便門應聲，先和阿梨確認去哪裡。": ("Reach the eaves gate and ask Ali where she wants to go.", "乾いた足場から勝手口に行き、どこへ向かうかアーリーに尋ねる。"),
    "便門依阿梨的回覆開放。": ("The eaves gate opens after Ali responds.", "アーリーの返事のあとで勝手口が開く。"),
    "先在亮處確認阿梨的回覆。": ("Confirm Ali's reply at the lit porch first.", "まず明るい玄関先でアーリーの返事を確認する。"),
    "後門在阿梨回覆後才開放。": ("The rear door opens after Ali responds.", "アーリーの返事のあとで裏口が開く。"),
}
OBJECTS = (
    ("ⓥ", START, "雨棚下的路標", "rain_chase_alley", 12, 19,
     ("查看兩條路線", "Check both routes", "二つの経路を確認する")),
    ("ⓤ", DOOR, "屋簷便門", "rain_chase_alley", 64, 14,
     ("在便門應聲", "Call from the eaves gate", "勝手口から声をかける")),
    ("ⓝ", PORCH, "亮著燈的門廊", "ali_homefront", 17, 19,
     ("查看門口留下的話", "Read the message at the porch", "玄関先の伝言を読む")),
)
THEME = ("asphalt", ["shopfront", "shutter_block"], None, 0.0, "sky_storm",
         ["rain_chase_alley", "harbor_plaza", "sluice_hall", "neon_market"])
SPEC = "res://data/levels/features/ch6_rain_time_trial.tres"


def extend_yard(room):
    room.stand(47, "ⅷ", 16)


def rain_alley(kit, ground):
    room = kit.Area("rain_chase_alley", "市集外街與屋簷", 82, ground)
    room.stand(4, "ⅸ")
    room.stand(7, "◆")
    room.stand(9, "P")
    room.stand(73, "ⅹ")
    room.platform(15, 21, 18)
    room.platform(20, 28, 16)
    room.platform(27, 39, 14)
    room.platform(36, 49, 13)
    room.platform(49, 58, 14)
    room.platform(57, 70, 15)
    room.stand(68, "ⅻ", 14)
    room.ceiling(8, 27, 5)
    room.ceiling(26, 36, 7)
    room.ceiling(51, 69, 8)
    # Bolt the two entry treads to the same sheltered wall as the sign and ladder.
    room.prop("sluice_hall__catwalk_section", 16, y=18, dy=7, support="wall")
    room.prop("sluice_hall__catwalk_section", 21, y=16, dy=7, support="wall")
    room.prop("rain_chase_alley__alley_neon_noodle", 8, y=14, support="wall")
    room.prop("rain_chase_alley__chalk_arrow_wall", 15, y=15, support="wall")
    room.prop("rain_chase_alley__hanging_fire_ladder", 23, y=15, support="wall")
    room.prop("rain_chase_alley__alley_dumpster", 42, y=19, support="ground")
    room.prop("rain_chase_alley__shortcut_gate", 67, y=14, support="ground")
    room.lamp(59, 11)
    room.lamp(73, 14)
    room.features = {
        "landmark": "紅色市場招牌指向外街，屋簷下的粉筆箭頭指向三樓便門。",
        "loop": "外街、屋簷便門及門廊後門在市集路口相通。",
    }
    return room


def porch(kit, ground):
    room = kit.Area("ali_homefront", "阿梨家門廊", 34, ground, indoor=True)
    room.ceiling(1, 32, 12)
    room.stand(4, "ⅺ")
    room.stand(7, "◈")
    room.stand(10, "P")
    room.stand(28, "◇")
    room.prop("rain_chase_alley__ali_window", 16, y=16, support="wall")
    room.prop("harbor_plaza__fallen_umbrellas", 21)
    room.lamp(14, 14)
    room.lamp(25, 14)
    room.features = {"landmark": "屋號與留傘的亮門廊。", "loop": "後門往市集路口，前門接外街及屋簷。"}
    return room


def write_spec(root: Path):
    destination = root / SPEC.removeprefix("res://")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("""[gd_resource type="Resource" load_steps=2 format=3]

[ext_resource type="Script" path="res://data/scripts/traversal_trial_data.gd" id="1"]

[resource]
script = ExtResource("1")
start_source = &"ch6_rain_route_board"
arrival_source = &"ch6_ali_eaves_door"
normal_scene = &"ch6_t_ali_run_arm"
guided_scene = &"ch6_t_ali_guide_arm"
gate_flag = &"knows_ali_address"
resolved_flag = &"ch6_ali_rain_arrival_resolved"
start_cell = Vector2i(20, 17)
normal_seconds = 23.0
guided_seconds = 58.0
text_path = "res://data/levels/features/ch6_rain_trial_ui.json"
""", encoding="utf8", newline="\n")
