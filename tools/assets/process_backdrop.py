"""Build the parallax city layers (far skyline, mid buildings) from free assets (NE-57 / NE-61).

Usage: python tools/assets/process_backdrop.py [--only ID ...]

Reads assets_src/pipeline/backdrop.json ("layers" list). Two kinds, both write art/environment/backdrop/<id>.webp
plus <id>_glow.webp (window light) and a width of tile_logical_px x texture_scale so the layer repeats seamlessly
(LevelBackground tiles a layer every 640 logical px):
  pano_skyline  cut a band of a 360-degree HDRI preview (city skyline): span_deg wide, between two elevation angles,
                cross-faded at the wrap so left and right edges meet; the top fades to transparent.
                glow = the bright pixels of the source (lit windows, neon), kept as their own layer.
  city_blocks   assemble buildings out of the already-built facade modules (art/environment/facades): random widths
                and heights from a fixed seed, silhouettes darker the further away; windows glow through the modules' _glow.
Grading (brightness / contrast / saturation / tint / gamma) is in the JSON.
"""
import argparse
import json
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "assets_src" / "raw"
PIPELINE = ROOT / "assets_src" / "pipeline" / "backdrop.json"
OUT = ROOT / "art" / "environment" / "backdrop"
FACADES = ROOT / "art" / "environment" / "facades"
TILE_LOGICAL = 640
MAX_BYTES = 1_200_000
LUMA = np.array([0.299, 0.587, 0.114], dtype=np.float32)


def grade(a: np.ndarray, g: dict) -> np.ndarray:
    a = a ** float(g.get("gamma", 1.0))
    lum = a @ LUMA
    a = lum[..., None] + (a - lum[..., None]) * float(g.get("saturation", 1.0))
    a = (a - 0.5) * float(g.get("contrast", 1.0)) + 0.5
    a = a * float(g.get("brightness", 1.0)) * np.array(g.get("tint", [1, 1, 1]), dtype=np.float32)
    return np.clip(a, 0.0, 1.0)


def save_webp(path: Path, rgba: np.ndarray, quality: int) -> int:
    Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(path, "WEBP", quality=quality, method=6)
    return path.stat().st_size


def pano_skyline(spec: dict) -> tuple[np.ndarray, np.ndarray]:
    files = sorted((RAW / spec["source"]).glob("*.jpg"))
    pano = Image.open(files[0]).convert("RGB")
    w, h = pano.size
    e0, e1 = spec["elevation"]
    top, bottom = int((0.5 - e1 / 180.0) * h), int((0.5 - e0 / 180.0) * h)
    px_per_deg = w / 360.0
    out_w = int(TILE_LOGICAL * spec["texture_scale"])
    blend = int(out_w * float(spec.get("seam_blend", 0.12)))
    span_px = int(spec["span_deg"] * px_per_deg)
    extra = int(span_px * blend / out_w)
    left = int(((spec["yaw_deg"] % 360.0) - spec["span_deg"] / 2.0) * px_per_deg) % w
    pano_wrapped = Image.new("RGB", (w * 2, h))
    pano_wrapped.paste(pano, (0, 0)), pano_wrapped.paste(pano, (w, 0))
    band = pano_wrapped.crop((left, top, left + span_px + extra, bottom))
    out_h = int(round(band.height * out_w / span_px))
    band = band.resize((out_w + blend, out_h), Image.LANCZOS)
    a = np.asarray(band).astype(np.float32) / 255.0
    body, tail = a[:, :out_w].copy(), a[:, out_w:]
    ramp = np.linspace(0.0, 1.0, blend, dtype=np.float32)[None, :, None]
    body[:, :blend] = tail * (1.0 - ramp) + body[:, :blend] * ramp  # col 0 continues col out_w-1
    # glow: bright pixels of the source (before grading)
    v = body.max(axis=2)
    mask = np.clip((v - float(spec.get("glow_threshold", 0.7))) * 6.0, 0.0, 1.0)
    glow = np.concatenate([body, mask[..., None]], axis=2)
    graded = grade(body, spec.get("grade", {}))
    alpha = np.ones((out_h, out_w, 1), dtype=np.float32)
    fade = int(out_h * float(spec.get("top_fade", 0.3)))
    if fade > 0:
        alpha[:fade, :, 0] = np.linspace(0.0, 1.0, fade, dtype=np.float32)[:, None]
    glow[..., :3] = grade(glow[..., :3], spec.get("glow_grade", {"brightness": 1.0}))
    glow[..., 3] *= alpha[..., 0]
    return np.concatenate([graded, alpha], axis=2), glow


