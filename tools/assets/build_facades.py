"""Assemble building facade modules from rendered kit pieces and patch the facade data (NE-57 / NE-59).

Usage: python tools/assets/build_facades.py [--only ID ...]

Needs the kit renders (render_model.tscn with a "glow" job, then kit_cells.py) in assets_src/work/kits/.
Reads assets_src/pipeline/facades.json. A module is one or more kit cells laid side by side (the cell ids come from
kit_cells.py's numbered preview), stretched to the module size (64 x 40 / 32 / 8 logical px, texture_scale pixels per px):
  ground: storefront / garage / door       body: standard floor       cap: parapet strip
Per module it writes art/environment/facades/<id>_g<i>|_b<i>|_cap<i>.png with _n.png (normals) and _glow.png (window light):
every window in the kit's glass mask is lit with probability `light_chance`, in a colour picked from `light_colors` (scaled by `light_gain`: big bright windows next to the player flatten dark-scene readability, see check below)
(fixed seed per module so a rebuild gives the same picture). Colour grading comes from the JSON.
Then data/environment/facades/<id>.tres gets its ground / body / cap arrays rewritten.
Facades with no kit (curtain-wall towers, facility walls) use "generated": a wall tiled from a processed terrain
material (art/environment/materials/<wall_material>_body{,_n}.png) with a window grid drawn over it:
  "generated": {"wall_material": "glass_curtain", "tile_world": 48,
                "windows": {"ground": {...}, "body": {"cols": 8, "rows": 3, "w": 6.5, "h": 8, "glass": [r, g, b]}, "cap": null}}
Windows are recessed boxes (frame, dark glass, bevelled normals) and are lit like kit windows (light_chance / colors / gain).
"""
import argparse
import json
import random
import re
import sys
import zlib
from pathlib import Path

import cv2
import numpy as np
import decor
from PIL import Image
from scipy import ndimage

sys.path.insert(0, str(Path(__file__).resolve().parent))  # decor.py sits next to this script
ROOT = Path(__file__).resolve().parents[2]
KITS = ROOT / "assets_src" / "work" / "kits"
PIPELINE = ROOT / "assets_src" / "pipeline" / "facades.json"
OUT = ROOT / "art" / "environment" / "facades"
DATA = ROOT / "data" / "environment" / "facades"
MODULE_W = 64.0
HEIGHTS = {"ground": 40.0, "body": 32.0, "cap": 8.0}
SUFFIX = {"ground": "g", "body": "b", "cap": "cap"}
LUMA = np.array([0.299, 0.587, 0.114], dtype=np.float32)


class Kit:
    def __init__(self, name: str):
        self.color = Image.open(KITS / f"{name}.png").convert("RGBA")
        self.normal = Image.open(KITS / f"{name}_n.png").convert("RGBA")
        glow = KITS / f"{name}_glow.png"
        self.glow = Image.open(glow).convert("RGBA") if glow.exists() else None
        self.boxes = json.loads((KITS / f"{name}_cells.json").read_text(encoding="utf-8"))


def compose(kit_image: Image.Image, boxes: list, cells: list[int], crop, size: tuple[int, int], resample) -> Image.Image:
    """Lay the cells side by side, optionally crop (fractions), and stretch to size."""
    pieces = []
    for c in cells:
        x0, y0, x1, y1 = boxes[c]
        pieces.append(kit_image.crop((x0 + 2, y0 + 2, x1 - 2, y1 - 2)))
    height = max(p.height for p in pieces)
    width = sum(int(p.width * height / p.height) for p in pieces)
    strip = Image.new("RGBA", (width, height))
    x = 0
    for p in pieces:
        w = int(p.width * height / p.height)
        strip.paste(p.resize((w, height), Image.LANCZOS), (x, 0))
        x += w
    if crop:
        strip = strip.crop((int(crop[0] * width), int(crop[1] * height), int(crop[2] * width), int(crop[3] * height)))
    return strip.resize(size, resample)


def grade(a: np.ndarray, g: dict) -> np.ndarray:
    a = a ** float(g.get("gamma", 1.0))
    lum = a @ LUMA
    a = lum[..., None] + (a - lum[..., None]) * float(g.get("saturation", 1.0))
    a = (a - 0.5) * float(g.get("contrast", 1.0)) + 0.5
    a = a * float(g.get("brightness", 1.0)) * np.array(g.get("tint", [1, 1, 1]), dtype=np.float32)
    return np.clip(a, 0.0, 1.0)


