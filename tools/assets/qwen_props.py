"""Generate game prop textures with Qwen Image (local ComfyUI) for props that have no free 3D model (NE-62 / NE-63).

Usage: python tools/assets/qwen_props.py [--pipeline NAME] [--only ID ...] [--regen] [--no-gen] [--sheet OUT.png]

--pipeline NAME reads assets_src/pipeline/NAME.json instead of qwen_props.json (default). A list other than the default
inherits "styles", "glow_presets", "defaults", "px_per_meter" and the normal profile tables from qwen_props.json, so it only
needs its own "props". An entry with "scene": "<scene_id>" writes into art/environment/scene_props/<scene_id>/ and
data/environment/scene_props/<scene_id>/ (a theme points its prop_dir there), not into the shared prop library.

Reads assets_src/pipeline/qwen_props.json. For every entry it
  1. asks Qwen for the prop with a transparent background (official RGBA prompt) at the prop's aspect ratio (cached in
     assets_src/work/qwen/<id>.png together with the prompt and seed; only regenerated when those change or --regen),
  2. uses the generated alpha (or cuts a flat background out with qwen_matte.matte), trims to the silhouette, grades, and resizes to texture_scale x the logical
     size (<= 1024 px),
  3. writes art/environment/props/<id>.png, <id>_n.png (normal map) and, when "glow" rules match, <id>_glow.png,
  4. patches data/environment/props/<id>.tres: size (kept when "fit" is "keep"), has_glow, light_offset scaling and any
     extra fields listed under "data" (sway, flicker, ...).
Needs a running ComfyUI (see design/03-art-pipeline/ART_PIPELINE.md) unless --no-gen. The art is generated from our own
prompts, so there is no third-party licence; prompt and seed in the JSON are the "source".
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "comfyui"))
from comfy_guard import ComfyFailure  # noqa: E402
from build_props import DATA, make_aliases, MAX_SIDE_PX, OUT, ROOT, fmt, read_size, resize_rgba, set_field, write_new_tres  # noqa: E402
import qwen_matte as qm  # noqa: E402

DEFAULT_PIPELINE = ROOT / "assets_src" / "pipeline" / "qwen_props.json"
PIPELINE = DEFAULT_PIPELINE  # main() points it at --pipeline
RAW = ROOT / "assets_src" / "work" / "qwen"
GEN_AREA = 0.80e6  # pixels Qwen paints per image (more is slow, less is mushy)


def gen_size(w: float, h: float, area: float = GEN_AREA) -> tuple[int, int]:
    """Canvas for a prop of logical size w x h: same aspect, multiples of 16, sides within 256..1536."""
    aspect = w / h
    gh = math.sqrt(area / aspect)
    gw = gh * aspect
    clamp = lambda v: int(min(1536, max(256, round(v / 16) * 16)))  # noqa: E731
    return clamp(gw), clamp(gh)


def build_prompt(e: dict, cfg: dict) -> str:
    """Official Qwen-Image 2.1 recipe for transparent output: the model writes a real alpha channel when the prompt
    follows "This is an RGBA image with transparency. <subject>. The image has alpha channel and the background is
    transparent." (model card / ComfyUI template). "native_alpha": false asks for a plain picture instead (edit refs)."""
    subject = f"{cfg['styles'][e.get('style', 'dark')]} {e['prompt']}".strip()
    if e.get("native_alpha", True):
        return f"This is an RGBA image with transparency. {subject.rstrip('.')}. The image has alpha channel and the background is transparent."
    return subject


def entry_dirs(e: dict) -> tuple[Path, Path, str]:
    """(art folder, data folder, res:// prefix of the art folder) for an entry: the shared prop library, or its scene's own pack."""
    scene = e.get("scene")
    if scene:
        return OUT.parent / "scene_props" / scene, DATA.parent / "scene_props" / scene, f"res://art/environment/scene_props/{scene}"
    return OUT, DATA, "res://art/environment/props"


def load_cfg(path: Path) -> tuple[dict, dict]:
    """(raw file content, merged config). The merged one shares the "props" list with the raw one, so anchors the tools
    remember are written back, while inherited tables are not copied into the file."""
    raw = json.loads(path.read_text(encoding="utf-8"))
    cfg = dict(raw)
    if path != DEFAULT_PIPELINE:
        base = json.loads(DEFAULT_PIPELINE.read_text(encoding="utf-8"))
        for key in ("styles", "glow_presets", "defaults", "px_per_meter", "normal_default"):
            cfg.setdefault(key, base.get(key))
        cfg["normal_profiles"] = {**base.get("normal_profiles", {}), **raw.get("normal_profiles", {})}
    return raw, cfg


