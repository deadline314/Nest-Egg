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

import cv2
import numpy as np
from PIL import Image, ImageChops, ImageDraw

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


def soften(rgba: np.ndarray, sigma: float) -> np.ndarray:
    """Soften a glow image: premultiplied blur (colours do not bleed to black) plus a wide faint halo, so lit windows
    are not hard-edged rectangles."""
    a = rgba[..., 3:4]
    pre = np.concatenate([rgba[..., :3] * a, a], axis=2)
    core = cv2.GaussianBlur(pre, (0, 0), sigma)
    halo = cv2.GaussianBlur(pre, (0, 0), sigma * 3.0) * 0.45
    out = np.maximum(core, halo)
    alpha = np.clip(out[..., 3:4], 1e-4, 1.0)
    return np.concatenate([np.clip(out[..., :3] / alpha, 0.0, 1.0), np.clip(out[..., 3:4], 0.0, 1.0)], axis=2)


def shape_mask(width: int, height: int, shape: str, rng: random.Random) -> Image.Image:
    """Silhouette of a building: not always a box. 'L' image, 255 inside."""
    m = Image.new("L", (width, height), 0)
    d = ImageDraw.Draw(m)
    if shape == "stepped":
        tiers = rng.choice([2, 3])
        y = height
        w = width
        for t in range(tiers):
            tier_h = height // tiers + (height % tiers if t == 0 else 0)
            x0 = (width - w) // 2
            d.rectangle((x0, y - tier_h, x0 + w, y), fill=255)
            y -= tier_h
            w = int(w * rng.uniform(0.62, 0.8))
    elif shape == "slope":
        drop = int(height * rng.uniform(0.12, 0.22))
        left_high = rng.random() < 0.5
        d.polygon([(0, 0 if left_high else drop), (width, drop if left_high else 0), (width, height), (0, height)], fill=255)
    elif shape == "gable":
        peak = int(height * rng.uniform(0.14, 0.24))
        d.polygon([(0, peak), (width // 2, 0), (width, peak), (width, height), (0, height)], fill=255)
    elif shape == "crown":
        # a narrow tower rising out of the main block and ending in a spire
        tw = int(width * 0.42)
        x0 = (width - tw) // 2
        spire = int(height * 0.14)
        base = int(height * 0.2)
        d.rectangle((0, base + spire, width, height), fill=255)
        d.rectangle((x0, spire, x0 + tw, base + spire + 2), fill=255)
        d.polygon([(x0, spire), (x0 + tw, spire), (x0 + tw // 2, 0)], fill=255)
    elif shape == "chamfer":
        c = int(min(width, height) * rng.uniform(0.18, 0.3))
        d.polygon([(c, 0), (width - c, 0), (width, c), (width, height), (0, height), (0, c)], fill=255)
    else:
        d.rectangle((0, 0, width, height), fill=255)
    return m


def roof_decor(draw: ImageDraw.ImageDraw, glow_draw: ImageDraw.ImageDraw, cx: int, y_top: int, k: float, rng: random.Random, color: tuple) -> None:
    """Silhouette clutter on a roof: antenna, water tank on legs, dish, vents. Keeps the skyline from being a row of boxes."""
    kind = rng.choice(["antenna", "tank", "dish", "vents", "none", "antenna"])
    line = max(1, int(k * 0.6))
    if kind == "antenna":
        h = int(rng.uniform(14, 30) * k)
        draw.line((cx, y_top, cx, y_top - h), fill=color, width=line)
        r = max(2, int(k * 0.9))
        glow_draw.ellipse((cx - r, y_top - h - r, cx + r, y_top - h + r), fill=(255, 20, 20, 255))
        for i in range(rng.choice([1, 2, 3])):
            yy = y_top - int(h * (0.45 + 0.2 * i))
            draw.line((cx - int(5 * k), yy, cx + int(5 * k), yy), fill=color, width=max(1, line - 1))
    elif kind == "tank":
        tw, th = int(rng.uniform(9, 14) * k), int(rng.uniform(8, 12) * k)
        top = y_top - th - int(4 * k)
        draw.ellipse((cx - tw // 2, top, cx + tw // 2, top + th), fill=color)
        draw.rectangle((cx - tw // 2 + 2, top + th // 2, cx + tw // 2 - 2, top + th), fill=color)
        for lx in (-tw // 3, tw // 3):
            draw.line((cx + lx, top + th, cx + lx, y_top), fill=color, width=line)
    elif kind == "dish":
        r = int(rng.uniform(5, 8) * k)
        draw.pieslice((cx - r, y_top - 2 * r, cx + r, y_top), 180, 360, fill=color)
        draw.line((cx, y_top - r, cx + int(r * 0.7), y_top - int(r * 1.7)), fill=color, width=max(1, line - 1))
    elif kind == "vents":
        for i in range(rng.choice([2, 3])):
            vw, vh = int(rng.uniform(3, 5) * k), int(rng.uniform(4, 8) * k)
            vx = cx + i * int(7 * k)
            draw.rounded_rectangle((vx, y_top - vh, vx + vw, y_top), radius=vw // 2, fill=color)


def build_building(facade: str, width: int, floors: int, k: float, rng: random.Random):
    """Stack the facade's ground / body / cap modules into one building image (RGBA colour + RGBA glow)."""
    floor_h, cap_h, ground_h = 32 * k, 8 * k, 40 * k
    parts = [("g", int(ground_h))] + [("b", int(floor_h))] * floors + [("cap", int(cap_h))]
    total = sum(h for _, h in parts)
    color = Image.new("RGBA", (width, total), (0, 0, 0, 0))
    glow = Image.new("RGBA", (width, total), (0, 0, 0, 0))
    y = total
    for kind, height in parts:
        files = sorted(FACADES.glob(f"{facade}_{kind}[0-9].png"))
        if not files:
            continue
        src = rng.choice(files)
        y -= height
        color.paste(Image.open(src).convert("RGBA").resize((width, height), Image.LANCZOS), (0, y))
        gp = FACADES / (src.stem + "_glow.png")
        if gp.exists():
            glow.paste(Image.open(gp).convert("RGBA").resize((width, height), Image.LANCZOS), (0, y))
    return color, glow


def paste_clipped(base: Image.Image, layer: Image.Image, x: int, y: int) -> None:
    """alpha_composite that also accepts a negative x (building cut by the left edge)."""
    if x < 0:
        layer = layer.crop((-x, 0, layer.width, layer.height))
        x = 0
    base.alpha_composite(layer, (x, y))


def city_blocks(spec: dict) -> tuple[np.ndarray, np.ndarray]:
    rng = random.Random(int(spec.get("seed", 1)))
    ts = int(spec["texture_scale"])
    out_w, out_h = int(TILE_LOGICAL * ts), int(spec["height_logical"] * ts)
    k = float(spec["module_scale"]) * ts
    shapes = spec.get("shapes", ["flat", "stepped", "slope", "gable", "dome", "chamfer"])
    canvas = Image.new("RGBA", (out_w, out_h), (0, 0, 0, 0))
    glow = Image.new("RGBA", (out_w, out_h), (0, 0, 0, 0))
    rows = [(float(spec.get("back_row_dim", 0.55)), 0.8, 0.5)] if spec.get("back_row", True) else []
    rows.append((1.0, 1.0, 0.0))
    for dim, height_factor, offset in rows:  # back row first (dimmer, lower), then the front row
        x = -int(offset * 64 * k)
        while x < out_w:
            facade = rng.choice(spec["facades"])
            width = int(64 * k * rng.choice(spec.get("widths", [1, 1, 2])) * rng.uniform(0.8, 1.15))
            floors = max(2, int(rng.randint(*spec["floors"]) * height_factor))
            building, bglow = build_building(facade, width, floors, k, rng)
            if building.height > out_h:
                building = building.crop((0, building.height - out_h, width, building.height))
                bglow = bglow.crop((0, bglow.height - out_h, width, bglow.height))
            mask = shape_mask(building.width, building.height, rng.choice(shapes), rng)
            alpha = ImageChops.multiply(building.getchannel("A"), mask)
            bglow.putalpha(ImageChops.multiply(bglow.getchannel("A"), mask))
            dimmed = building.convert("RGB").point(lambda v: int(v * dim)).convert("RGBA")
            dimmed.putalpha(alpha)
            by = out_h - building.height
            paste_clipped(canvas, dimmed, x, by)
            if dim >= 1.0:
                paste_clipped(glow, bglow, x, by)
            bbox = alpha.getbbox()
            if spec.get("decor", True) and bbox:
                layer = Image.new("RGBA", (out_w, out_h), (0, 0, 0, 0))
                glow_layer = Image.new("RGBA", (out_w, out_h), (0, 0, 0, 0))
                col = int(building.width * rng.uniform(0.25, 0.75))
                column = np.asarray(alpha.crop((col, 0, col + 1, alpha.height)))[:, 0]
                filled = np.nonzero(column > 128)[0]
                if len(filled):
                    roof_decor(ImageDraw.Draw(layer), ImageDraw.Draw(glow_layer), x + col, by + int(filled[0]), k, rng, (10, 11, 20, 255))
                canvas.alpha_composite(layer)
                if dim >= 1.0:
                    glow.alpha_composite(glow_layer)
            x += width + int(rng.choice(spec.get("gaps", [0, 0, 6])) * ts)
    c = np.asarray(canvas).astype(np.float32) / 255.0
    g = np.asarray(glow).astype(np.float32) / 255.0
    c[..., :3] = grade(c[..., :3], spec.get("grade", {}))
    g[..., :3] = grade(g[..., :3], spec.get("glow_grade", {"brightness": 1.0}))
    return c, soften(g, max(1.0, ts * 0.45))


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
