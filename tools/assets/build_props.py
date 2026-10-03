"""Render free 3D models into game prop textures and patch the prop data (NE-57 / NE-62 / NE-63 / NE-64).

Usage: python tools/assets/build_props.py [--only ID ...] [--no-render]

Reads assets_src/pipeline/props.json. For every prop it
  1. renders the glTF with tools/assets/render_model.tscn (albedo, camera-space normals, optional glow mask),
  2. crops (for kit models that hold several pieces), grades, trims to the silhouette and resizes so the texture is
     texture_scale x its logical size,
  3. writes art/environment/props/<id>.png, <id>_n.png and (if the model has emissive parts) <id>_glow.png,
  4. patches data/environment/props/<id>.tres: size (keeps the old size along `fit`, the other axis follows the model's
     aspect), light_offset (scaled with the size) and has_glow.
Grading lives in the JSON. Set GODOT to the Godot executable (default: C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe).
Props with a one-way platform must keep their aspect ("keep_size": true stretches to the old size instead).
Kit pieces: an entry with "kit_cell": <n> skips its own render and cuts piece n (numbered by kit_cells.py) out of the
kit render in assets_src/work/kits/<asset>.png (+ _n, _glow); "rotate": 90|180|270 turns the piece (normals included).
"""
import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "assets_src" / "raw"
WORK = ROOT / "assets_src" / "work" / "props"
KITS = ROOT / "assets_src" / "work" / "kits"
PIPELINE = ROOT / "assets_src" / "pipeline" / "props.json"
OUT = ROOT / "art" / "environment" / "props"
DATA = ROOT / "data" / "environment" / "props"
GODOT = os.environ.get("GODOT", "C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe")
MAX_SIDE_PX = 1024  # size budget per texture
LUMA = np.array([0.299, 0.587, 0.114], dtype=np.float32)


def render(entries: list[dict]) -> bool:
    jobs = []
    for e in entries:
        if "kit_cell" in e:
            continue
        gltf = next((RAW / e["model"]).glob("*.gltf"), None)  # file name keeps the source's capitalisation (Barrel_01)
        if gltf is None:
            print(f"FAIL  {e['id']}: no .gltf in assets_src/raw/{e['model']} (run fetch_assets.py)", file=sys.stderr)
            continue
        job = {"src": f"assets_src/raw/{e['model']}/{gltf.name}", "out": f"assets_src/work/props/{e['id']}",
               "width": int(e.get("render_width", 768)), "yaw": e.get("yaw", 0), "pitch": e.get("pitch", 0)}
        if e.get("glow"):
            job["glow"] = e["glow"]
            job["glow_color"] = e.get("glow_color", [1, 1, 1])
            job["glow_through"] = bool(e.get("glow_through", False))
        jobs.append(job)
    WORK.mkdir(parents=True, exist_ok=True)
    batch = WORK / "batch.json"
    batch.write_text(json.dumps(jobs, indent=1), encoding="utf-8")
    result = subprocess.run([GODOT, "--path", str(ROOT), "res://tools/assets/render_model.tscn", "--",
                             f"--batch={batch}"], capture_output=True, text=True)
    print("\n".join(l for l in result.stdout.splitlines() if l.startswith("rendered") or "ERROR" in l))
    if result.returncode != 0:
        print(result.stderr[-800:], file=sys.stderr)
    return result.returncode == 0


def grade(a: np.ndarray, g: dict) -> np.ndarray:
    a = a ** float(g.get("gamma", 1.0))
    lum = a @ LUMA
    a = lum[..., None] + (a - lum[..., None]) * float(g.get("saturation", 1.0))
    a = (a - 0.5) * float(g.get("contrast", 1.0)) + 0.5
    a = a * float(g.get("brightness", 1.0)) * np.array(g.get("tint", [1, 1, 1]), dtype=np.float32)
    return np.clip(a, 0.0, 1.0)


def crop_fraction(im: Image.Image, box) -> Image.Image:
    w, h = im.size
    return im.crop((int(box[0] * w), int(box[1] * h), int(box[2] * w), int(box[3] * h)))


def resize_rgba(im: Image.Image, size: tuple[int, int]) -> Image.Image:
    return im.convert("RGBa").resize(size, Image.LANCZOS).convert("RGBA")