def soften(rgba: np.ndarray, sigma: float) -> np.ndarray:
    """Soft-edged glow: premultiplied blur (colours do not bleed to black) plus a faint wide halo, so a lit window is
    not a hard-edged rectangle."""
    a = rgba[..., 3:4]
    pre = np.concatenate([rgba[..., :3] * a, a], axis=2)
    out = np.maximum(cv2.GaussianBlur(pre, (0, 0), sigma), cv2.GaussianBlur(pre, (0, 0), sigma * 3.0) * 0.4)
    alpha = np.clip(out[..., 3:4], 1e-4, 1.0)
    return np.concatenate([np.clip(out[..., :3] / alpha, 0.0, 1.0), np.clip(out[..., 3:4], 0.0, 1.0)], axis=2)


def window_light(mask: np.ndarray, rng: random.Random, chance: float, colors: list, gain: float) -> np.ndarray:
    """RGBA glow image: each connected window in `mask` is lit (or not) as a whole."""
    # Panes of one window are separated by mullions: dilate first so a whole window is one lit/unlit unit.
    labels, count = ndimage.label(ndimage.binary_dilation(mask, iterations=max(2, mask.shape[1] // 90)))
    labels = labels * mask
    out = np.zeros(mask.shape + (4,), dtype=np.float32)
    ys = np.linspace(1.0, 0.7, mask.shape[0], dtype=np.float32)[:, None]
    chosen = [i for i in range(1, count + 1) if rng.random() <= chance]
    if count > 0 and not chosen:
        chosen = [rng.randint(1, count)]  # a floor with windows never goes fully dark: the data promises a glow layer
    for i in chosen:
        sel = labels == i
        if sel.sum() < 12:
            continue
        color = np.array(rng.choice(colors), dtype=np.float32) * rng.uniform(0.75, 1.0) * gain
        out[sel, :3] = color
        out[sel, 3] = (0.95 * np.broadcast_to(ys, mask.shape))[sel]
    return out


MATERIALS = ROOT / "art" / "environment" / "materials"


def tile_to(image: Image.Image, size: tuple[int, int], period: int) -> Image.Image:
    base = image.convert("RGBA").resize((period, period), Image.LANCZOS)
    out = Image.new("RGBA", size)
    for y in range(0, size[1], period):
        for x in range(0, size[0], period):
            out.paste(base, (x, y))
    return out


def _chamfer(x0: float, y0: float, x1: float, y1: float, cut: float) -> list[tuple[float, float]]:
    """Rectangle with its four corners cut off (an octagon): the window shape used by generated facades."""
    return [(x0 + cut, y0), (x1 - cut, y0), (x1, y0 + cut), (x1, y1 - cut), (x1 - cut, y1), (x0 + cut, y1), (x0, y1 - cut), (x0, y0 + cut)]


def apply_decor(color_img: Image.Image, normal_img: Image.Image, glow_img: Image.Image, size: tuple[int, int], k: int,
                rng: random.Random, e: dict, kind: str) -> None:
    """Draw the facade's surface decoration (see decor.py); the config is e["decor"][kind] in facades.json."""
    cfg = (e.get("decor") or {}).get(kind)
    if not cfg:
        return
    colors = e.get("light_colors", [[1.0, 0.75, 0.4]])
    glow_alpha = np.asarray(glow_img.getchannel("A"))
    if cfg.get("pipes"):
        decor.pipe_run(color_img, normal_img, size, k, rng)
    if cfg.get("props"):
        decor.paste_props(color_img, normal_img, glow_img, size, k, rng, cfg["props"], glow_alpha, float(cfg.get("prop_tone", 0.6)))
    if cfg.get("hazard"):
        decor.hazard_band(color_img, normal_img, size, k, float(cfg.get("hazard_y", 0.9)))
    if cfg.get("traces"):
        decor.circuit_traces(color_img, normal_img, glow_img, size, k, rng, colors, int(cfg["traces"]))
    if cfg.get("led"):
        decor.led_row(color_img, normal_img, glow_img, size, k, rng, colors)
    if cfg.get("beacon"):
        decor.beacon(glow_img, int(size[0] * rng.uniform(0.1, 0.9)), int(size[1] * 0.12), k)


def build_generated(e: dict, kind: str, index: int) -> bool:
    """A facade module drawn from a terrain material plus a window grid (see the module docstring)."""
    from PIL import ImageDraw
    g = e["generated"]
    k = int(e["texture_scale"])
    size = (int(MODULE_W * k), int(HEIGHTS[kind] * k))
    period = int(g.get("tile_world", 48) * k)
    wall = tile_to(Image.open(MATERIALS / f"{g['wall_material']}_body.png"), size, period)
    wall_n = tile_to(Image.open(MATERIALS / f"{g['wall_material']}_body_n.png"), size, period)
    color = np.asarray(wall.convert("RGB")).astype(np.float32) / 255.0
    color = grade(color, e.get("grade", {}))
    color_img = Image.fromarray((color * 255 + 0.5).astype(np.uint8), "RGB").convert("RGBA")
    normal_img = wall_n.copy()
    glow_img = Image.new("RGBA", size, (0, 0, 0, 0))
    name = f"{e['id']}_{SUFFIX[kind]}{index}"
    rng = random.Random(zlib.crc32(name.encode()))
    win = (g.get("windows") or {}).get(kind)
    cd, nd, gd = ImageDraw.Draw(color_img), ImageDraw.Draw(normal_img), ImageDraw.Draw(glow_img)
    if win:
        cols, rows, w, h = int(win["cols"]), int(win["rows"]), float(win["w"]) * k, float(win["h"]) * k
        cell_w, cell_h = size[0] / cols, size[1] / rows
        glass = tuple(int(c * 255) for c in win.get("glass", [0.03, 0.06, 0.1]))
        frame = tuple(int(c * 255) for c in win.get("frame", [0.16, 0.18, 0.22]))
        bevel = max(2, k // 2)
        lit_chance, colors, gain = float(e.get("light_chance", 0.5)), e.get("light_colors", [[1.0, 0.75, 0.4]]), float(e.get("light_gain", 1.0))
        any_lit, boxes = False, []
        for r in range(rows):
            for c in range(cols):
                x0, y0 = c * cell_w + (cell_w - w) / 2, r * cell_h + (cell_h - h) / 2
                boxes.append((int(x0), int(y0), int(x0 + w), int(y0 + h)))
        lit = {i for i in range(len(boxes)) if rng.random() <= lit_chance}
        if kind == "body" and not lit and boxes:
            lit = {rng.randrange(len(boxes))}
        for i, (x0, y0, x1, y1) in enumerate(boxes):
            # Chamfered (cut-corner) windows with an inner mullion cross: neither plain rectangles nor plain arcs.
            cut = max(2, int(min(x1 - x0, y1 - y0) * float(win.get("chamfer", 0.3))))
            outer = _chamfer(x0 - bevel, y0 - bevel, x1 + bevel, y1 + bevel, cut + bevel)
            inner = _chamfer(x0, y0, x1, y1, cut)
            cd.polygon(outer, fill=frame + (255,))
            cd.polygon(inner, fill=glass + (255,))
            nd.polygon(outer, fill=(128, 128, 200, 255))  # the frame slope tilts away from the glass
            nd.polygon(inner, fill=(128, 128, 255, 255))
            mid_x, mid_y = (x0 + x1) // 2, (y0 + y1) // 2
            bar = max(1, k // 3)
            if (x1 - x0) > 5 * k:
                cd.line((mid_x, y0, mid_x, y1), fill=frame + (255,), width=bar)
            if (y1 - y0) > 6 * k:
                cd.line((x0, mid_y, x1, mid_y), fill=frame + (255,), width=bar)
            if i in lit:
                col = [int(255 * min(1.0, c * gain * rng.uniform(0.75, 1.0))) for c in rng.choice(colors)]
                gd.polygon(inner, fill=tuple(col) + (240,))
                gd.line((mid_x, y0, mid_x, y1), fill=(0, 0, 0, 0), width=bar)  # the mullion is dark even when lit
                any_lit = True
        if not any_lit and kind == "body":
            raise ValueError(f"{name}: no lit window")
    OUT.mkdir(parents=True, exist_ok=True)
    if glow_img.getbbox():  # window light first (softened), then the crisp small decoration lights on top
        soft = soften(np.asarray(glow_img).astype(np.float32) / 255.0, max(0.8, k * 0.22))
        glow_img = Image.fromarray((soft * 255 + 0.5).astype(np.uint8), "RGBA")
    apply_decor(color_img, normal_img, glow_img, size, k, rng, e, kind)
    color_img.save(OUT / f"{name}.png", optimize=True)
    normal_img.save(OUT / f"{name}_n.png", optimize=True)
    glow_path = OUT / f"{name}_glow.png"
    if glow_img.getbbox():
        glow_img.save(glow_path, optimize=True)
    elif glow_path.exists():
        glow_path.unlink()
    return True


def build_module(kit: Kit, spec: dict, e: dict, kind: str, index: int) -> bool:
    item = spec if isinstance(spec, dict) else {"cells": spec}
    k = int(e["texture_scale"])
    size = (int(MODULE_W * k), int(HEIGHTS[kind] * k))
    crop = item.get("crop")
    color = compose(kit.color, kit.boxes, item["cells"], crop, size, Image.LANCZOS)
    normal = compose(kit.normal, kit.boxes, item["cells"], crop, size, Image.LANCZOS)
    rgb = grade(np.asarray(color.convert("RGB")).astype(np.float32) / 255.0, e.get("grade", {}))
    name = f"{e['id']}_{SUFFIX[kind]}{index}"
    OUT.mkdir(parents=True, exist_ok=True)
    color_img = Image.fromarray((rgb * 255 + 0.5).astype(np.uint8), "RGB").convert("RGBA")
    nrm = np.asarray(normal).astype(np.float32) / 255.0
    nrm[..., 3] = 1.0
    normal_img = Image.fromarray((nrm * 255 + 0.5).astype(np.uint8), "RGBA")
    glow_img = Image.new("RGBA", size, (0, 0, 0, 0))
    rng = random.Random(zlib.crc32(name.encode()))
    if kit.glow is not None and kind != "cap":
        g = compose(kit.glow, kit.boxes, item["cells"], crop, size, Image.NEAREST)
        mask = np.asarray(g)[..., :3].max(axis=2) > 90
        light = window_light(mask, rng, float(e.get("light_chance", 0.5)), e.get("light_colors", [[1.0, 0.75, 0.4]]), float(e.get("light_gain", 1.0)))
        if light[..., 3].max() > 0.0:
            light = soften(light, max(0.8, int(e["texture_scale"]) * 0.22))
            glow_img = Image.fromarray((light * 255 + 0.5).astype(np.uint8), "RGBA")
    apply_decor(color_img, normal_img, glow_img, size, k, rng, e, kind)
    color_img.save(OUT / f"{name}.png", optimize=True)
    normal_img.save(OUT / f"{name}_n.png", optimize=True)
    glow_path = OUT / f"{name}_glow.png"
    if glow_img.getbbox():
        glow_img.save(glow_path, optimize=True)
    elif glow_path.exists():
        glow_path.unlink()
    return True


def patch_tres(e: dict, names: dict[str, list[str]]) -> None:
    path = DATA / f"{e['id']}.tres"
    text = path.read_text(encoding="utf-8")
    for kind in ("ground", "body", "cap"):
        paths = ", ".join(f'"res://art/environment/facades/{n}.png"' for n in names[kind])
        text = re.sub(rf"^{kind} = PackedStringArray\(.*\)$", f"{kind} = PackedStringArray({paths})", text, flags=re.M)
    path.write_text(text, encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=[])
    args = ap.parse_args()
    cfg = json.loads(PIPELINE.read_text(encoding="utf-8"))
    kits: dict[str, Kit] = {}
    failed = 0
    for spec in cfg["facades"]:
        if args.only and spec["id"] not in args.only:
            continue
        e = {**cfg["defaults"], **spec}
        try:
            kit = kits.setdefault(e["kit"], Kit(e["kit"])) if "kit" in e else None
            names = {}
            for kind in ("ground", "body", "cap"):
                names[kind] = []
                for i, item in enumerate(e[kind]):
                    if "generated" in e:
                        build_generated(e, kind, i)
                    else:
                        build_module(kit, item, e, kind, i)
                    names[kind].append(f"{e['id']}_{SUFFIX[kind]}{i}")
            if not (DATA / f"{e['id']}.tres").exists():
                raise FileNotFoundError(f"{e['id']}.tres not found")
            patch_tres(e, names)
            print(f"ok    {e['id']:14} ground {len(names['ground'])} body {len(names['body'])} cap {len(names['cap'])}  <- {e.get('kit') or e['generated']['wall_material']}")
        except Exception as ex:  # one bad facade must not block the rest
            failed += 1
            print(f"FAIL  {spec.get('id')}: {ex}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
