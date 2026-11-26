"""Scene 6.03 staging under the relay canopy and on the isolated booth feed."""

from ch6_relay_water import POWERED

MET = "ch6_su_studio_met"
TRIAL = "ch6_trial_broadcast_confirmed"
YARD_SU = "su_canopy"
BOOTH_SU = "su_booth"
MONITOR = "trial_monitor"

OBJECTS = (
    ("ⓢ", YARD_SU, "蘇", "broadcast_outside", 53, 19,
     ("和蘇確認錄音室", "Check the booth with Wake", "蘇と録音室を確認する")),
    ("ⓣ", BOOTH_SU, "蘇", "recording_booth", 22, 19,
     ("和蘇試音", "Check the microphone with Wake", "蘇とマイクを確認する")),
    ("ⓜ", MONITOR, "試音稿", "recording_booth", 18, 19,
     ("查看試音稿", "Read the rehearsal script", "音声テストの原稿を読む")),
)
PEOPLE = {
    YARD_SU: dict(spawn_requires_flag=POWERED, spawn_unless_flag=MET),
    BOOTH_SU: dict(spawn_requires_flag=MET),
}


def extend_canopy(room):
    room.ceiling(49, 54, 14)
    room.zone(49, "ch6_studio_light", blend=5)
    room.lamp(52, 15)
    room.features["landmark"] = "水位尺、前庭泵房與亮著白燈的錄音室雨棚。"


def extend_booth(room):
    room.zone(0, "ch6_studio_light", blend=5)
    room.grid.put(13, 13, ".")
    room.prop("recording_booth__glass_window", 8, y=15, support="wall")
    room.prop("recording_booth__foam_panels", 24, y=17, support="wall")
    console = dict(y=18, dy=-10, support="prop",
                   support_id="recording_booth__mixing_console", support_x=17, support_dy=4)
    room.prop("recording_booth__recording_desk_lamp", 17, dx=6, **console)
    room.prop("recording_booth__script_sheets", 18, dx=2, **console)
    room.prop("recording_booth__desk_microphone", 20, **console)
    room.features["landmark"] = "隔音窗、試音稿與麥克風。"
