"""Scene 6.02 map additions, beside the existing forecourt approach."""

DIVERTED = "ch6_relay_water_diverted"
DRAINED = "ch6_relay_water_drained"
POWERED = "ch6_relay_powered"
OBJECTS = (
    ("ⓓ", "relay_diverter", "分流手輪", "broadcast_outside", 29, 17,
     ("操作分流手輪", "Operate the diversion valve", "分流弁を操作する")),
    ("ⓡ", "relay_drain", "退水控制盒", "broadcast_outside", 35, 18,
     ("操作退水控制盒", "Operate the drain control", "排水盤を操作する")),
    ("ⓟ", "relay_backup", "備援電源箱", "broadcast_outside", 45, 16,
     ("查看備援電源", "Check the backup power", "予備電源を確認する")),
)
PORTALS = (
    ("ⅵ", "relay_recording", "ch6_recording_booth", "recording_relay", "hidden", POWERED,
     "先讓水位降到白線下，再接通上層備援電源。",
     ("進錄音室", "Enter the recording booth", "録音室に入る")),
    ("ⅶ", "recording_relay", "ch6_broadcast_outside", "relay_recording", "door", "", "",
     ("回廣播站前庭", "Return to the relay yard", "中継所前庭に戻る")),
)
LOCK_TEXT = PORTALS[0][6]
LOCK_COPY = ("Lower the water below the white mark and connect backup power upstairs.",
             "水位を白線より下げてから、上層の予備電源をつなぐ。")
THEME = ("facility_floor", ["facility_wall"], "facility_panel", 0.0, "sky_storm",
         ["recording_booth", "broadcast_outside"])


def extend_forecourt(room):
    room.platform(26, 27, 19)
    room.platform(28, 31, 18)
    room.platform(34, 36, 19)
    room.platform(37, 39, 18)
    room.platform(40, 48, 17)
    room.stand(50, "ⅵ")
    room.prop("broadcast_outside__cooling_valve", 28, y=19, support="ground", react="ch6_diversion_wheel")
    room.prop("sluice_hall__release_console", 35, y=18, support="ground", react="ch6_drain_indicator")
    room.prop("abandoned_factory__power_panel", 45, y=16, support="ground", react="ch6_backup_indicator")
    room.lamp(39, 13)


def recording_booth(kit, ground):
    room = kit.Area("recording_booth", "廣播站錄音室", 34, ground, indoor=True)
    room.ceiling(1, 32, 12)
    room.stand(4, "ⅶ")
    room.stand(8, "P")
    room.prop("recording_booth__mixing_console", 17)
    room.prop("recording_booth__booth_stool", 23)
    room.prop("recording_booth__reel_recorder", 26)
    room.lamp(13, 13)
    room.lamp(24, 13)
    room.features = {"landmark": "窗後的調音台與錄音機。", "loop": "從原門回廣播站前庭。"}
    return room
