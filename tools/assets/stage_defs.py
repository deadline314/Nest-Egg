"""Write the cutscene stage definitions that use the Qwen-generated room backgrounds (NE-65).

The pictures come from tools/assets/qwen_scenes.py (art/environment/stages/*.webp, 1536x864, drawn at scale 0.5 so one
picture covers the 640x360 stage with a margin for camera moves). Everything animated (glow flicker and pulse, dust motes,
grain) is a data layer on top of the picture, so a stage is still just a JSON file. Rerunning rewrites the files.
"""
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
STAGES = ROOT / "data" / "cutscene" / "stages"
ART = ROOT / "art" / "environment" / "stages"

# The row of little feet in the white room (BG-6): one cel-shaded pair of feet (white_room_foot.webp, from
# tools/assets/qwen_scenes.py) repeated FEET_COUNT times at an equal pitch, centred on the stage, soles on the floor line.
FEET_COUNT = 16
FEET_PITCH = 28.0      # stage units between two pairs
FEET_WIDTH = 22.0      # stage units: width of one pair (the picture's height follows its proportions)
FEET_CENTER_X = 320.0
FEET_FLOOR_Y = 286.0   # where the soles stand (the old polygons ended here)
FEET_FADE = 0.3        # fraction of the picture height over which the shins fade out at the top
FEET_PX_PER_UNIT = 4   # texture pixels per stage unit (the camera zooms to 1.8x, so keep it crisp)


def bg(name: str, dy: float = 0.0, **extra) -> dict:
    """dy shifts the picture so its floor line meets the stage's floor (where the characters stand)."""
    layer = {"kind": "sprite", "path": f"res://art/environment/stages/{name}.webp", "pos": [-64, -36 + dy], "scale": 0.5, "filter": "linear"}
    layer.update(extra)
    return layer


def feet_layer() -> dict | None:
    """Compose the 16 pairs into one wide picture (art/environment/stages/white_room_feet.webp) and return its sprite layer.
    Returns None (and says where) when the single-pair picture is missing, so the caller keeps the old stage layers."""
    src = ART / "white_room_foot.webp"
    if not src.exists():
        print(f"ERROR {src}: missing, run tools/assets/qwen_scenes.py --only white_room_foot first; the white room keeps its old feet", file=sys.stderr)
        return None
    pair = Image.open(src).convert("RGBA")
    pw = round(FEET_WIDTH * FEET_PX_PER_UNIT)
    ph = max(1, round(pw * pair.height / pair.width))
    pair = pair.resize((pw, ph), Image.LANCZOS)
    total_units = FEET_PITCH * (FEET_COUNT - 1) + FEET_WIDTH
    canvas = Image.new("RGBA", (round(total_units * FEET_PX_PER_UNIT), ph), (0, 0, 0, 0))
    base = np.asarray(pair).astype(np.float32)
    ramp = np.clip(np.arange(ph, dtype=np.float32) / (FEET_FADE * ph), 0.0, 1.0)  # the shins fade out at the top instead of ending in a straight cut
    base[..., 3] *= ramp[:, None]
    for i in range(FEET_COUNT):
        tone = 1.0 - 0.015 * ((i * 7) % 4) / 3.0  # a faint, repeatable variation so the row does not look stamped
        arr = base.copy()
        arr[..., :3] *= tone
        canvas.alpha_composite(Image.fromarray(np.clip(arr + 0.5, 0, 255).astype(np.uint8), "RGBA"), (round(i * FEET_PITCH * FEET_PX_PER_UNIT), 0))
    ART.mkdir(parents=True, exist_ok=True)
    out = ART / "white_room_feet.webp"
    canvas.save(out, "WEBP", lossless=True, method=6)
    scale = 1.0 / FEET_PX_PER_UNIT
    return {"kind": "sprite", "path": "res://art/environment/stages/white_room_feet.webp",
            "pos": [round(FEET_CENTER_X - total_units / 2.0, 2), round(FEET_FLOOR_Y - ph * scale, 2)], "scale": scale, "filter": "linear"}


# Wataru's bed (BG-11): a child's bed (qwen_scenes.py old_k_shop_bed / old_k_shop_dawn_bed, 440 px wide, drawn at scale 0.25)
# whose mattress top sits where the "sit" pose rests (stage y 277 at x=520, actors scale 2.0), foot end at x=500 so the calves hang free.
BED_POS = [500, 243]
BED_SCALE = 0.25


