"""Turn downloaded PBR textures into game terrain materials (NE-57 / NE-58).

Usage: python tools/assets/process_material.py [--only ID ...]

Reads assets_src/pipeline/materials.json. An entry with a "cel" block is painted by cel_tile.py (cel-shaded, flat colours
with ink lines, seamless by construction, BG-1); one with a "source" is cut from a downloaded PBR texture (NE-58).
For every entry writes, into art/environment/materials/:
  <id>_body.png  <id>_top.png  <id>_side.png   (+ _n.png normals, Godot 2D convention: Y+ up, OpenGL maps as-is)
and patches data/environment/materials/<id>.tres with the texture_scale that matches the written size,
so the game draws the texture at tile_world logical pixels per repeat.
Grading (brightness / contrast / saturation / tint) lives in the JSON, never in code, so one edit re-colours a material.
A seam metric is printed per body texture; above SEAM_LIMIT the source is not tileable and the entry is skipped.
"""
import argparse
import json
import re
import sys
import zlib
from pathlib import Path

import cv2
import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cel_tile  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "assets_src" / "raw"
PIPELINE = ROOT / "assets_src" / "pipeline" / "materials.json"
OUT = ROOT / "art" / "environment" / "materials"
DATA = ROOT / "data" / "environment" / "materials"
SEAM_LIMIT = 3.0
MAX_BODY_PX = 768  # size budget per texture; raise deliberately, not by accident
LUMA = np.array([0.299, 0.587, 0.114], dtype=np.float32)


def find_map(folder: Path, names: list[str]):
    for n in names:
        for p in sorted(folder.glob(f"*{n}*")):
            if p.suffix.lower() in (".jpg", ".png"):
                return p
    return None


def load_rgb(path: Path) -> np.ndarray:
    im = cv2.imread(str(path), cv2.IMREAD_COLOR)
    if im is None:
        raise IOError(f"cannot read {path}")
    return cv2.cvtColor(im, cv2.COLOR_BGR2RGB).astype(np.float32) / 255.0


