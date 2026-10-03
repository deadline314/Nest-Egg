"""Write the cutscene stage definitions that use the Qwen-generated room backgrounds (NE-65).

The pictures come from tools/assets/qwen_scenes.py (art/environment/stages/*.webp, 1536x864, drawn at scale 0.5 so one
picture covers the 640x360 stage with a margin for camera moves). Everything animated (glow flicker and pulse, dust motes,
grain) is a data layer on top of the picture, so a stage is still just a JSON file. Rerunning rewrites the files.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STAGES = ROOT / "data" / "cutscene" / "stages"


def bg(name: str, dy: float = 0.0, **extra) -> dict:
    """dy shifts the picture so its floor line meets the stage's floor (where the characters stand)."""
    layer = {"kind": "sprite", "path": f"res://art/environment/stages/{name}.webp", "pos": [-64, -36 + dy], "scale": 0.5, "filter": "linear"}
    layer.update(extra)
    return layer


def glow(pos, radius, color, intensity, alpha, **extra) -> dict:
    layer = {"kind": "glow", "pos": pos, "radius": radius, "color": color, "intensity": intensity, "additive": True, "alpha": alpha}
    layer.update(extra)
    return layer


def motes(count, color, opacity, area, drift, size, seed) -> dict:
    return {"kind": "motes", "count": count, "color": color, "opacity": opacity, "area": area, "drift": drift, "size": size, "seed": seed}


def grain(amount, opacity, **extra) -> dict:
    layer = {"kind": "grain", "amount": amount, "opacity": opacity, "depth": "front"}
    layer.update(extra)
    return layer


STAGE_LAYERS = {
    "old_k_shop": [
        {"kind": "gradient", "top": "#1a1410", "bottom": "#2c2018", "parallax": 0.0},
        bg("old_k_shop", modulate=[1.7, 1.55, 1.45, 1.0]),
        glow([321, 40], 250, "#ffb066", 0.9, 0.5, flicker=0.05),
        glow([14, 112], 120, "#a070e8", 0.8, 0.45, flicker=0.12),
        motes(46, "#ffd9a0", 0.55, [150, 30, 360, 260], [2, -4], 1.3, 4),
        grain(50, 0.06),
    ],
    "old_k_shop_dawn": [
        {"kind": "gradient", "top": "#10161c", "bottom": "#222a30", "parallax": 0.0},
        bg("old_k_shop_dawn", modulate=[1.6, 1.6, 1.7, 1.0]),
        glow([26, 110], 170, "#9ab8d8", 0.8, 0.45, pulse=0.08, pulse_depth=0.25),
        motes(30, "#cfe0ff", 0.4, [0, 30, 320, 260], [3, -3], 1.2, 6),
        grain(50, 0.06),
    ],
    "hangar_red": [
        {"kind": "gradient", "top": "#120508", "bottom": "#2a0c10", "parallax": 0.0},
        bg("hangar_red", dy=-10, modulate=[1.25, 1.2, 1.2, 1.0]),
        glow([320, 150], 340, "#ff2a18", 0.9, 0.22, flicker=0.35),
        glow([226, 20], 150, "#ff2a1a", 1.0, 0.6, pulse=0.9, pulse_depth=0.85),
        glow([406, 20], 150, "#ff2a1a", 1.0, 0.6, pulse=0.9, pulse_depth=0.85, phase=0.5),
        glow([-45, 168], 130, "#ff2a1a", 1.0, 0.55, pulse=0.9, pulse_depth=0.8, phase=0.25),
        glow([677, 168], 130, "#ff2a1a", 1.0, 0.55, pulse=0.9, pulse_depth=0.8, phase=0.75),
        {"kind": "sprite", "path": "res://art/environment/props/fuel_tank.png", "pos": [30, 200], "scale": 0.6},
        motes(54, "#ff7a45", 0.6, [0, 40, 640, 230], [5, -10], 1.2, 12),
        grain(60, 0.08),
    ],
    "terminal_room": [
        {"kind": "gradient", "top": "#060c12", "bottom": "#10202c", "parallax": 0.0},
        bg("terminal_room", dy=-12, modulate=[1.7, 1.7, 1.7, 1.0]),
        glow([356, 190], 190, "#35e0ff", 1.0, 0.4, pulse=0.25, pulse_depth=0.3),
        {"kind": "sprite", "path": "res://art/environment/props/terminal_holo.png", "pos": [323, 89], "scale": 0.384, "filter": "linear"},
        motes(64, "#35e0ff", 0.6, [0, 30, 640, 240], [0, -9], 1.1, 21),
        grain(40, 0.07),
    ],
    "transfer_corridor": [
        {"kind": "gradient", "top": "#0c1218", "bottom": "#18222c", "parallax": 0.0},
        bg("transfer_corridor"),
        glow([163, 36], 170, "#cfe8ff", 0.9, 0.3, flicker=0.15),
        glow([477, 36], 190, "#cfe8ff", 0.9, 0.3),
        motes(26, "#cfe0ff", 0.3, [0, 40, 640, 220], [2, -2], 1.0, 33),
        grain(50, 0.07),
    ],
    "white_room": [
        {"kind": "gradient", "top": "#f2f1ec", "bottom": "#d8d4c8", "parallax": 0.0},
        bg("white_room"),
        glow([320, 100], 260, "#ffffff", 0.5, 0.3, pulse=0.07, pulse_depth=0.3),
        {"_keep_kind": "poly"},
        motes(36, "#fffdf2", 0.55, [0, 20, 640, 260], [1.5, -2.5], 1.4, 41),
        grain(420, 0.35, color="#7a7266"),
        {"kind": "rect", "rect": [-100, -100, 840, 520], "color": "#f8f2e0", "alpha": 0.18, "depth": "front"},
    ],
}


def expand(layers: list, existing: dict) -> list:
    """Replace {"_keep_kind": k} placeholders by the layers of kind k from the current stage file (story props like the row of cubes)."""
    out = []
    for layer in layers:
        if "_keep_kind" in layer:
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
        path.write_text(json.dumps(data, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"ok    {name}: {len(data['layers'])} layers")
    return 0


if __name__ == "__main__":
    sys.exit(main())
