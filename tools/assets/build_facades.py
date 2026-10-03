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
"""
import argparse
import json
import random
import re
import sys
import zlib
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

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
    Image.fromarray((rgb * 255 + 0.5).astype(np.uint8), "RGB").convert("RGBA").save(OUT / f"{name}.png", optimize=True)
    nrm = np.asarray(normal).astype(np.float32) / 255.0
    nrm[..., 3] = 1.0
    Image.fromarray((nrm * 255 + 0.5).astype(np.uint8), "RGBA").save(OUT / f"{name}_n.png", optimize=True)
    glow_path = OUT / f"{name}_glow.png"
    if kit.glow is not None and kind != "cap":
        g = compose(kit.glow, kit.boxes, item["cells"], crop, size, Image.NEAREST)
        mask = np.asarray(g)[..., :3].max(axis=2) > 90
        rng = random.Random(zlib.crc32(name.encode()))
        light = window_light(mask, rng, float(e.get("light_chance", 0.5)), e.get("light_colors", [[1.0, 0.75, 0.4]]), float(e.get("light_gain", 1.0)))
        if light[..., 3].max() > 0.0:
            Image.fromarray((light * 255 + 0.5).astype(np.uint8), "RGBA").save(glow_path, optimize=True)
            return True
    if glow_path.exists():
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
            kit = kits.setdefault(e["kit"], Kit(e["kit"]))
            names = {}
            for kind in ("ground", "body", "cap"):
                names[kind] = []
                for i, item in enumerate(e[kind]):
                    build_module(kit, item, e, kind, i)
                    names[kind].append(f"{e['id']}_{SUFFIX[kind]}{i}")
            if not (DATA / f"{e['id']}.tres").exists():
                raise FileNotFoundError(f"{e['id']}.tres not found")
            patch_tres(e, names)
            print(f"ok    {e['id']:14} ground {len(names['ground'])} body {len(names['body'])} cap {len(names['cap'])}  <- {e['kit']}")
        except Exception as ex:  # one bad facade must not block the rest
            failed += 1
            print(f"FAIL  {spec.get('id')}: {ex}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