def make_square(a: np.ndarray) -> np.ndarray:
    """Stack a tileable non-square map into a square one (stacking tileable copies stays tileable)."""
    h, w = a.shape[:2]
    if w == h:
        return a
    if w > h and w % h == 0:
        return np.tile(a, (w // h, 1, 1))
    if h > w and h % w == 0:
        return np.tile(a, (1, h // w, 1))
    raise ValueError(f"cannot square {w}x{h}")


def seam_ratio(a: np.ndarray) -> float:
    """How much worse the wrap-around edge is than a typical neighbouring-row step (1.0 = seamless)."""
    g = a.mean(axis=2)
    step_v = np.abs(np.diff(g, axis=0)).mean() + 1e-6
    step_h = np.abs(np.diff(g, axis=1)).mean() + 1e-6
    return float(max(np.abs(g[0] - g[-1]).mean() / step_v, np.abs(g[:, 0] - g[:, -1]).mean() / step_h))


def grade(a: np.ndarray, g: dict) -> np.ndarray:
    a = a ** float(g.get("gamma", 1.0))
    mean = a.mean()
    a = (a - mean) * float(g.get("contrast", 1.0)) + mean
    lum = a @ LUMA
    a = lum[..., None] + (a - lum[..., None]) * float(g.get("saturation", 1.0))
    a = a * float(g.get("brightness", 1.0)) * np.array(g.get("tint", [1, 1, 1]), dtype=np.float32)
    return np.clip(a, 0.0, 1.0)


def resize(a: np.ndarray, px: int) -> np.ndarray:
    return cv2.resize(a, (px, px), interpolation=cv2.INTER_AREA)


def to_vectors(n: np.ndarray, strength: float) -> np.ndarray:
    v = n * 2.0 - 1.0
    v[..., :2] *= strength
    return v / np.maximum(np.linalg.norm(v, axis=2, keepdims=True), 1e-6)


def save(path: Path, rgb: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    cv2.imwrite(str(path), cv2.cvtColor((np.clip(rgb, 0, 1) * 255.0 + 0.5).astype(np.uint8), cv2.COLOR_RGB2BGR),
                [cv2.IMWRITE_PNG_COMPRESSION, 9])


def bevel(length: int, depth_px: float) -> np.ndarray:
    """1 at index 0 fading to 0 after depth_px: the rounded lip of an exposed edge."""
    return np.clip(1.0 - np.arange(length, dtype=np.float32) / max(depth_px, 1.0), 0.0, 1.0)


def lip_color(spec: dict) -> np.ndarray:
    return np.array(spec.get("lip", [0.6, 0.7, 0.9]), dtype=np.float32)


def build_top(body, nrm, k, top_h, spec):
    h = int(top_h * k)
    img, v = body[:h].copy(), nrm[:h].copy()
    lip = bevel(h, k * 1.5)[:, None, None]
    img = img * (1.0 - 0.35 * lip) + lip_color(spec) * 0.2 * lip
    img = img * np.linspace(1.15, 0.7, h, dtype=np.float32)[:, None, None]
    v[..., 1] += 0.9 * bevel(h, k * 2.0)[:, None] - 0.6 * bevel(h, k * 1.0)[::-1][:, None]
    return img, v


def build_side(body, nrm, k, side_w, spec):
    w = int(side_w * k)
    img, v = body[:, :w].copy(), nrm[:, :w].copy()
    lip = bevel(w, k * 1.5)[None, :, None]
    img = img * (1.0 - 0.25 * lip) + lip_color(spec) * 0.12 * lip
    img = img * np.linspace(1.0, 0.65, w, dtype=np.float32)[None, :, None]
    v[..., 0] -= 0.9 * bevel(w, k * 2.0)[None, :]
    return img, v


def _rows(img: np.ndarray, a: int, b: int, color: np.ndarray, t: float) -> None:
    img[a:b] = img[a:b] * (1.0 - t) + color * t


def build_top_cel(body, nrm, k, top_h, spec):
    """Cel-shaded top strip: a dark ink outline at the very top, a bright rim light under it, then the body with a hard
    two-tone step (the lower part darker). Normals tilt up at the lip as in the photo version."""
    h = int(top_h * k)
    img, v = body[:h].copy(), nrm[:h].copy()
    ink = np.array(cel_tile.hexc(spec["cel"]["pal"]["ink"]), dtype=np.float32) / 255.0
    r0, r1 = max(1, int(0.7 * k)), max(2, int(2.1 * k))
    img[int(h * 0.62):] *= 0.78
    _rows(img, r0, r1, lip_color(spec), 0.55)
    img[:r0] = ink
    v[..., 1] += 0.9 * bevel(h, k * 2.0)[:, None] - 0.6 * bevel(h, k * 1.0)[::-1][:, None]
    return img, v


def build_side_cel(body, nrm, k, side_w, spec):
    """Cel-shaded side strip (mirror of the top strip, along the left edge)."""
    w = int(side_w * k)
    img, v = body[:, :w].copy(), nrm[:, :w].copy()
    ink = np.array(cel_tile.hexc(spec["cel"]["pal"]["ink"]), dtype=np.float32) / 255.0
    c0, c1 = max(1, int(0.7 * k)), max(2, int(2.1 * k))
    img[:, int(w * 0.62):] *= 0.78
    img[:, c0:c1] = img[:, c0:c1] * 0.45 + lip_color(spec) * 0.55
    img[:, :c0] = ink
    v[..., 0] -= 0.9 * bevel(w, k * 2.0)[None, :]
    return img, v


def patch_tres(path: Path, scale: int) -> None:
    text = path.read_text(encoding="utf-8")
    line = f"texture_scale = {scale}"
    if re.search(r"^texture_scale = .*$", text, re.M):
        text = re.sub(r"^texture_scale = .*$", line, text, flags=re.M)
    else:
        text = re.sub(r'(^id = &"[^"]*"\n)', lambda m: m.group(1) + line + "\n", text, count=1, flags=re.M)
    path.write_text(text, encoding="utf-8")


def process(spec: dict, defaults: dict) -> bool:
    spec = {**defaults, **spec}
    k, tile_world = int(spec["texture_scale"]), int(spec["tile_world"])
    px = k * tile_world
    if px > MAX_BODY_PX:
        print(f"FAIL  {spec['id']}: body {px}px exceeds budget {MAX_BODY_PX}px", file=sys.stderr)
        return False
    if "cel" in spec:
        tile = cel_tile.paint(spec["cel"]["kind"], px, k, zlib.crc32(spec["id"].encode()), spec["cel"])
        rgb, height = tile.finish()
        ratio = seam_ratio(rgb)
        body = grade(rgb, spec.get("grade", {}))
        nrm = cel_tile.normals(height, float(spec.get("normal_strength", 8.0))) * 2.0 - 1.0
        source = f"cel:{spec['cel']['kind']}"
    else:
        folder = RAW / spec["source"]
        diffuse = find_map(folder, ["Diffuse", "_Color"])
        normal = find_map(folder, ["nor_gl", "NormalGL"])
        if diffuse is None:
            print(f"FAIL  {spec['id']}: no diffuse map in {folder}", file=sys.stderr)
            return False
        col = make_square(load_rgb(diffuse))
        ratio = seam_ratio(col)
        if ratio > SEAM_LIMIT:
            print(f"FAIL  {spec['id']}: seam ratio {ratio:.1f} > {SEAM_LIMIT} (source not tileable)", file=sys.stderr)
            return False
        body = grade(resize(col, px), spec.get("grade", {}))
        if normal is not None:
            nrm = to_vectors(resize(make_square(load_rgb(normal)), px), float(spec.get("normal_strength", 1.0)))
        else:
            print(f"warn  {spec['id']}: no normal map, using flat", file=sys.stderr)
            nrm = np.zeros((px, px, 3), dtype=np.float32)
            nrm[..., 2] = 1.0
        source = spec["source"]
    top_fn, side_fn = (build_top_cel, build_side_cel) if "cel" in spec else (build_top, build_side)
    parts = {
        "body": (body, nrm),
        "top": top_fn(body, nrm, k, float(spec["top_height"]), spec),
        "side": side_fn(body, nrm, k, float(spec["side_width"]), spec),
    }
    for name, (img, v) in parts.items():
        v = v / np.maximum(np.linalg.norm(v, axis=2, keepdims=True), 1e-6)
        save(OUT / f"{spec['id']}_{name}.png", img)
        save(OUT / f"{spec['id']}_{name}_n.png", v * 0.5 + 0.5)
    tres = DATA / f"{spec['id']}.tres"
    if tres.exists():
        patch_tres(tres, k)
    else:
        print(f"warn  {spec['id']}: {tres.name} not found, texture_scale not patched", file=sys.stderr)
    print(f"ok    {spec['id']:16} body {px}px  scale {k}  seam {ratio:.2f}  <- {source}")
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=[])
    args = ap.parse_args()
    cfg = json.loads(PIPELINE.read_text(encoding="utf-8"))
    failed = 0
    for spec in cfg["materials"]:
        if args.only and spec["id"] not in args.only:
            continue
        try:
            failed += 0 if process(spec, cfg["defaults"]) else 1
        except Exception as e:  # one bad entry must not block the rest
            failed += 1
            print(f"FAIL  {spec.get('id')}: {e}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
