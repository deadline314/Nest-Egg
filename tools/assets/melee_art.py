"""Generates and prepares the art of the melee weapons (NE-260): thermal blade, mono dagger, ion glaive, hydraulic maul, whip handle.

Usage (project root):
  python tools/assets/melee_art.py [--only ID ...] [--no-gen] [--regen] [--sheet OUT.png]

Reads assets_src/pipeline/melee_weapons.json (prompts, seeds, the span of weapon space each picture covers, glow rules,
blade light numbers). For every weapon it
  1. generates a transparent side-view picture with the local Qwen model (skipped with --no-gen; an identical finished job
     is reused), handle on the left and tip on the right,
  2. trims it, checks it really is a horizontal object, mirrors it when the glowing part ended up on the left,
  3. scales it so its width covers exactly the weapon-space span from the list - the grip stays at the origin and the tip
     at the weapon's melee_length, so the pose, reach and pivot of the old line art are unchanged,
  4. extracts the emissive layer and measures the centre line of the handle (where the hand holds it),
  5. writes art/weapons/melee/<id>.png, <id>_glow.png and one entry in data/weapon_art/melee.json,
  6. redraws the pickup lying in the world (art/items/world/<id>.png and _glow.png, the weapon laid diagonally) and, where the
     backpack already uses a dedicated icon file for this weapon (art/items/icons/<profile>.png and _hd.png), that icon too -
     so the weapon in the hand, in the backpack and on the ground are visibly the same object.
The game (core/melee_art.gd) draws the picture when that entry exists and falls back to the old line art when it does not.
The art comes from our own prompt and seed, so there is no third-party licence; both are kept in the list for reproduction.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
import qwen_matte as qm  # noqa: E402
from qwen_props import drop_specks  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
PIPELINE = ROOT / "assets_src" / "pipeline" / "melee_weapons.json"
RAW = ROOT / "assets_src" / "raw" / "melee"
ART = ROOT / "art" / "weapons" / "melee"
DATA = ROOT / "data" / "weapon_art" / "melee.json"
WORLD = ROOT / "art" / "items" / "world"
ICONS = ROOT / "art" / "items" / "icons"
WORLD_SIDE = 96      # same canvas and margin as tools/art/build_world_items.py
WORLD_MARGIN = 8
LAY_ANGLE = 35.0     # lying from lower left to upper right, like the other world sprites
MIN_ASPECT = 1.5  # a weapon lying across the picture is clearly wider than tall


def prompt_for(cfg: dict, entry: dict) -> str:
    subject = f"{cfg['style']} {entry['prompt']} {cfg['view']}".strip()
    return f"This is an RGBA image with transparency. {subject} The image has alpha channel and the background is transparent."


def generate(cfg: dict, entry: dict, regen: bool) -> Path:
    path, meta = RAW / f"{entry['id']}.png", RAW / f"{entry['id']}.json"
    want = {"prompt": prompt_for(cfg, entry), "seed": int(entry["seed"]), "w": entry["gen"][0], "h": entry["gen"][1], "steps": int(entry.get("steps", 25))}
    if path.exists() and meta.exists() and not regen and json.loads(meta.read_text(encoding="utf-8")) == want:
        return path
    os.environ["OUT_DIR"] = str(RAW)
    sys.path.insert(0, str(ROOT / "tools" / "comfyui"))
    from comfy_api import qwen
    RAW.mkdir(parents=True, exist_ok=True)
    out = qwen(want["prompt"], w=want["w"], h=want["h"], steps=want["steps"], seed=want["seed"], prefix=f"_gen_{entry['id']}", reuse=not regen)
    Image.open(out[0]).convert("RGBA").save(path)
    meta.write_text(json.dumps(want, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"gen   {entry['id']:14} {want['w']}x{want['h']}  seed {want['seed']}")
    return path


def process(cfg: dict, entry: dict, no_gen: bool, regen: bool) -> dict | None:
    wid = entry["id"]
    src = RAW / f"{wid}.png"
    if not no_gen:
        src = generate(cfg, entry, regen)
    if not src.exists():
        print(f"FAIL  {wid}: no generated picture ({src}); run without --no-gen", file=sys.stderr)
        return None
    raw = np.asarray(Image.open(src).convert("RGBA")).astype(np.float32) / 255.0
    if raw[..., 3].min() > 0.98:
        print(f"FAIL  {wid}: the model returned no transparency (seed {entry['seed']}); try another seed", file=sys.stderr)
        return None
    alpha = drop_specks(np.clip((raw[..., 3] - 0.04) / 0.92, 0.0, 1.0))
    ys, xs = np.where(alpha > 0.3)
    if len(xs) == 0:
        print(f"FAIL  {wid}: the picture is empty", file=sys.stderr)
        return None
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    rgba = np.dstack([raw[..., :3], alpha])[y0:y1, x0:x1]
    aspect = rgba.shape[1] / rgba.shape[0]
    if aspect < MIN_ASPECT:
        print(f"FAIL  {wid}: the weapon is not lying horizontally (width/height {aspect:.2f}); try another seed", file=sys.stderr)
        return None
    # The glowing part belongs to the business end: mirror the picture when the model put it on the left.
    flip = entry.get("flip", "auto")
    if flip == "auto":
        first = qm.glow_mask(rgba, entry["glow"])
        flip = first is not None and float((first[..., 3].sum(axis=0) * np.arange(first.shape[1])).sum()) < first[..., 3].sum() * first.shape[1] * 0.5
    if flip:
        rgba = rgba[:, ::-1]
    span_min, span_max = entry["span"]
    scale = int(cfg["tex_scale"])
    width_px = max(8, round((span_max - span_min) * scale))
    height_px = max(4, round(width_px / aspect))
    small = np.asarray(Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA").resize((width_px, height_px), Image.LANCZOS)).astype(np.float32) / 255.0
    color = np.dstack([qm.grade(small[..., :3], entry.get("grade", {})), small[..., 3]])
    ART.mkdir(parents=True, exist_ok=True)
    qm.to_image(color).save(ART / f"{wid}.png", optimize=True)
    glow = qm.glow_mask(color, entry["glow"])
    glow_file = ART / f"{wid}_glow.png"
    if glow is None:
        print(f"FAIL  {wid}: no glowing part was found; adjust the glow rules or the prompt", file=sys.stderr)
        return None
    if entry.get("glow_tint"):
        # The model sometimes paints the glowing edge as plain bright metal: give the emissive layer the weapon's own colour,
        # keeping how bright each pixel was.
        glow[..., :3] = glow[..., :3].max(axis=2, keepdims=True) * np.asarray(entry["glow_tint"], dtype=np.float32)
    qm.to_image(glow).save(glow_file, optimize=True)
    # Centre line of the handle: alpha-weighted mean row inside the grip zone.
    g0 = int(np.clip((entry["grip_zone"][0] - span_min) * scale, 0, width_px - 1))
    g1 = int(np.clip((entry["grip_zone"][1] - span_min) * scale, g0 + 1, width_px))
    zone = color[:, g0:g1, 3]
    rows = zone.sum(axis=1)
    grip_row = float((rows * (np.arange(height_px) + 0.5)).sum() / max(float(rows.sum()), 1e-6))
    glow_cols = glow[..., 3].sum(axis=0)
    glow_centre = float((glow_cols * (np.arange(width_px) + 0.5)).sum() / max(float(glow_cols.sum()), 1e-6))
    size = [round(width_px / scale, 3), round(height_px / scale, 3)]
    result = {
        "texture": f"res://art/weapons/melee/{wid}.png",
        "glow": f"res://art/weapons/melee/{wid}_glow.png",
        "size": size,
        "grip": [round(-span_min, 3), round(grip_row / scale, 3)],
        "glow_at": round(glow_centre / scale + span_min, 2),
        "light": entry["light"],
    }
    print(f"ok    {wid:14} {width_px}x{height_px}px  size {size[0]}x{size[1]}  grip {result['grip']}  glow at x={result['glow_at']}  flipped={bool(flip)}")
    lay_out(entry, rgba)
    return result


def laid(entry: dict, rgba: np.ndarray, side: int, margin: int) -> tuple[Image.Image, Image.Image]:
    """The weapon laid diagonally on a square transparent canvas, and its emissive layer."""
    picture = Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA")
    if entry.get("coil"):
        # A whip is only a handle in the hand; on the ground and in the backpack it is the handle with the filament coiled.
        coil = entry["coil"]
        k = picture.height / 10.0
        canvas = Image.new("RGBA", (picture.width + int(60 * k), int(70 * k)))
        draw = ImageDraw.Draw(canvas)
        colour = tuple(int(c * 255) for c in coil["color"]) + (255,)
        x0, y0 = picture.width - int(4 * k), canvas.height // 2
        for loop, radius in enumerate((26, 19)):
            box = [x0 + int(4 * k) * loop, y0 - int(radius * k), x0 + int(4 * k) * loop + int(radius * 2 * k), y0 + int(radius * k)]
            draw.ellipse(box, outline=colour, width=max(2, int(1.6 * k)))
        canvas.alpha_composite(picture, (0, y0 - picture.height // 2))
        picture = canvas
    picture = picture.rotate(LAY_ANGLE, resample=Image.BICUBIC, expand=True)
    box = picture.getchannel("A").point(lambda v: 255 if v >= 32 else 0).getbbox()
    picture = picture.crop(box)
    picture.thumbnail((side - margin * 2, side - margin * 2), Image.LANCZOS)
    sprite = Image.new("RGBA", (side, side))
    sprite.alpha_composite(picture, ((side - picture.width) // 2, (side - picture.height) // 2))
    arr = np.asarray(sprite).astype(np.float32) / 255.0
    glow = qm.glow_mask(arr, entry["glow"])
    if glow is None:
        return sprite, Image.new("RGBA", (side, side))
    if entry.get("glow_tint"):
        glow[..., :3] = glow[..., :3].max(axis=2, keepdims=True) * np.asarray(entry["glow_tint"], dtype=np.float32)
    return sprite, qm.to_image(glow)


def lay_out(entry: dict, rgba: np.ndarray) -> None:
    sprite, glow = laid(entry, rgba, WORLD_SIDE, WORLD_MARGIN)
    WORLD.mkdir(parents=True, exist_ok=True)
    sprite.save(WORLD / f"{entry['id']}.png", optimize=True)
    glow.save(WORLD / f"{entry['id']}_glow.png", optimize=True)
    profile = entry.get("profile", "")
    for name, side, margin in ((f"{profile}.png", 32, 2), (f"{profile}_hd.png", 384, 24)):
        target = ICONS / name
        if profile and target.exists():
            icon, icon_glow = laid(entry, rgba, side, margin)
            icon.alpha_composite(icon_glow)
            icon.save(target, optimize=True)
            print(f"icon  {name}")


def sheet(ids: list[str], out: Path) -> None:
    """Contact sheet: every weapon and its glow layer on a dark background, enlarged."""
    tiles = []
    for wid in ids:
        if not (ART / f"{wid}.png").exists():
            continue
        art = Image.open(ART / f"{wid}.png").convert("RGBA")
        glow = Image.open(ART / f"{wid}_glow.png").convert("RGBA")
        k = max(1, 560 // art.width)
        row = Image.new("RGBA", (art.width * k * 2 + 30, art.height * k + 30), (26, 28, 38, 255))
        row.alpha_composite(art.resize((art.width * k, art.height * k), Image.NEAREST), (10, 22))
        dark = Image.new("RGBA", (art.width * k, art.height * k), (4, 4, 8, 255))
        dark.alpha_composite(glow.resize((art.width * k, art.height * k), Image.NEAREST))
        row.alpha_composite(dark, (art.width * k + 20, 22))
        ImageDraw.Draw(row).text((10, 4), wid, fill=(230, 235, 240, 255))
        tiles.append(row)
    if not tiles:
        return
    board = Image.new("RGBA", (max(t.width for t in tiles), sum(t.height for t in tiles)), (26, 28, 38, 255))
    y = 0
    for tile in tiles:
        board.alpha_composite(tile, (0, y))
        y += tile.height
    board.convert("RGB").save(out)
    print("sheet", out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=[])
    ap.add_argument("--no-gen", action="store_true")
    ap.add_argument("--regen", action="store_true")
    ap.add_argument("--sheet", default="")
    args = ap.parse_args()
    cfg = json.loads(PIPELINE.read_text(encoding="utf-8"))
    table = json.loads(DATA.read_text(encoding="utf-8")) if DATA.exists() else {}
    table["_說明"] = ("近戰武器的圖（NE-260），由 python tools/assets/melee_art.py 產生，不要手改。每把武器：texture／glow＝圖與發光層；"
                    "size＝畫在遊戲裡的大小（世界像素）；grip＝握把（手握的位置）在圖上的位置（世界像素，從左上角算），遊戲把這一點對到手上、"
                    "圖的 +x 朝刃尖；glow_at＝發光部位在武器座標的 x（刃光的位置）；light＝刃光（radius 拿在手上的光池半徑、energy 亮度、"
                    "swing 揮動時放大幾倍）。沒有列在這裡的武器用程式畫的線條。")
    weapons = table.setdefault("weapons", {})
    failures = 0
    done = []
    for entry in cfg["weapons"]:
        if args.only and entry["id"] not in args.only:
            continue
        result = process(cfg, entry, args.no_gen, args.regen)
        if result is None:
            failures += 1
            continue
        weapons[entry["id"]] = result
        done.append(entry["id"])
    DATA.write_text(json.dumps(table, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n")
    if args.sheet:
        sheet([e["id"] for e in cfg["weapons"]], Path(args.sheet))
    print(f"{len(done)} weapons written, {failures} failed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
