"""Roof and bedside geometry for Hollow Shell scene 16."""

LEDGER_SAVED = "ch4_original_ledger_saved"
ROOF_HEARD = "ch4_roof_radio_heard"
MIC_REQUESTED = "ch4_lamp_mic_requested"
MESSAGE_RECORDED = "ch4_lamp_message_recorded"

POINTS = {
    "roof_lantern": ("factory_roof", 28, 19),
    "lamp_bedside": ("ward_lamp_bay", 18, 19),
}
STATIONS = {"roof_lantern": "屋頂收訊箱", "lamp_bedside": "側窗床位"}
GLYPHS = {"roof_lantern": "ⓚ", "lamp_bedside": "ⓠ"}
PROMPTS = {"roof_lantern": "聽燈的通訊", "lamp_bedside": "在床邊架好話筒"}

PORTALS = {
    "⟰": ("office_roof", "factory_roof", "roof_office", "從維修樓梯上屋頂", LEDGER_SAVED,
          "先在辦公桌核對原帳，再從樓梯回程。"),
    "⟱": ("roof_office", "factory_office", "office_roof", "沿樓梯回原帳辦公室", "", ""),
    "⇣": ("roof_safety", "factory_safety", "safety_roof", "下樓回清理線安全臺", "", ""),
    "⇡": ("safety_roof", "factory_roof", "roof_safety", "從安全臺上屋頂", LEDGER_SAVED,
          "先在舊廠辦公室核對原帳。"),
    "⇢": ("ward_lamp_bay", "ward_lamp_bay", "lamp_bay_ward", "去病房東側床位", MIC_REQUESTED,
          "先在屋頂聽過燈的通訊，再帶話筒來。"),
    "⇠": ("lamp_bay_ward", "nursing_ward", "ward_lamp_bay", "回安養病房走廊", "", ""),
}
THEMES = {
    "factory_roof": ("steel_plate", ["warehouse", "brick_block"], "hangar_wall",
                     0.14, "sky_storm", ["rooftop", "broadcast_roof", "abandoned_factory"]),
    "ward_lamp_bay": ("facility_floor", ["facility_wall"], "facility_panel", 0.0,
                      "sky_storm", ["nursing_ward", "clinic"]),
}


def install_ward_door(area):
    area.stand(48, "⇢")


def build_ward_bay(kit, ground):
    area = kit.Area("ward_lamp_bay", "病房側窗床位", 34, ground, indoor=True)
    area.ceiling(1, 32, 6)
    area.zone(0, "clinic_ward")
    area.stand(5, "⇠")
    area.stand(8, "P")
    area.lamp(16, 7)
    area.lamp(27, 7)
    area.prop("nursing_ward__rain_window_wide", 14, y=13, support="wall")
    area.prop("nursing_ward__ward_bed", 13)
    area.prop("nursing_ward__bed_curtain", 11)
    area.prop("nursing_ward__lamp_bedside_cabinet", 18)
    area.prop("nursing_ward__bedside_radio", 18, y=17, dy=-1, support="prop",
              support_id="nursing_ward__lamp_bedside_cabinet", support_x=18)
    area.prop("nursing_ward__visitor_chair", 24)
    area.features = {"landmark": "隔簾旁能錄留言的床頭收音機。"}
    return area


def install_office_stairs(area):
    area.stand(14, "⟰")


def install_safety_stairs(area):
    area.stand(33, "⇡")


def build_roof(kit, ground):
    area = kit.Area("factory_roof", "廠房回程梯與屋頂", 60, ground, indoor=False)
    area.zone(0, "rooftop")
    area.stand(3, "⟱")
    area.stand(10, "P")
    area.stand(53, "⇣")
    area.prop("rooftop__stairwell_hut", 1)
    area.prop("rooftop__rain_collecting_barrel", 11)
    area.prop("broadcast_roof__roof_railing", 15)
    area.prop("rooftop__antenna_forest", 22)
    area.prop("rooftop__dish_pair", 30)
    area.prop("broadcast_roof__generator_unit", 28)
    area.prop("broadcast_roof__roof_railing", 39, y=ground - 1)   # 頭上有維修平台：寫明站在屋頂地面
    area.prop("rooftop__stairwell_hut", 51)
    area.lamp(27, ground - 6)
    area.lamp(49, ground - 5)
    # 冷卻機的維修平台（地圖線）：欄杆後面踩一階上去，平台盡頭有一包信用點，從地面看得到、要繞上去才拿得到。
    area.platform(36, 39, ground - 4)
    area.platform(41, 48, ground - 7)
    area.stand(46, "q", row=ground - 8)
    area.stand(44, "♣", row=ground - 8)   # 冷卻機的維修卡（ST-63）
    area.features = {
        "landmark": "雨裡的天線與低亮度收訊箱。",
        "loop": "辦公室樓梯上屋頂，另一座梯塔回安全臺。",
        "secret": "冷卻機維修平台上的信用點（x=46）",
    }
    return area