def city_blocks(spec: dict) -> tuple[np.ndarray, np.ndarray]:
    rng = random.Random(int(spec.get("seed", 1)))
    out_w = int(TILE_LOGICAL * spec["texture_scale"])
    out_h = int(spec["height_logical"] * spec["texture_scale"])
    canvas = np.zeros((out_h, out_w, 4), dtype=np.float32)
    glow = np.zeros((out_h, out_w, 4), dtype=np.float32)
    kinds = spec["facades"]
    k = float(spec["module_scale"]) * spec["texture_scale"]
    mod_w, floor_h, cap_h, ground_h = 64 * k, 32 * k, 8 * k, 40 * k
    x = 0.0
    while x < out_w:
        facade = rng.choice(kinds)
        cols = rng.choice(spec.get("widths", [1, 1, 2]))
        floors = rng.randint(*spec["floors"])
        width = int(mod_w * cols)
        if x + width > out_w:
            width = out_w - int(x)
            if width < mod_w * 0.4:
                break
        x0 = int(x)
        y = out_h
        parts = [("g", int(ground_h))] + [("b", int(floor_h))] * floors + [("cap", int(cap_h))]
        for kind, height in parts:
            files = sorted(FACADES.glob(f"{facade}_{kind}[0-9].png"))
            if not files:
                continue
            src = rng.choice(files)
            tile = Image.open(src).convert("RGBA").resize((max(1, width), max(1, height)), Image.LANCZOS)
            y -= height
            if y < -height:
                break
            ta = np.asarray(tile).astype(np.float32) / 255.0
            ty0, ty1 = max(0, y), min(out_h, y + height)
            canvas[ty0:ty1, x0:x0 + width] = ta[ty0 - y:ty1 - y, :width]
            gp = FACADES / (src.stem + "_glow.png")
            if gp.exists():
                ga = np.asarray(Image.open(gp).convert("RGBA").resize((max(1, width), max(1, height)), Image.NEAREST)).astype(np.float32) / 255.0
                glow[ty0:ty1, x0:x0 + width] = ga[ty0 - y:ty1 - y, :width]
        x += width + int(rng.choice(spec.get("gaps", [0, 0, 6])) * spec["texture_scale"])
    canvas[..., :3] = grade(canvas[..., :3], spec.get("grade", {}))
    glow[..., :3] = grade(glow[..., :3], spec.get("glow_grade", {"brightness": 1.0}))
    return canvas, glow


BUILDERS = {"pano_skyline": pano_skyline, "city_blocks": city_blocks}


def process(spec: dict) -> bool:
    color, glow = BUILDERS[spec["type"]](spec)
    OUT.mkdir(parents=True, exist_ok=True)
    q = int(spec.get("quality", 82))
    size = save_webp(OUT / f"{spec['id']}.webp", color, q)
    gsize = save_webp(OUT / f"{spec['id']}_glow.webp", glow, q)
    if max(size, gsize) > MAX_BYTES:
        print(f"FAIL  {spec['id']}: {max(size, gsize)} bytes exceeds {MAX_BYTES}", file=sys.stderr)
        return False
    print(f"ok    {spec['id']:16} {color.shape[1]}x{color.shape[0]}  {size // 1024}+{gsize // 1024} KB  [{spec['type']}]")
    return True


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=[])
    args = ap.parse_args()
    cfg = json.loads(PIPELINE.read_text(encoding="utf-8"))
    failed = 0
    for spec in cfg.get("layers", []):
        if args.only and spec["id"] not in args.only:
            continue
        try:
            failed += 0 if process(spec) else 1
        except Exception as e:  # one bad layer must not block the rest
            failed += 1
            print(f"FAIL  {spec.get('id')}: {e}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