def generate(e: dict, cfg: dict, size: tuple[float, float], regen: bool) -> Path | None:
    pid = e["id"]
    path, meta = RAW / f"{pid}.png", RAW / f"{pid}.json"
    gw, gh = e.get("gen") or gen_size(*size)
    prompt = build_prompt(e, cfg)
    want = {"prompt": prompt, "seed": int(e.get("seed", 1)), "w": gw, "h": gh, "steps": int(e.get("steps", 25))}
    if path.exists() and meta.exists() and not regen and json.loads(meta.read_text(encoding="utf-8")) == want:
        return path
    os.environ["OUT_DIR"] = str(RAW)
    sys.path.insert(0, str(ROOT / "tools" / "comfyui"))
    from comfy_api import qwen
    RAW.mkdir(parents=True, exist_ok=True)
    refs = []
    for r in e.get("refs", []):  # layout references: the old sprite on white, scaled to the canvas (edit mode keeps its size)
        ref = Image.open(ROOT / r).convert("RGBA")
        canvas = Image.new("RGBA", ref.size, (255, 255, 255, 255))
        canvas.alpha_composite(ref)
        rp = RAW / f"_ref_{pid}.png"
        canvas.convert("RGB").resize((gw, gh), Image.LANCZOS).save(rp)
        refs.append(str(rp))
    out = qwen(prompt, w=gw, h=gh, steps=want["steps"], seed=want["seed"], prefix=f"_gen_{pid}", images=refs, reuse=not regen)
    Image.open(out[0]).convert("RGBA").save(path)
    meta.write_text(json.dumps(want, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"gen   {pid:18} {gw}x{gh}  seed {want['seed']}")
    return path


def drop_specks(alpha: np.ndarray, min_share: float = 0.01) -> np.ndarray:
    """Erase stray pieces (haze, shadow streaks, far-off specks) so they neither show nor stretch the bounding box:
    connected parts smaller than `min_share` of the largest part are removed."""
    import cv2
    mask = (alpha > 0.3).astype(np.uint8)
    count, labels, stats, _ = cv2.connectedComponentsWithStats(mask, connectivity=8)
    if count <= 2:
        return alpha
    areas = stats[1:, cv2.CC_STAT_AREA]
    keep = np.zeros(count, dtype=bool)
    keep[1:] = areas >= areas.max() * min_share
    return np.where(keep[labels], alpha, 0.0).astype(alpha.dtype)


def glow_centre(glow: np.ndarray | None) -> tuple[float, float]:
    """Centre of the emissive layer as fractions of the picture (x, y), weighted by how strongly each pixel glows.
    Without a glow layer the light starts a little below the middle, where a lamp's lens usually is."""
    if glow is None or float(glow[..., 3].sum()) <= 0.0:
        return 0.5, 0.6
    weight = glow[..., 3] ** 2
    h, w = weight.shape
    total = float(weight.sum())
    return (float((weight.sum(axis=0) * (np.arange(w) + 0.5)).sum() / total / w),
            float((weight.sum(axis=1) * (np.arange(h) + 0.5)).sum() / total / h))


def deck_center(alpha: np.ndarray) -> float | None:
    """Vertical centre (fraction of the height) of the first thick, nearly full-width horizontal bar - a landing or awning."""
    h = alpha.shape[0]
    full = (alpha > 0.5).mean(axis=1) >= 0.8
    need = max(3, int(0.04 * h))
    run_start = None
    for y in range(h + 1):
        on = y < h and full[y]
        if on and run_start is None:
            run_start = y
        elif not on and run_start is not None:
            if y - run_start >= need:
                return (run_start + y) / 2.0 / h
            run_start = None
    return None


def align_platform(rgba: np.ndarray, tres: str, old_h: float, pid: str, contain_w: float = 0.0) -> np.ndarray:
    """Pad the picture with transparency (uniformly, so nothing is stretched) until its deck sits where the prop's one-way
    platform is, so the standable surface in the data matches what the player sees."""
    m = re.search(r"^platform = Rect2\(([-\d.]+), ([-\d.]+), ([-\d.]+), ([-\d.]+)\)", tres, re.M)
    f = deck_center(rgba[..., 3])
    if m is None or f is None:
        print(f"warn  {pid}: platform_align needs a platform in the data and a deck in the picture", file=sys.stderr)
        return rgba
    t = (float(m.group(2)) + float(m.group(4)) / 2.0) / old_h
    h, w = rgba.shape[:2]
    if contain_w:  # keep the drawn proportions: fit inside the old box (no stretching) and put the deck on the platform
        k = min(contain_w / w, old_h / h)  # logical units per picture pixel
        top = round(t * old_h / k - f * h)
        top = max(0, min(top, round(old_h / k) - h))
        canvas_w, canvas_h = round(contain_w / k), round(old_h / k)
        left = (canvas_w - w) // 2
        out = np.zeros((canvas_h, canvas_w, 4), dtype=rgba.dtype)
        out[top:top + h, left:left + w] = rgba
        print(f"align {pid:18} deck at {f:.2f} -> {t:.2f} (contained in {contain_w:g}x{old_h:g})")
        return out
    if abs(f - t) < 0.01:
        return rgba
    if f < t:  # deck too high: add room above
        grow = (t - f) / (1.0 - t)
        top, bottom = round(grow * h), 0
    else:      # deck too low: add room below
        grow = f / t - 1.0
        top, bottom = 0, round(grow * h)
    side = round(grow * w / 2.0)
    out = np.pad(rgba, ((top, bottom), (side, side), (0, 0)))
    print(f"align {pid:18} deck at {f:.2f} -> {t:.2f} (padded {grow * 100:.0f}%)")
    return out


def process(e: dict, cfg: dict, regen: bool, no_gen: bool) -> bool:
    orig = e
    e = {**cfg["defaults"], **e}
    if isinstance(e.get("glow"), str):
        e["glow"] = cfg["glow_presets"][e["glow"]]
    pid = e["id"]
    art_dir, data_dir, res_prefix = entry_dirs(e)
    tres_path = data_dir / f"{pid}.tres"
    if e.get("new") and not tres_path.exists():
        a = (e.get("anchor") or {}).get("size", [16.0, 16.0])
        data_dir.mkdir(parents=True, exist_ok=True)
        write_new_tres(tres_path, pid, e["new"], f"{res_prefix}/{pid}.png", (a[0], a[1]))
    if not tres_path.exists():
        print(f"FAIL  {pid}: {tres_path} not found", file=sys.stderr)
        return False
    tres = tres_path.read_text(encoding="utf-8")
    anchor = e.get("anchor") or {"size": list(read_size(tres))}
    e["anchor"] = orig["anchor"] = anchor
    old_w, old_h = anchor["size"]
    src = RAW / f"{pid}.png"
    if not no_gen:
        src = generate(e, cfg, (old_w, old_h), regen)
    if src is None or not src.exists():
        print(f"FAIL  {pid}: no generated image ({src}); run without --no-gen", file=sys.stderr)
        return False

    raw = np.asarray(Image.open(src).convert("RGBA")).astype(np.float32) / 255.0
    rgb = raw[..., :3]
    if e.get("native_alpha", True) and not e.get("silhouette"):
        if raw[..., 3].min() > 0.98:
            print(f"FAIL  {pid}: the model returned no transparency (seed {e.get('seed')}); try another seed", file=sys.stderr)
            return False
        floor = float(e.get("alpha_floor", 0.04))  # drop the faint haze around the outline (a soft wall shadow needs ~0.4)
        alpha = np.clip((raw[..., 3] - floor) / (1.0 - floor - 0.04), 0.0, 1.0)
        rgba = np.dstack([rgb, alpha])
    elif e.get("silhouette"):
        rgba = qm.silhouette_matte(rgb, float(e.get("silhouette_gamma", 1.0)))
        rgba[..., :3] = np.array(e.get("silhouette_color", [0.02, 0.025, 0.04]), dtype=np.float32)
    else:  # plain picture on a flat background ("native_alpha": false): cut the background out
        rgba = qm.matte(rgb, e.get("bg", "white"), float(e.get("tol", 0.10)), float(e.get("soft", 0.12)))
    if e.get("flip"):
        rgba = rgba[:, ::-1].copy()
    rgba[..., 3] = drop_specks(rgba[..., 3])
    box = Image.fromarray((rgba[..., 3] * 255).astype(np.uint8)).point(lambda v: 255 if v > 10 else 0).getbbox()
    if box is None:
        print(f"FAIL  {pid}: nothing left after matting", file=sys.stderr)
        return False
    pad = int(e.get("pad", 0))
    box = (max(0, box[0] - pad), max(0, box[1] - pad), min(rgba.shape[1], box[2] + pad), min(rgba.shape[0], box[3] + pad))
    if e.get("crop"):  # fractions of the trimmed box: keep only part of the picture (e.g. one of two objects)
        x0, y0, x1, y1 = e["crop"]
        bw, bh = box[2] - box[0], box[3] - box[1]
        box = (box[0] + int(x0 * bw), box[1] + int(y0 * bh), box[0] + int(x1 * bw), box[1] + int(y1 * bh))
    rgba = rgba[box[1]:box[3], box[0]:box[2]]
    if e.get("platform_align"):
        rgba = align_platform(rgba, tres, old_h, pid, old_w if e["platform_align"] == "contain" else 0.0)
    aspect = rgba.shape[1] / rgba.shape[0]
    if e.get("max_aspect") and aspect > float(e["max_aspect"]):  # keep the old footprint (see-through front trees must not grow over enemies): squeeze sideways
        print(f"note  {pid}: aspect {aspect:.2f} squeezed to {e['max_aspect']}")
        aspect = float(e["max_aspect"])

    fit = e.get("fit", "height")
    if fit == "keep":
        new_w, new_h = old_w, old_h
        if abs(aspect / (old_w / old_h) - 1.0) > 0.30:
            print(f"warn  {pid}: aspect {aspect:.2f} vs logical {old_w / old_h:.2f} is stretched by more than 30%")
    elif fit == "area":
        # natural proportions, about the old footprint; the height stays within 0.75 .. 1.3 of the old one
        new_h = min(max(math.sqrt(old_w * old_h / aspect), 0.75 * old_h), 1.3 * old_h)
        new_w = new_h * aspect
    elif fit == "meters":
        # real-world height times the scene's pixels per metre, so props keep a sensible size next to the player
        new_h = float(e["height_m"]) * float(cfg.get("px_per_meter", 30))
        new_w = new_h * aspect
    elif fit == "height":
        new_h, new_w = old_h, old_h * aspect
    else:
        new_w, new_h = old_w, old_w / aspect
    k = int(e["texture_scale"])
    px = (max(1, round(new_w * k)), max(1, round(new_h * k)))
    if max(px) > MAX_SIDE_PX:
        s = MAX_SIDE_PX / max(px)
        px = (max(1, int(px[0] * s)), max(1, int(px[1] * s)))

    big = Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA")
    small = np.asarray(resize_rgba(big, px)).astype(np.float32) / 255.0
    color = np.dstack([qm.grade(small[..., :3], e.get("grade", {}), "prop"), small[..., 3]])
    art_dir.mkdir(parents=True, exist_ok=True)
    qm.to_image(color).save(art_dir / f"{pid}.png", optimize=True)
    normal = dict(e.get("normal") or {})
    profile = normal.pop("profile", None) or cfg.get("normal_profiles", {}).get(pid, cfg.get("normal_default", "pillow"))
    if profile != "legacy":  # BG-8: height field from the silhouette (depth_normals.py); "legacy" keeps the old luminance-bevel normals
        normal = {k: v for k, v in normal.items() if k in ("round_px", "relief", "detail", "detail_sigma", "gate", "strength")}
        normal["profile"] = profile
    qm.to_image(qm.normal_map(color, **normal)).save(art_dir / f"{pid}_n.png", optimize=True)

    has_glow = False
    g = None
    glow_file = art_dir / f"{pid}_glow.png"
    if e.get("glow"):
        g = qm.glow_mask(np.dstack([qm.grade(small[..., :3], e.get("glow_source_grade", {})), small[..., 3]]), e["glow"])
        if g is not None:
            g[..., :3] = qm.grade(g[..., :3], e.get("glow_grade", {}))
            qm.to_image(g).save(glow_file, optimize=True)
            has_glow = True
    if not has_glow and glow_file.exists():
        glow_file.unlink()

    tres = set_field(tres, "size", f"Vector2({fmt(new_w)}, {fmt(new_h)})")
    tres = set_field(tres, "has_glow", "true" if has_glow else "false") if (has_glow or re.search(r"^has_glow = true", tres, re.M)) else tres
    if e.get("light_from_glow"):
        # Lamp fixtures (BG-36): the light starts at the centre of the glowing part, wherever the model drew it.
        lx, ly = glow_centre(g)
        anchor.pop("light_offset", None)
        tres = set_field(tres, "light_offset", f"Vector2({fmt(lx * new_w)}, {fmt(ly * new_h)})")
    elif "light_offset" not in anchor:
        m = re.search(r"^light_offset = Vector2\(([-\d.]+), ([-\d.]+)\)", tres, re.M)
        if m:
            anchor["light_offset"] = [float(m.group(1)), float(m.group(2))]
    if not e.get("light_from_glow") and "light_offset" in anchor and old_w > 0 and old_h > 0:
        lx, ly = anchor["light_offset"]
        tres = set_field(tres, "light_offset", f"Vector2({fmt(lx * new_w / old_w)}, {fmt(ly * new_h / old_h)})")
    for key, value in (e.get("data") or {}).items():
        tres = set_field(tres, key, value if isinstance(value, str) else json.dumps(value))
    tres_path.write_text(tres, encoding="utf-8")
    print(f"ok    {pid:18} {px[0]}x{px[1]}px  size {fmt(new_w)}x{fmt(new_h)}  glow={has_glow}")
    return True


def sheet(entries: list[dict], out: Path, cell: int = 300) -> None:
    """Contact sheet (albedo on a dark checker, then normal, then glow) for a quick look."""
    cols = 2
    ids = [e["id"] for e in entries]
    rows = math.ceil(len(ids) / cols)
    img = Image.new("RGB", (cols * (cell * 3 + 30), rows * (cell + 24)), (28, 30, 42))
    d = ImageDraw.Draw(img)
    for i, pid in enumerate(ids):
        ox, oy = (i % cols) * (cell * 3 + 30), (i // cols) * (cell + 24)
        d.text((ox + 4, oy + 4), pid, fill=(220, 220, 230))
        for j, suffix in enumerate(["", "_n", "_glow"]):
            p = entry_dirs(entries[i])[0] / f"{pid}{suffix}.png"
            if not p.exists():
                continue
            im = Image.open(p).convert("RGBA")
            s = min(cell / im.width, cell / im.height)
            im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
            tile = Image.new("RGBA", (cell, cell), (46, 48, 62, 255) if suffix != "_glow" else (6, 6, 10, 255))
            tile.alpha_composite(im, ((cell - im.width) // 2, cell - im.height))
            img.paste(tile.convert("RGB"), (ox + j * (cell + 8), oy + 20))
    img.save(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=[])
    ap.add_argument("--regen", action="store_true")
    ap.add_argument("--no-gen", action="store_true")
    ap.add_argument("--sheet", default="")
    ap.add_argument("--pipeline", default="qwen_props", help="list name in assets_src/pipeline/ (without .json)")
    args = ap.parse_args()
    global PIPELINE
    PIPELINE = ROOT / "assets_src" / "pipeline" / f"{args.pipeline}.json"
    raw, cfg = load_cfg(PIPELINE)
    entries = [e for e in cfg["props"] if not args.only or e["id"] in args.only]
    failed = 0
    for e in entries:
        try:
            failed += 0 if process(e, cfg, args.regen, args.no_gen) else 1
        except ComfyFailure as ex:  # the server stays broken after every retry: stop instead of failing every remaining entry
            print(f"STOP  {e.get('id')}: {ex}", file=sys.stderr)
            PIPELINE.write_text(json.dumps(raw, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")
            return 2
        except Exception as ex:  # one bad entry must not block the rest
            failed += 1
            print(f"FAIL  {e.get('id')}: {ex}", file=sys.stderr)
        PIPELINE.write_text(json.dumps(raw, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")  # remembers anchors
    # aliases (the see-through front trees) reuse a tree's picture; their size follows the tree's new proportions
    made = {e["id"] for e in entries}
    aliases = [a for a in json.loads((ROOT / "assets_src" / "pipeline" / "props.json").read_text(encoding="utf-8")).get("aliases", []) if a["of"] in made]
    if aliases:
        make_aliases({"aliases": aliases})
    if args.sheet:
        sheet(entries, Path(args.sheet))
    return 1 if failed else 0


if __name__ == "__main__":
    from texture_import import finish_pipeline
    sys.exit(finish_pipeline(main()))
