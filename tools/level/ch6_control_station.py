"""Scene 6.04's booth contact and local control-room composition."""

from pathlib import Path
import json
import struct

OBJECT = "control_link"
STAGE = "ch6_lamp_control_room"
OBJECTS = (
    ("ⓛ", OBJECT, "控制室連線", "recording_booth", 29, 19,
     ("查看控制室連線", "Open the control-room feed", "制御室の回線を確認する")),
)
ART = "art/environment/scene_props/control_room"


def extend_booth(room):
    room.prop("control_room__sos_panel", 29, y=16, dy=8, support="wall")


def write_stage(root: Path):
    def sprite(name, pos, scale, **options):
        art = f"{ART}/control_room__{name}.png"
        with (root / art).open("rb") as stream:
            header = stream.read(24)
        if header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
            raise ValueError(f"{art}: expected PNG stage art")
        width = struct.unpack(">I", header[16:20])[0]
        return dict(kind="sprite", path=f"res://{art}", pos=pos, scale=scale, filter="linear",
                    source_width=width, glow=False, **options)

    layers = [
        dict(kind="gradient", top="#0b111f", bottom="#172738", parallax=0.0),
        dict(kind="rect", rect=[0, 16, 640, 15], color="#172436"),
        dict(kind="rect", rect=[0, 31, 640, 2], color="#32445c"),
        dict(kind="rect", rect=[0, 304, 640, 72], color="#111d2a"),
        sprite("monitor_wall", [50, 29], .54, id="noisy_display", modulate="#6f607c"),
        sprite("monitor_wall", [50, 29], .54, id="clear_display", modulate="#b7d4df", visible=False),
        sprite("relay_map_display", [401, 38], .34, id="relay_dim", modulate="#526575"),
        sprite("relay_map_display", [401, 38], .34, id="relay_active", modulate="#bfdbe6", visible=False),
        sprite("comm_console", [87, 188], .83, lighting="physical"),
        sprite("sos_panel", [589, 95], .35, id="call_alarm", visible=False),
    ]
    stage = {"camera": {"pos": [320, 180], "zoom": 1.0}, "floor": 335, "layers": layers}
    path = root / f"data/cutscene/stages/{STAGE}.json"
    path.write_text(json.dumps(stage, ensure_ascii=False, indent=1) + "\n", encoding="utf8", newline="\n")