def bed(name: str, **extra) -> dict:
    return {"kind": "sprite", "path": f"res://art/environment/stages/{name}.webp", "pos": BED_POS, "scale": BED_SCALE, "filter": "linear", **extra}


def glow(pos, radius, color, intensity, alpha, **extra) -> dict:
    layer = {"kind": "glow", "pos": pos, "radius": radius, "color": color, "intensity": intensity, "additive": True, "alpha": alpha}
    layer.update(extra)
    return layer


def motes(count, color, opacity, area, drift, size, seed) -> dict:
    return {"kind": "motes", "count": count, "color": color, "opacity": opacity, "area": area, "drift": drift, "size": size, "seed": seed}


def grain(amount, opacity, reason, **extra) -> dict:
    """畫面顆粒只給回憶、非現實這類特殊舞台用，reason 寫明理由；一般舞台不加（BG-27）。"""
    layer = {"kind": "grain", "amount": amount, "opacity": opacity, "depth": "front", "reason": reason}
    layer.update(extra)
    return layer


def scene_bg(name: str, **extra) -> dict:
    """A BG-11 scene background (art/environment/scenes, 1536x864) used as a stage picture, drawn like the room stages."""
    layer = {"kind": "sprite", "path": f"res://art/environment/scenes/{name}.webp", "pos": [-64, -36.0], "scale": 0.5, "filter": "linear", "source_width": 1536}
    layer.update(extra)
    return layer


# Extra top-level fields of a stage file: the floor line the actors stand on and the furniture painted into the picture
# (measured on the picture in stage coordinates; kinds and their allowed sizes are in data/cutscene/stage_proportions.json).
STAGE_FIELDS = {
    # 客人簿的房間（BG-46）：榻榻米上一張矮桌、左右各一個坐墊。站著的人腳在 y=278；坐墊的座面 y=262。
    # 家具是照 3.8～4.0 倍的演員畫的：站著要把鏡頭拉遠到 0.84，坐在墊上用 1.0 就放得下。
    "ch2_guest_book_room": {
        "floor": 278,
        "furniture": [
            {"id": "low_table", "kind": "low_table", "rect": [250, 236, 120, 40], "plane": "actor"},
            {"id": "cushion_left", "kind": "floor_cushion", "rect": [185, 262, 83, 16], "plane": "actor"},
            {"id": "cushion_right", "kind": "floor_cushion", "rect": [352, 262, 93, 16], "plane": "actor"},
        ],
    },
}

