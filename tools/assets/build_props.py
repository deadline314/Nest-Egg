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
New props: an entry with "new": {display_name, category, layer, front_alpha, sway, casts_shadow} and an "anchor": {"size": [w, h]}
creates data/environment/props/<id>.tres on first run (the size is then fitted to the model like any other prop).
"aliases" entries (id, of, display_name, layer, front_alpha, scale) add another data file that reuses an existing prop's
texture (e.g. a half-transparent foreground copy of a tree) without any new art.
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
import grade as grade_lib  # noqa: E402

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


def grade(a: np.ndarray, g: dict, use_master: bool = True) -> np.ndarray:
    """Entry grade, then the shared master grade (see grade.py); emissive layers pass use_master=False."""
    return grade_lib.grade_asset(a, g, "prop", "half", use_master)

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


TRES_TEMPLATE = '''[gd_resource type="Resource" script_class="PropData" format=3]

[ext_resource type="Script" path="res://data/scripts/prop_data.gd" id="1_prop"]

[resource]
script = ExtResource("1_prop")
id = &"{id}"
display_name = "{name}"
texture = "{texture}"
size = Vector2({w}, {h})
'''


def write_new_tres(path: Path, pid: str, new: dict, texture: str, size: tuple[float, float]) -> None:
    text = TRES_TEMPLATE.format(id=pid, name=new.get("display_name", pid), texture=texture, w=fmt(size[0]), h=fmt(size[1]))
    lines = []
    if int(new.get("layer", 0)):
        lines.append(f"layer = {int(new['layer'])}")
    if "front_alpha" in new:
        lines.append(f"front_alpha = {new['front_alpha']}")
    if float(new.get("sway", 0)) > 0:
        lines.append(f"sway = {new['sway']}")
    if new.get("casts_shadow"):
        lines.append("casts_shadow = true")
    lines.append(f'category = &"{new.get("category", "street")}"')
    path.write_text(text + "\n".join(lines) + "\n", encoding="utf-8")


def make_aliases(cfg: dict) -> None:
    for a in cfg.get("aliases", []):
        base = DATA / f"{a['of']}.tres"
        if not base.exists():
            print(f"FAIL  {a['id']}: base prop {a['of']} not built yet", file=sys.stderr)
            continue
        w, h = read_size(base.read_text(encoding="utf-8"))
        k = float(a.get("scale", 1.0))
        write_new_tres(DATA / f"{a['id']}.tres", a["id"], a, f"res://art/environment/props/{a['of']}.png", (w * k, h * k))
        print(f"ok    {a['id']:16} alias of {a['of']}")


def process(e: dict, defaults: dict) -> bool:
    e = {**defaults, **e}
    pid = e["id"]
    if e.get("new") and not (DATA / f"{pid}.tres").exists():
        anchor_size = (e.get("anchor") or {}).get("size", [16.0, 16.0])
        write_new_tres(DATA / f"{pid}.tres", pid, e["new"], f"res://art/environment/props/{pid}.png", (anchor_size[0], anchor_size[1]))
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
    # "anchor" is the prop's size / light offset before the first replacement (kept in the JSON so a rerun does not
    # compound the previous run's result); without one, the current data is taken and remembered.
    anchor = e.get("anchor") or {"size": list(read_size(tres))}
    e["anchor"] = anchor
    old_w, old_h = anchor["size"]
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
            gl = np.concatenate([grade(g[..., :3], e.get("glow_grade", {"brightness": 1.0}), use_master=False), alpha[..., None]], axis=2)
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
    if "light_offset" not in anchor:
        m = re.search(r"^light_offset = Vector2\(([-\d.]+), ([-\d.]+)\)", tres, re.M)
        if m:
            anchor["light_offset"] = [float(m.group(1)), float(m.group(2))]
    if "light_offset" in anchor and old_w > 0 and old_h > 0:
        lx, ly = anchor["light_offset"]
        tres = set_field(tres, "light_offset", f"Vector2({fmt(lx * new_w / old_w)}, {fmt(ly * new_h / old_h)})")
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
    if not args.only:
        make_aliases(cfg)
    PIPELINE.write_text(json.dumps(cfg, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")  # remembers new anchors
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
