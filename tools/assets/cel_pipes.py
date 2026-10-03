"""Cel-shaded pipe props painted by script (BG-10): pipe_vertical, pipe_horizontal, facility_pipes.

Usage: python tools/assets/cel_pipes.py [--only ID ...]

Writes art/environment/props/<id>.png and <id>_n.png (OpenGL normals, Y+ up). Pipes are long thin straight things the
image model draws badly (it bends them, or breaks the 1:10 proportion), and a script keeps them straight and the same
length as the data (size in data/environment/props/<id>.tres is not touched: 8 px per logical px).

Every shape is flat colour with a dark ink outline, a lit band on the upper left, a hard shaded band on the lower right,
flange rings with bolts, and a bright accent band; the colour layer and a height layer are painted together and the
normal map comes from the height layer.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cel_tile  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "art" / "environment" / "props"
SS = 3  # supersampling
K = 8   # texture pixels per logical pixel

INK = (10, 13, 26)
LIGHT = (176, 196, 230)


class Sprite:
    """Colour (RGBA) and height painted together on a transparent canvas."""

    def __init__(self, w: int, h: int):
        self.w, self.h = w, h
        self.col = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
        self.hgt = Image.new("L", (w * SS, h * SS), 128)
        self.dc, self.dh = ImageDraw.Draw(self.col), ImageDraw.Draw(self.hgt)

    def rect(self, x0, y0, x1, y1, fill=None, h=None, ink=None, ink_w=0.0):
        b = [x0 * SS, y0 * SS, x1 * SS, y1 * SS]
        if fill is not None:
            self.dc.rectangle(b, fill=tuple(fill) + (255,))
        if h is not None:
            self.dh.rectangle(b, fill=h)
        if ink is not None and ink_w > 0:
            w = max(1, int(round(ink_w * SS)))
            self.dc.rectangle(b, outline=tuple(ink) + (255,), width=w)
            self.dh.rectangle(b, outline=70, width=w)

    def circle(self, cx, cy, r, fill, h=None, ink=None, ink_w=0.0):
        b = [(cx - r) * SS, (cy - r) * SS, (cx + r) * SS, (cy + r) * SS]
        self.dc.ellipse(b, fill=tuple(fill) + (255,), outline=tuple(ink) + (255,) if ink else None,
                        width=max(1, int(ink_w * SS)) if ink else 0)
        if h is not None:
            self.dh.ellipse(b, fill=h)

    def finish(self) -> tuple[np.ndarray, np.ndarray]:
        col = cv2.resize(np.asarray(self.col), (self.w, self.h), interpolation=cv2.INTER_AREA)
        hgt = cv2.resize(np.asarray(self.hgt), (self.w, self.h), interpolation=cv2.INTER_AREA).astype(np.float32) / 255.0
        return col, hgt


def pipe_x(s: Sprite, x0: float, x1: float, y0: float, y1: float, base, strength: float = 1.0) -> None:
    """A vertical pipe run: lit band, body, shaded band, ink outline (three flat bands, light from the upper left)."""
    w = x1 - x0
    lit, shade = cel_tile.mix(base, LIGHT, 0.55), cel_tile.mul(base, 0.58)
    s.rect(x0, y0, x1, y1, base, 165, INK, 0.28 * K)
    s.rect(x0 + 0.22 * K, y0, x0 + w * 0.30, y1, lit, 185)
    s.rect(x0 + w * 0.68, y0, x1 - 0.22 * K, y1, shade, 135)


def flange(s: Sprite, cx: float, y: float, half: float, thick: float, base) -> None:
    """A flange ring across a vertical pipe with a bolt at each end."""
    s.rect(cx - half, y, cx + half, y + thick, cel_tile.mul(base, 0.8), 185, INK, 0.25 * K)
    s.rect(cx - half + 0.2 * K, y + 0.2 * K, cx + half - 0.2 * K, y + 0.2 * K + 0.3 * K, cel_tile.mix(base, LIGHT, 0.6), 195)
    for bx in (cx - half + 0.9 * K, cx + half - 0.9 * K):
        s.circle(bx, y + thick / 2, 0.28 * K, LIGHT, 200, INK, 0.1 * K)


def paint_vertical() -> Sprite:
    """6.7 x 64 logical: one tall pipe, flanges every 16 logical px, a bright accent band, a side stub with a valve."""
    w, h = int(6.7 * K), 64 * K
    s = Sprite(w, h)
    base = (84, 104, 140)
    cx = w * 0.46
    pipe_x(s, cx - 2.3 * K, cx + 2.3 * K, 0, h, base)
    for i in range(4):
        flange(s, cx, (i * 16 + 6) * K, 3.0 * K, 1.5 * K, base)
    for y in (24, 56):  # accent colour bands
        s.rect(cx - 2.3 * K, y * K, cx + 2.3 * K, (y + 1.6) * K, (40, 170, 190), 160, INK, 0.2 * K)
    s.rect(cx + 2.3 * K, 38 * K, w - 0.4 * K, 39.6 * K, cel_tile.mul(base, 0.8), 160, INK, 0.2 * K)  # stub
    s.circle(w - 1.0 * K, 38.8 * K, 0.9 * K, (180, 70, 60), 175, INK, 0.2 * K)  # valve wheel
    return s


def paint_horizontal() -> Sprite:
    v = paint_vertical()
    rot = lambda im: im.rotate(90, expand=True)  # noqa: E731  light was on the left: it ends up on the bottom, flip below
    out = Sprite(v.h, v.w)
    out.col = rot(v.col).transpose(Image.FLIP_TOP_BOTTOM)
    out.hgt = rot(v.hgt).transpose(Image.FLIP_TOP_BOTTOM)
    return out


def paint_facility() -> Sprite:
    """64 x 15.5 logical: three parallel horizontal pipes of different widths and colours with clamps, flanges and a valve."""
    w, h = 64 * K, int(15.5 * K)
    s = Sprite(w, h)
    pipes = [(0.3, 5.6, (86, 108, 146)), (5.9, 10.4, (176, 140, 52)), (10.6, 15.1, (58, 150, 150))]
    for y0, y1, base in pipes:
        lit, shade = cel_tile.mix(base, LIGHT, 0.55), cel_tile.mul(base, 0.58)
        top, bot = y0 * K, y1 * K
        s.rect(0, top, w, bot, base, 165, INK, 0.28 * K)
        s.rect(0, top + 0.25 * K, w, top + (bot - top) * 0.28, lit, 185)
        s.rect(0, top + (bot - top) * 0.70, w, bot - 0.25 * K, shade, 135)
        for fx in (10, 33, 54):  # flanges
            s.rect(fx * K, top - 0.3 * K, (fx + 1.5) * K, bot + 0.3 * K, cel_tile.mul(base, 0.8), 185, INK, 0.25 * K)
            s.rect(fx * K + 0.2 * K, top, fx * K + 0.6 * K, bot, cel_tile.mix(base, LIGHT, 0.6), 195)
    for cx in (21, 44):  # clamp straps across all three pipes
        s.rect(cx * K, 0.0, (cx + 2.4) * K, h, (52, 60, 80), 190, INK, 0.25 * K)
        s.rect(cx * K + 0.3 * K, 0.0, cx * K + 0.9 * K, h, cel_tile.mix((52, 60, 80), LIGHT, 0.5), 200)
        for by in (1.4, 8.0, 13.6):
            s.circle((cx + 1.2) * K, by * K, 0.3 * K, LIGHT, 205, INK, 0.1 * K)
    s.circle(40.0 * K, 3.0 * K, 1.5 * K, (190, 72, 62), 180, INK, 0.22 * K)   # valve wheel on the top pipe
    s.rect(39.6 * K, 3.0 * K - 0.15 * K, 40.4 * K, 3.0 * K + 0.15 * K, INK)
    s.rect(39.85 * K, 1.5 * K, 40.15 * K, 4.5 * K, INK)
    for ax in (4, 27, 49):  # direction arrows on the middle pipe
        s.rect(ax * K, 8.0 * K, (ax + 3) * K, 8.5 * K, (30, 24, 8))
        s.rect((ax + 2.2) * K, 7.6 * K, (ax + 3.4) * K, 8.9 * K, (30, 24, 8))
    return s


PAINTERS = {"pipe_vertical": paint_vertical, "pipe_horizontal": paint_horizontal, "facility_pipes": paint_facility}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", default=[])
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    for pid, fn in PAINTERS.items():
        if args.only and pid not in args.only:
            continue
        col, hgt = fn().finish()
        alpha = col[..., 3].astype(np.float32) / 255.0
        nrm = cel_tile.normals(hgt, 9.0)
        nrm_rgba = np.dstack([nrm, alpha])
        Image.fromarray(col, "RGBA").save(OUT / f"{pid}.png", optimize=True)
        Image.fromarray((np.clip(nrm_rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(OUT / f"{pid}_n.png", optimize=True)
        print(f"ok    {pid:16} {col.shape[1]}x{col.shape[0]} px")
    return 0


if __name__ == "__main__":
    sys.exit(main())