STAGE_LAYERS = {
    "ch2_guest_book_room": [
        {"kind": "gradient", "top": "#140a10", "bottom": "#2a141c", "parallax": 0.0},
        scene_bg("guest_book_room"),
        glow([480, 120], 170, "#ffc890", 0.8, 0.4, pulse=0.07, pulse_depth=0.2),
        glow([300, 250], 150, "#ff9a6a", 0.5, 0.18),
        motes(22, "#ffd9b0", 0.35, [120, 40, 420, 230], [1.5, -2.5], 1.1, 46),
    ],
    "old_k_shop": [
        {"kind": "gradient", "top": "#1a1410", "bottom": "#2c2018", "parallax": 0.0},
        bg("old_k_shop", modulate=[1.25, 1.2, 1.15, 1.0]),
        bed("old_k_shop_bed", modulate=[1.25, 1.2, 1.15, 1.0]),
        glow([321, 40], 250, "#ffb066", 0.9, 0.5, flicker=0.05),
        glow([14, 112], 120, "#a070e8", 0.8, 0.45, flicker=0.12),
        motes(46, "#ffd9a0", 0.55, [150, 30, 360, 260], [2, -4], 1.3, 4),
    ],
    "old_k_shop_dawn": [
        {"kind": "gradient", "top": "#10161c", "bottom": "#222a30", "parallax": 0.0},
        bg("old_k_shop_dawn", modulate=[1.15, 1.15, 1.2, 1.0]),
        bed("old_k_shop_dawn_bed", modulate=[1.15, 1.15, 1.2, 1.0]),
        glow([26, 110], 170, "#9ab8d8", 0.8, 0.45, pulse=0.08, pulse_depth=0.25),
        motes(30, "#cfe0ff", 0.4, [0, 30, 320, 260], [3, -3], 1.2, 6),
    ],
    "hangar_red": [
        {"kind": "gradient", "top": "#120508", "bottom": "#2a0c10", "parallax": 0.0},
        bg("hangar_red", dy=-10, modulate=[1.1, 1.1, 1.1, 1.0]),
        glow([320, 150], 340, "#ff2a18", 0.9, 0.22, flicker=0.35),
        glow([226, 20], 150, "#ff2a1a", 1.0, 0.6, pulse=0.9, pulse_depth=0.85),
        glow([406, 20], 150, "#ff2a1a", 1.0, 0.6, pulse=0.9, pulse_depth=0.85, phase=0.5),
        glow([-45, 168], 130, "#ff2a1a", 1.0, 0.55, pulse=0.9, pulse_depth=0.8, phase=0.25),
        glow([677, 168], 130, "#ff2a1a", 1.0, 0.55, pulse=0.9, pulse_depth=0.8, phase=0.75),
        {"kind": "sprite", "path": "res://art/environment/props/fuel_tank.png", "pos": [30, 200], "scale": 0.6},
        motes(54, "#ff7a45", 0.6, [0, 40, 640, 230], [5, -10], 1.2, 12),
    ],
    "terminal_room": [
        {"kind": "gradient", "top": "#060c12", "bottom": "#10202c", "parallax": 0.0},
        bg("terminal_room", dy=-12, modulate=[1.35, 1.35, 1.35, 1.0], source_width=1536),
        glow([315, 180], 190, "#35e0ff", 1.0, 0.4, pulse=0.25, pulse_depth=0.3),
        {"kind": "sprite", "path": "res://art/environment/props/terminal_holo.png", "pos": [265, 132.36], "scale": 0.205, "filter": "linear", "source_width": 487,
         "support_rect": [258, 216, 116, 4]},
        motes(64, "#35e0ff", 0.6, [0, 30, 640, 240], [0, -9], 1.1, 21),
    ],
    "transfer_corridor": [
        {"kind": "gradient", "top": "#0c1218", "bottom": "#18222c", "parallax": 0.0},
        bg("transfer_corridor"),
        glow([6, 16], 170, "#cfe8ff", 0.9, 0.3, flicker=0.15),
        glow([306, 16], 190, "#cfe8ff", 0.9, 0.3),
        glow([612, 16], 170, "#cfe8ff", 0.9, 0.3, flicker=0.1),
        motes(26, "#cfe0ff", 0.3, [0, 40, 640, 220], [2, -2], 1.0, 33),
    ],
    "white_room": [
        {"kind": "gradient", "top": "#f2f1ec", "bottom": "#d8d4c8", "parallax": 0.0},
        bg("white_room"),
        glow([320, 100], 260, "#ffffff", 0.5, 0.3, pulse=0.07, pulse_depth=0.3),
        {"_build": "white_room_feet", "_fallback_kind": "poly"},
        motes(36, "#fffdf2", 0.55, [0, 20, 640, 260], [1.5, -2.5], 1.4, 41),
        grain(140, 0.2, "白房間是記憶裡的畫面，少量顆粒表示這不是現實。", color="#7a7266"),
        {"kind": "rect", "rect": [-100, -100, 840, 520], "color": "#f8f2e0", "alpha": 0.18, "depth": "front"},
    ],
}


def expand(layers: list, existing: dict) -> list:
    """Replace {"_keep_kind": k} placeholders by the layers of kind k from the current stage file (story props like the row of cubes)."""
    out = []
    for layer in layers:
        if "_build" in layer:  # a layer made by code (the white room's row of feet); on failure keep the old layers of kind _fallback_kind
            built = feet_layer() if layer["_build"] == "white_room_feet" else None
            if built is not None:
                out.append(built)
            else:
                out.extend(l for l in existing.get("layers", []) if l.get("kind") == layer.get("_fallback_kind"))
        elif "_keep_kind" in layer:
            out.extend(l for l in existing.get("layers", []) if l.get("kind") == layer["_keep_kind"])
        else:
            out.append(layer)
    return out


def main() -> int:
    only = sys.argv[1:]
    for name, layers in STAGE_LAYERS.items():
        if only and name not in only:
            continue
        path = STAGES / f"{name}.json"
        data = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {"camera": {"pos": [320, 180], "zoom": 1.0}}
        data["layers"] = expand(layers, data)
        data.update(STAGE_FIELDS.get(name, {}))
        path.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"ok    {name}: {len(data['layers'])} layers")
    return 0


if __name__ == "__main__":
    sys.exit(main())