def rotate_normals(im: Image.Image, degrees: int) -> Image.Image:
    """Rotate a normal map counter-clockwise: the pixels and the vectors inside them both turn."""
    turns = (degrees // 90) % 4
    a = np.asarray(im).astype(np.float32) / 255.0
    nx, ny = a[..., 0] * 2 - 1, a[..., 1] * 2 - 1
    for _ in range(turns):
        nx, ny = -ny, nx
        a = np.rot90(a)
        nx, ny = np.rot90(nx), np.rot90(ny)
    a = a.copy()
    a[..., 0], a[..., 1] = nx * 0.5 + 0.5, ny * 0.5 + 0.5
    return Image.fromarray((a * 255 + 0.5).astype(np.uint8), "RGBA")


def load_passes(e: dict):
    """(color, normal, glow or None) for an entry: its own render, or a piece cut from a kit render."""
    if "kit_cell" in e:
        asset = e["model"].split("_", 2)[2]
        boxes = json.loads((KITS / f"{asset}_cells.json").read_text(encoding="utf-8"))
        box = tuple(boxes[int(e["kit_cell"])])
        glow_p = KITS / f"{asset}_glow.png"
        color = Image.open(KITS / f"{asset}.png").convert("RGBA").crop(box)
        normal = Image.open(KITS / f"{asset}_n.png").convert("RGBA").crop(box)
        glow = Image.open(glow_p).convert("RGBA").crop(box) if glow_p.exists() else None
    else:
        pid = e["id"]
        color, normal = Image.open(WORK / f"{pid}.png").convert("RGBA"), Image.open(WORK / f"{pid}_n.png").convert("RGBA")
        glow_p = WORK / f"{pid}_glow.png"
        glow = Image.open(glow_p).convert("RGBA") if glow_p.exists() else None
    deg = int(e.get("rotate", 0))
    if deg:
        color = color.rotate(deg, expand=True)
        normal = rotate_normals(normal, deg)
        glow = glow.rotate(deg, expand=True) if glow is not None else None
    return color, normal, glow


def read_size(tres: str) -> tuple[float, float]:
    m = re.search(r"^size = Vector2\(([-\d.]+), ([-\d.]+)\)", tres, re.M)
    return (float(m.group(1)), float(m.group(2))) if m else (16.0, 16.0)


def set_field(tres: str, key: str, value: str) -> str:
    line = f"{key} = {value}"
    if re.search(rf"^{key} = .*$", tres, re.M):
        return re.sub(rf"^{key} = .*$", line, tres, flags=re.M)
    return re.sub(r"(^texture = .*\n)", lambda m: m.group(1) + line + "\n", tres, count=1, flags=re.M)


def fmt(v: float) -> str:
    return f"{v:.1f}".rstrip("0").rstrip(".")


def process(e: dict, defaults: dict) -> bool:
    e = {**defaults, **e}
    pid = e["id"]
    tres_path = DATA / f"{pid}.tres"
    if not tres_path.exists():
        print(f"FAIL  {pid}: {tres_path} not found", file=sys.stderr)
        return False
    color, normal, glow = load_passes(e)
    if e.get("crop"):
        color, normal = crop_fraction(color, e["crop"]), crop_fraction(normal, e["crop"])
        glow = crop_fraction(glow, e["crop"]) if glow is not None else None
    box = color.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox()
    if box is None:
        print(f"FAIL  {pid}: empty after crop", file=sys.stderr)
        return False
    color, normal = color.crop(box), normal.crop(box)
    glow = glow.crop(box) if glow is not None else None

    tres = tres_path.read_text(encoding="utf-8")
    old_w, old_h = read_size(tres)
    aspect = color.width / color.height
    if e.get("keep_size"):
        new_w, new_h = old_w, old_h
    elif e.get("fit", "height") == "height":
        new_h, new_w = old_h, old_h * aspect
    else:
        new_w, new_h = old_w, old_w / aspect
    k = int(e["texture_scale"])
    px = (max(1, round(new_w * k)), max(1, round(new_h * k)))
    if max(px) > MAX_SIDE_PX:
        s = MAX_SIDE_PX / max(px)
        px = (max(1, int(px[0] * s)), max(1, int(px[1] * s)))
    rgba = np.asarray(resize_rgba(color, px)).astype(np.float32) / 255.0
    rgb = grade(rgba[..., :3], e.get("grade", {}))
    out = np.concatenate([rgb, rgba[..., 3:]], axis=2)
    OUT.mkdir(parents=True, exist_ok=True)
    Image.fromarray((out * 255 + 0.5).astype(np.uint8), "RGBA").save(OUT / f"{pid}.png", optimize=True)
    resize_rgba(normal, px).save(OUT / f"{pid}_n.png", optimize=True)
    has_glow = False
    if glow is not None:
        g = np.asarray(resize_rgba(glow, px)).astype(np.float32) / 255.0
        strength = g[..., :3].max(axis=2)
        alpha = np.clip((strength - 0.05) * 4.0, 0.0, 1.0) * g[..., 3]
        if alpha.max() > 0.02:
            gl = np.concatenate([grade(g[..., :3], e.get("glow_grade", {"brightness": 1.0})), alpha[..., None]], axis=2)
            Image.fromarray((gl * 255 + 0.5).astype(np.uint8), "RGBA").save(OUT / f"{pid}_glow.png", optimize=True)
            has_glow = True
    glow_file = OUT / f"{pid}_glow.png"
    if not has_glow and glow_file.exists():
        glow_file.unlink()

    tres = set_field(tres, "size", f"Vector2({fmt(new_w)}, {fmt(new_h)})")
    if has_glow:
        tres = set_field(tres, "has_glow", "true")
    elif re.search(r"^has_glow = true", tres, re.M):
        tres = set_field(tres, "has_glow", "false")  # the old hand-painted glow layer is gone; the data must not claim one
    m = re.search(r"^light_offset = Vector2\(([-\d.]+), ([-\d.]+)\)", tres, re.M)
    if m and old_w > 0 and old_h > 0:
        tres = set_field(tres, "light_offset", f"Vector2({fmt(float(m.group(1)) * new_w / old_w)}, {fmt(float(m.group(2)) * new_h / old_h)})")
    tres_path.write_text(tres, encoding="utf-8")
    print(f"ok    {pid:16} {px[0]}x{px[1]}px  size {fmt(new_w)}x{fmt(new_h)}  glow={has_glow}  <- {e['model']}")
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=[])
    ap.add_argument("--no-render", action="store_true")
    args = ap.parse_args()
    cfg = json.loads(PIPELINE.read_text(encoding="utf-8"))
    entries = [e for e in cfg["props"] if not args.only or e["id"] in args.only]
    if not args.no_render and not render(entries):
        return 1
    failed = 0
    for e in entries:
        try:
            failed += 0 if process(e, cfg["defaults"]) else 1
        except Exception as ex:  # one bad entry must not block the rest
            failed += 1
            print(f"FAIL  {e.get('id')}: {ex}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
