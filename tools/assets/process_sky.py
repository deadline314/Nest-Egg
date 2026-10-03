"""Build the seamless parallax sky strips (NE-57 / NE-60 / BG-4).

Usage: python tools/assets/process_sky.py [--only ID ...]

Reads assets_src/pipeline/backdrop.json ("skies" list). For every entry writes art/environment/backdrop/<id>.webp.

Entries with a "cel" block (BG-4, the current look) are painted by tools/assets/cel_sky.py: flat colour bands, flat
clouds with a hard shade colour, stepped horizon glow, left and right edges wrap by construction. Keys: width, height,
top_fade, cel{...} (see cel_sky.py); output is lossless WebP because flat colour compresses small and keeps edges clean.

Entries without "cel" (legacy, no longer used) take the HDRI path: a horizontally seamless strip cut from the equirectangular panorama between two elevation angles, rolled by yaw_deg,
graded (brightness / contrast / saturation / tint / gamma live in the JSON), with an optional additive city-glow gradient
at the horizon and a transparent fade at the top so it blends into the in-game gradient sky above it.
Output is lossy WebP (photographic noise makes PNG several MB); the size budget is checked.
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cel_sky  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "assets_src" / "raw"
PIPELINE = ROOT / "assets_src" / "pipeline" / "backdrop.json"
OUT = ROOT / "art" / "environment" / "backdrop"
MAX_WIDTH = 4096
MAX_BYTES = 1_200_000
LUMA = np.array([0.299, 0.587, 0.114], dtype=np.float32)


def grade(a: np.ndarray, g: dict) -> np.ndarray:
    a = a ** float(g.get("gamma", 1.0))
    mean = a.mean()
    a = (a - mean) * float(g.get("contrast", 1.0)) + mean
    lum = a @ LUMA
    a = lum[..., None] + (a - lum[..., None]) * float(g.get("saturation", 1.0))
    a = a * float(g.get("brightness", 1.0)) * np.array(g.get("tint", [1, 1, 1]), dtype=np.float32)
    return np.clip(a, 0.0, 1.0)


def save_webp(spec: dict, rgb: np.ndarray, note: str) -> bool:
    height, width = rgb.shape[:2]
    alpha = np.ones((height, width, 1), dtype=np.float32)
    fade = int(height * float(spec.get("top_fade", 0.25)))
    if fade > 0:
        alpha[:fade, :, 0] = np.linspace(0.0, 1.0, fade, dtype=np.float32)[:, None]
    rgba = np.concatenate([rgb, (alpha * 255.0 + 0.5).astype(np.uint8)], axis=2)
    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{spec['id']}.webp"
    if spec.get("cel") is not None:
        Image.fromarray(rgba, "RGBA").save(path, "WEBP", lossless=True, quality=100, method=6)
    else:
        Image.fromarray(rgba, "RGBA").save(path, "WEBP", quality=int(spec.get("quality", 82)), method=6)
    size = path.stat().st_size
    if size > MAX_BYTES:
        print(f"FAIL  {spec['id']}: {size} bytes exceeds budget {MAX_BYTES}", file=sys.stderr)
        path.unlink()
        return False
    print(f"ok    {spec['id']:16} {width}x{height}  {size // 1024} KB  <- {note}")
    return True


def process_cel(spec: dict) -> bool:
    width = min(int(spec.get("width", MAX_WIDTH)), MAX_WIDTH)
    height = int(spec["height"])
    rgb = cel_sky.render(spec["cel"], width, height)
    return save_webp(spec, rgb, "cel_sky")


def process(spec: dict) -> bool:
    if spec.get("cel") is not None:
        return process_cel(spec)
    folder = RAW / spec["source"]
    files = sorted(folder.glob("*.jpg"))
    if not files:
        print(f"FAIL  {spec['id']}: no panorama in {folder}", file=sys.stderr)
        return False
    pano = Image.open(files[0]).convert("RGB")
    w, h = pano.size
    e0, e1 = spec["elevation"]  # degrees above the horizon, e0 < e1
    top, bottom = int((0.5 - e1 / 180.0) * h), int((0.5 - e0 / 180.0) * h)
    strip = pano.crop((0, top, w, bottom))
    width = min(int(spec.get("width", MAX_WIDTH)), MAX_WIDTH)
    height = int(round(strip.height * width / strip.width))
    strip = strip.resize((width, height), Image.LANCZOS)
    a = np.asarray(strip).astype(np.float32) / 255.0
    a = np.roll(a, int(spec.get("yaw_deg", 0.0) / 360.0 * width), axis=1)
    a = grade(a, spec.get("grade", {}))
    glow = spec.get("horizon_glow")
    if glow:
        t = np.linspace(1.0, 0.0, height, dtype=np.float32)[:, None, None]  # 1 at the bottom (horizon)
        weight = np.clip(t ** float(glow.get("falloff", 2.0)), 0.0, 1.0) * float(glow.get("strength", 0.3))
        a = np.clip(a + weight * np.array(glow["color"], dtype=np.float32), 0.0, 1.0)
    return save_webp(spec, (a * 255.0 + 0.5).astype(np.uint8), spec["source"])


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=[])
    args = ap.parse_args()
    cfg = json.loads(PIPELINE.read_text(encoding="utf-8"))
    failed = 0
    for spec in cfg.get("skies", []):
        if args.only and spec["id"] not in args.only:
            continue
        try:
            failed += 0 if process(spec) else 1
        except Exception as e:  # one bad entry must not block the rest
            failed += 1
            print(f"FAIL  {spec.get('id')}: {e}", file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
