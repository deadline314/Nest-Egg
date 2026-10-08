"""Build the parallax city layers (far skyline, mid buildings) from free assets (NE-57 / NE-61).

Usage: python tools/assets/process_backdrop.py [--only ID ...]

Reads assets_src/pipeline/backdrop.json ("layers" list). Two kinds, both write art/environment/backdrop/<id>.webp
plus <id>_glow.webp (window light) and a width of tile_logical_px x texture_scale so the layer repeats seamlessly
(LevelBackground tiles a layer every 640 logical px):
  pano_skyline  cut a band of a 360-degree HDRI preview (city skyline): span_deg wide, between two elevation angles,
                cross-faded at the wrap so left and right edges meet; the top fades to transparent.
                glow = the bright pixels of the source (lit windows, neon), kept as their own layer.
  city_blocks   assemble buildings out of the already-built cel facade modules (art/environment/facades, BG-2): random widths
                and heights from a fixed seed, two rows (back row hazier and lower), cel silhouettes with an ink outline, a lit left
                edge and a shaded right side, cel roof clutter (antenna with a red beacon, tank, dish, vents, chimney, sign, duct),
                haze that makes far rows paler and bluer; windows glow through the modules' _glow. Each row's widths sum to exactly
                one tile, so the layer repeats without a seam. Spec keys: haze {color, back, front}, ink, outline, clutter_scale,
                back_glow, shapes (flat stepped slope gable crown chamfer sidetower twin needle cut).
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
import grade as grade_lib  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "assets_src" / "raw"
PIPELINE = ROOT / "assets_src" / "pipeline" / "backdrop.json"
OUT = ROOT / "art" / "environment" / "backdrop"
FACADES = ROOT / "art" / "environment" / "facades"
TILE_LOGICAL = 640
MAX_BYTES = 1_200_000
LUMA = np.array([0.299, 0.587, 0.114], dtype=np.float32)


def grade(a: np.ndarray, g: dict, use_master: bool = True) -> np.ndarray:
    """Entry grade, then the shared master grade (see grade.py); emissive layers pass use_master=False."""
    return grade_lib.grade_asset(a, g, "backdrop", "half", use_master)

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
    glow[..., :3] = grade(glow[..., :3], spec.get("glow_grade", {"brightness": 1.0}), use_master=False)
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
    elif shape == "sidetower":
        # a tall narrow tower on one side with a pyramid roof, a lower block beside it
        tw = int(width * rng.uniform(0.34, 0.44))
        left = rng.random() < 0.5
        x0 = 0 if left else width - tw
        spire = int(height * 0.12)
        base = spire + int(height * rng.uniform(0.12, 0.2))
        d.rectangle((0, base, width, height), fill=255)
        d.rectangle((x0, spire, x0 + tw, height), fill=255)
        d.polygon([(x0 - 1, spire), (x0 + tw + 1, spire), (x0 + tw // 2, 0)], fill=255)
    elif shape == "twin":
        # two pointed towers either side of a lower, sloped middle
        tw = int(width * 0.3)
        spire = int(height * 0.1)
        base = spire + int(height * 0.16)
        d.rectangle((0, base, width, height), fill=255)
        for x0 in (0, width - tw):
            d.rectangle((x0, spire, x0 + tw, height), fill=255)
            d.polygon([(x0, spire), (x0 + tw, spire), (x0 + tw // 2, 0)], fill=255)
        d.polygon([(tw, base), (width - tw, base), (width // 2, base - int(height * 0.06))], fill=255)
    elif shape == "needle":
        # flat block with a thin spike in the middle
        sw = max(3, int(width * 0.14))
        spike = int(height * rng.uniform(0.16, 0.24))
        x0 = (width - sw) // 2 + rng.randint(-width // 8, width // 8)
        d.rectangle((0, spike + int(height * 0.04), width, height), fill=255)
        d.polygon([(x0, spike + 2), (x0 + sw, spike + 2), (x0 + sw // 2, 0)], fill=255)
    elif shape == "cut":
        # one big diagonal corner cut
        c = int(min(width, height) * rng.uniform(0.3, 0.5))
        if rng.random() < 0.5:
            d.polygon([(0, 0), (width - c, 0), (width, c), (width, height), (0, height)], fill=255)
        else:
            d.polygon([(c, 0), (width, 0), (width, height), (0, height), (0, c)], fill=255)
    else:
        d.rectangle((0, 0, width, height), fill=255)
    return m


# ---- cel roof clutter -------------------------------------------------------------------------------------------------------

def _hexc(c) -> tuple:
    if isinstance(c, str):
        c = c.lstrip("#")
        return int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)
    return tuple(int(v) for v in c)


def _mixc(a, b, t: float) -> tuple:
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def _ink_poly(d: ImageDraw.ImageDraw, pts, fill, ink, w: int) -> None:
    d.polygon(pts, fill=fill)
    d.line(list(pts) + [pts[0]], fill=ink, width=w, joint="curve")


def roof_clutter(draw: ImageDraw.ImageDraw, glow: ImageDraw.ImageDraw, cx: int, y: int, q: float, rng: random.Random, pal: dict) -> None:
    """Cel-shaded roof clutter standing on the roofline at (cx, y): flat fill, ink outline, a lit left edge and a shaded right
    edge. q = pixels per logical px. Antenna tips are pure red in the glow layer so the window shader blinks them."""
    fill, light, dark, ink = pal["fill"], pal["light"], pal["dark"], pal["ink"]
    w = max(2, int(round(q * 0.5)))
    kind = rng.choice(["antenna", "tank", "dish", "vents", "chimney", "sign", "duct", "antenna", "tank", "none"])
    if kind == "antenna":
        h = int(rng.uniform(16, 32) * q)
        d_w = max(2, int(q * 0.7))
        draw.line((cx, y, cx, y - h), fill=ink, width=d_w + 2 * (w // 2))
        draw.line((cx, y, cx, y - h), fill=fill, width=d_w)
        for i in range(rng.choice([1, 2, 3])):
            yy = y - int(h * (0.4 + 0.17 * i))
            span = int((6 - i) * q)
            draw.line((cx - span, yy, cx + span, yy), fill=ink, width=w + 1)
            draw.line((cx - span, yy, cx + span, yy), fill=fill, width=max(1, w - 1))
        r = max(2, int(q * 1.0))
        draw.ellipse((cx - r - 1, y - h - r - 1, cx + r + 1, y - h + r + 1), fill=ink)
        draw.ellipse((cx - r, y - h - r, cx + r, y - h + r), fill=(200, 60, 60))
        glow.ellipse((cx - r, y - h - r, cx + r, y - h + r), fill=(255, 20, 20, 255))
    elif kind == "tank":
        tw, th = int(rng.uniform(11, 16) * q), int(rng.uniform(9, 13) * q)
        leg = int(5 * q)
        top = y - th - leg
        x0 = cx - tw // 2
        cut = max(2, int(tw * 0.18))
        for lx in (x0 + int(tw * 0.15), x0 + int(tw * 0.85)):
            draw.line((lx, y, lx, top + th), fill=ink, width=w + 2)
            draw.line((lx, y, lx, top + th), fill=dark, width=max(1, w - 1))
        draw.line((x0 + int(tw * 0.15), y - leg // 2, x0 + int(tw * 0.85), y - leg // 2), fill=ink, width=w)
        body = [(x0, top + th), (x0, top + cut), (x0 + cut, top), (x0 + tw - cut, top), (x0 + tw, top + cut), (x0 + tw, top + th)]
        _ink_poly(draw, body, fill, ink, w)
        draw.rectangle((x0 + int(tw * 0.68), top + cut, x0 + tw - w, top + th - w), fill=dark)
        draw.rectangle((x0 + w, top + cut, x0 + int(tw * 0.18), top + th - w), fill=light)
        draw.line((x0, top + th // 2, x0 + tw, top + th // 2), fill=ink, width=max(1, w - 1))
        cone = [(x0 + int(tw * 0.15), top), (x0 + int(tw * 0.85), top), (cx, top - int(tw * 0.28))]
        _ink_poly(draw, cone, dark, ink, w)
    elif kind == "dish":
        r = int(rng.uniform(5, 8) * q)
        draw.line((cx, y, cx, y - r), fill=ink, width=w + 2)
        draw.line((cx, y, cx, y - r), fill=dark, width=max(1, w - 1))
        pts = [(cx - r, y - int(r * 1.5)), (cx + int(r * 0.4), y - int(r * 2.0)), (cx + int(r * 0.4), y - int(r * 1.15)), (cx - int(r * 0.5), y - int(r * 0.85))]
        _ink_poly(draw, pts, light, ink, w)
        draw.line((cx + int(r * 0.1), y - int(r * 1.6), cx + int(r * 1.1), y - int(r * 2.3)), fill=ink, width=w)
    elif kind == "vents":
        for i in range(rng.choice([2, 3])):
            vw, vh = int(rng.uniform(4, 6) * q), int(rng.uniform(5, 9) * q)
            vx = cx + i * int(7.5 * q)
            c = max(1, vw // 4)
            _ink_poly(draw, [(vx, y), (vx, y - vh + c), (vx + c, y - vh), (vx + vw - c, y - vh), (vx + vw, y - vh + c), (vx + vw, y)], fill, ink, w)
            draw.rectangle((vx + int(vw * 0.68), y - vh + c, vx + vw - w, y - w), fill=dark)
            draw.line((vx + w, y - vh // 2, vx + vw - w, y - vh // 2), fill=ink, width=max(1, w - 1))
    elif kind == "chimney":
        cw, ch = int(rng.uniform(4, 6) * q), int(rng.uniform(10, 16) * q)
        _ink_poly(draw, [(cx - cw // 2, y), (cx - cw // 2 + 1, y - ch), (cx + cw // 2 - 1, y - ch), (cx + cw // 2, y)], fill, ink, w)
        draw.rectangle((cx + cw // 6, y - ch + w, cx + cw // 2 - w, y - w), fill=dark)
        draw.rectangle((cx - cw // 2 - w, y - ch - int(q), cx + cw // 2 + w, y - ch + 1), fill=light, outline=ink, width=max(1, w - 1))
    elif kind == "sign":
        sw, sh = int(rng.uniform(16, 24) * q), int(rng.uniform(7, 10) * q)
        leg = int(3 * q)
        x0, top = cx - sw // 2, y - leg - sh
        for lx in (x0 + int(sw * 0.2), x0 + int(sw * 0.8)):
            draw.line((lx, y + 1, lx, y - leg), fill=ink, width=w * 2 + 1)
            draw.line((lx, y + 1, lx, y - leg), fill=light, width=max(1, w))
        c = max(2, sh // 4)
        board = [(x0 + c, top), (x0 + sw - c, top), (x0 + sw, top + c), (x0 + sw, top + sh - c), (x0 + sw - c, top + sh), (x0 + c, top + sh), (x0, top + sh - c), (x0, top + c)]
        _ink_poly(draw, board, dark, ink, w)
        col = rng.choice([(255, 60, 150), (60, 220, 255), (255, 200, 70)])
        inner = [(x0 + c + w * 2, top + w * 2), (x0 + sw - c - w * 2, top + w * 2), (x0 + sw - w * 2, top + c + w), (x0 + sw - w * 2, top + sh - c - w), (x0 + sw - c - w * 2, top + sh - w * 2),
                 (x0 + c + w * 2, top + sh - w * 2), (x0 + w * 2, top + sh - c - w), (x0 + w * 2, top + c + w)]
        draw.polygon(inner, fill=_mixc(col, (0, 0, 0), 0.55))
        glow.polygon(inner, fill=tuple(int(v * 0.75) for v in col) + (210,))
        glow.line([(x0 + sw * 0.3, top + sh // 2), (x0 + sw * 0.7, top + sh // 2)], fill=(0, 0, 0, 0), width=max(1, w - 1))
    elif kind == "duct":
        dw, dh = int(rng.uniform(10, 16) * q), int(rng.uniform(5, 8) * q)
        p = max(2, int(2.2 * q))
        pts = [(cx, y), (cx, y - dh), (cx + dw, y - dh), (cx + dw, y - int(dh * 0.4)), (cx + dw - p, y - int(dh * 0.4)), (cx + dw - p, y - dh + p), (cx + p, y - dh + p), (cx + p, y)]
        _ink_poly(draw, pts, fill, ink, w)
        draw.rectangle((cx + p, y - dh + w, cx + dw - p, y - dh + p - 1), fill=light)


def build_building(facade: str, width: int, floors: int, k: float, rng: random.Random):
    """Stack the facade's ground / body / cap modules into one building image (RGBA colour + RGBA glow). A building wider than
    one module is built from several modules side by side (each floor picks its modules separately), so windows keep their shape."""
    floor_h, cap_h, ground_h = 32 * k, 8 * k, 40 * k
    parts = [("g", int(ground_h))] + [("b", int(floor_h))] * floors + [("cap", int(cap_h))]
    total = sum(h for _, h in parts)
    n = max(1, int(round(width / (64 * k))))
    xs = [width * i // n for i in range(n + 1)]
    color = Image.new("RGBA", (width, total), (0, 0, 0, 0))
    glow = Image.new("RGBA", (width, total), (0, 0, 0, 0))
    y = total
    for kind, height in parts:
        files = sorted(FACADES.glob(f"{facade}_{kind}[0-9].png"))
        if not files:
            continue
        y -= height
        for i in range(n):
            src = rng.choice(files)
            seg = (xs[i + 1] - xs[i], height)
            color.alpha_composite(Image.open(src).convert("RGBA").resize(seg, Image.LANCZOS), (xs[i], y))
            gp = FACADES / (src.stem + "_glow.png")
            if gp.exists():
                glow.alpha_composite(Image.open(gp).convert("RGBA").resize(seg, Image.LANCZOS), (xs[i], y))
    return color, glow


def paste_clipped(base: Image.Image, layer: Image.Image, x: int, y: int) -> None:
    """alpha_composite that also accepts a negative x (building cut by the left edge)."""
    if x < 0:
        layer = layer.crop((-x, 0, layer.width, layer.height))
        x = 0
    base.alpha_composite(layer, (x, y))


def _row_layout(rng: random.Random, spec: dict, out_w: int, ts: int, k: float, offset: float) -> list[tuple[int, int]]:
    """(x, width) of each building in a row. Widths and gaps are scaled so they sum to exactly out_w: the row repeats."""
    items, total = [], 0
    while total < out_w:
        width = int(64 * k * rng.choice(spec.get("widths", [1, 1, 2])) * rng.uniform(0.8, 1.15))
        gap = int(rng.choice(spec.get("gaps", [0, 0, 6])) * ts)
        items.append([width, gap])
        total += width + gap
    f = out_w / total
    out, x = [], int(offset * 64 * k)
    for i, (width, gap) in enumerate(items):
        w = max(8, int(width * f))
        out.append((x % out_w, w))
        x += w + int(gap * f)
    return out


def city_blocks(spec: dict) -> tuple[np.ndarray, np.ndarray]:
    """Cel-style city rows from the facade modules: silhouettes with ink outlines, a lit left edge and a hard-shaded right side,
    cel roof clutter, a haze that thickens (paler, bluer) with distance. Each row repeats at out_w exactly, so left and right meet."""
    rng = random.Random(int(spec.get("seed", 1)))
    ts = int(spec["texture_scale"])
    out_w, out_h = int(TILE_LOGICAL * ts), int(spec["height_logical"] * ts)
    k = float(spec["module_scale"]) * ts
    shapes = spec.get("shapes", ["flat", "stepped", "slope", "gable", "chamfer"])
    haze_cfg = spec.get("haze", {})
    haze_col = _hexc(haze_cfg.get("color", "#1a2142"))
    ink_col = _hexc(spec.get("ink", "#080a18"))
    outline = max(2, int(round(ts * float(spec.get("outline", 0.55)))))
    q = k * float(spec.get("clutter_scale", 1.3))
    # (haze amount, brightness, height factor, offset in modules, glow strength)
    rows = []
    if spec.get("back_row", True):
        rows.append((float(haze_cfg.get("back", 0.55)), float(spec.get("back_row_dim", 0.7)), 0.8, 0.5, float(spec.get("back_glow", 0.5))))
    rows.append((float(haze_cfg.get("front", 0.3)), 1.0, 1.0, 0.0, 1.0))
    canvases, glows = [], []
    for haze, dim, height_factor, offset, glow_gain in rows:
        canvas = Image.new("RGBA", (out_w, out_h), (0, 0, 0, 0))
        glow = Image.new("RGBA", (out_w, out_h), (0, 0, 0, 0))
        pal = {"ink": _mixc(ink_col, haze_col, haze * 0.6), "fill": _mixc((46, 56, 88), haze_col, haze), "light": _mixc((92, 108, 150), haze_col, haze),
               "dark": _mixc((26, 32, 54), haze_col, haze)}
        pal = {name: tuple(int(v * (dim if name != "ink" else 1.0)) for v in col) for name, col in pal.items()}
        for x, width in _row_layout(rng, spec, out_w, ts, k, offset):
            facade = rng.choice(spec["facades"])
            floors = max(2, int(rng.randint(*spec["floors"]) * height_factor))
            building, bglow = build_building(facade, width, floors, k, rng)
            if building.height > out_h:
                building = building.crop((0, building.height - out_h, width, building.height))
                bglow = bglow.crop((0, bglow.height - out_h, width, bglow.height))
            mask = shape_mask(building.width, building.height, rng.choice(shapes), rng)
            alpha = ImageChops.multiply(building.getchannel("A"), mask)
            bglow.putalpha(ImageChops.multiply(bglow.getchannel("A"), mask))
            rgb = np.asarray(building.convert("RGB")).astype(np.float32)
            rgb = rgb * (1.0 - haze) + np.array(haze_col, dtype=np.float32) * haze  # distance haze: paler and bluer
            rgb *= dim
            rs = max(2, int(width * 0.16))  # hard two-tone: lit left edge, shaded right side (light from the upper left)
            rgb[:, width - rs:] *= 0.76
            rgb[:, : max(2, int(width * 0.04))] *= 1.18
            dimmed = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8), "RGB").convert("RGBA")
            dimmed.putalpha(alpha)
            by = out_h - building.height
            a_np = np.asarray(alpha)
            grown = cv2.dilate((a_np > 8).astype(np.uint8), cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (2 * outline + 1, 2 * outline + 1)))
            ink_layer = Image.fromarray(np.dstack([np.full(a_np.shape, c, np.uint8) for c in pal["ink"]] + [grown * 255]).astype(np.uint8), "RGBA")
            col = int(building.width * rng.uniform(0.25, 0.75))
            clutter_kind_seed = rng.random()
            roof_y = None
            column = a_np[:, col]
            filled = np.nonzero(column > 128)[0]
            if len(filled):
                roof_y = by + int(filled[0])
            xs = [x, x - out_w] if x + width > out_w else [x]
            for xx in xs:
                _paste_wrapped(canvas, ink_layer, xx, by, out_w)
                _paste_wrapped(canvas, dimmed, xx, by, out_w)
                _paste_wrapped(glow, _scale_alpha(bglow, glow_gain), xx, by, out_w)
                if spec.get("decor", True) and roof_y is not None:
                    sub = random.Random(int(clutter_kind_seed * 1e9))
                    roof_clutter(ImageDraw.Draw(canvas), ImageDraw.Draw(glow), xx + col, roof_y, q, sub, pal)
        canvases.append(canvas)
        glows.append(glow)
    # composite rows back to front; window light of a back building is hidden by the buildings in front of it
    final, final_glow = canvases[0], glows[0]
    for canvas, glow in zip(canvases[1:], glows[1:]):
        keep = 1.0 - np.asarray(canvas.getchannel("A")).astype(np.float32) / 255.0
        g = np.asarray(final_glow).astype(np.float32)
        g[..., 3] *= keep
        final_glow = Image.fromarray(g.astype(np.uint8), "RGBA")
        final = Image.alpha_composite(final, canvas)
        final_glow = Image.alpha_composite(final_glow, glow)
    c = np.asarray(final).astype(np.float32) / 255.0
    g = np.asarray(final_glow).astype(np.float32) / 255.0
    c[..., :3] = grade(c[..., :3], spec.get("grade", {}))
    g[..., :3] = grade(g[..., :3], spec.get("glow_grade", {"brightness": 1.0}), use_master=False)
    return c, soften(g, max(1.0, ts * 0.45))


def _scale_alpha(img: Image.Image, f: float) -> Image.Image:
    if f >= 0.999:
        return img
    out = img.copy()
    out.putalpha(img.getchannel("A").point(lambda v: int(v * f)))
    return out


def _paste_wrapped(base: Image.Image, layer: Image.Image, x: int, y: int, out_w: int) -> None:
    """alpha_composite that accepts a negative x and a layer running past the right edge."""
    if x < 0:
        layer = layer.crop((-x, 0, layer.width, layer.height))
        x = 0
    if x + layer.width > out_w:
        layer = layer.crop((0, 0, out_w - x, layer.height))
    if layer.width > 0:
        base.alpha_composite(layer, (x, y))


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
    ap.add_argument("--pipeline", default=str(PIPELINE), help="alternative backdrop.json (for trying settings)")
    args = ap.parse_args()
    cfg = json.loads(Path(args.pipeline).read_text(encoding="utf-8"))
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
    from texture_import import finish_pipeline
    sys.exit(finish_pipeline(main()))
