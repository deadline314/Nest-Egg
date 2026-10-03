"""Cel-shaded facade painter (NE-74): the canvas, wall painters, windows, ground-floor openings and roof caps.

A facade module is drawn on a Canvas: a colour image, a height image (it becomes the normal map) and a glow image
(window light, indicator lights, beacons), all drawn at 3x and averaged down so cel edges are clean but not jagged.
Style: flat colours, clean dark ink lines, hard-edged two-tone shadows (light from the upper left), no gradients.
Windows are chamfered octagons with panes; walls are painted straight into the module (no terrain material needed).

Everything is in "logical" units u (= k pixels, 1 u = 1 logical game pixel): a module is 64 u wide and 32 / 40 / 8 u high.
Shapes that cross the left or right edge are drawn again on the other side, so modules wrap horizontally; floors stack
because the top and bottom edges (floor ledge, hard shadow below it) are the same in every body variant.

Surface decoration (pipes, AC units, cameras, traces, LEDs, hazard stripes) lives in decor.py; assembly and JSON in
build_facades.py. Colours come from assets_src/pipeline/facades.json.
"""
from __future__ import annotations

import math
import random
import sys
from contextlib import contextmanager
from pathlib import Path

import cv2
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, str(Path(__file__).resolve().parent))
from cel_tile import hexc, mix, mul, normals  # noqa: E402  (shared colour helpers and the normal-map filter)

SS = 3
Color = tuple


def rgba(c, a: int = 255) -> tuple:
    c = tuple(int(v) for v in c)
    return c if len(c) == 4 else c + (a,)


class Canvas:
    """colour (RGBA) + height (L) + glow (RGBA), drawn at SS x. Coordinates are final pixels (floats allowed)."""

    def __init__(self, w: int, h: int, k: int, ink, rng: random.Random, transparent: bool = False):
        self.w, self.h, self.k, self.ink, self.rng = w, h, k, tuple(ink), rng
        n = (w * SS, h * SS)
        self.col = Image.new("RGBA", n, self.ink + ((0,) if transparent else (255,)))
        self.hgt = Image.new("L", n, 128)
        self.glw = Image.new("RGBA", n, (0, 0, 0, 0))
        self.ox = self.oy = 0
        self.wrap = True
        self.occ: list[tuple[float, float, float, float]] = []  # rectangles taken by windows and big decor (free-space checks)
        self._bind()

    def _bind(self) -> None:
        self.dc, self.dh, self.dg = ImageDraw.Draw(self.col), ImageDraw.Draw(self.hgt), ImageDraw.Draw(self.glw)

    @property
    def u(self) -> float:
        return float(self.k)

    # ---- primitives -------------------------------------------------------------------------------------------------------
    def _shifts(self, xs, margin: float):
        if not self.wrap:
            return [0]
        return [0] + ([self.w] if min(xs) - margin < 0 else []) + ([-self.w] if max(xs) + margin > self.w else [])

    def _P(self, pts, sx: float):
        return [((x + sx) * SS + self.ox, y * SS + self.oy) for x, y in pts]

    def poly(self, pts, fill=None, h=None, ink=None, ink_w: float = 0.0, ink_h=None, glow=None) -> None:
        for sx in self._shifts([p[0] for p in pts], ink_w):
            P = self._P(pts, sx)
            if fill is not None:
                self.dc.polygon(P, fill=rgba(fill))
            if h is not None:
                self.dh.polygon(P, fill=int(h))
            if glow is not None:
                self.dg.polygon(P, fill=rgba(glow))
            if ink is not None and ink_w > 0:
                w = max(1, int(round(ink_w * SS)))
                self.dc.line(P + [P[0]], fill=rgba(ink), width=w, joint="curve")
                if ink_h is not None:
                    self.dh.line(P + [P[0]], fill=int(ink_h), width=w, joint="curve")

    def rect(self, x0, y0, x1, y1, fill=None, h=None, ink=None, ink_w: float = 0.0, ink_h=None, glow=None) -> None:
        self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], fill, h, ink, ink_w, ink_h, glow)

    def ellipse(self, cx, cy, rx, ry, fill=None, h=None, ink=None, ink_w: float = 0.0, glow=None) -> None:
        for sx in self._shifts([cx - rx, cx + rx], ink_w):
            box = [(cx + sx - rx) * SS + self.ox, (cy - ry) * SS + self.oy, (cx + sx + rx) * SS + self.ox, (cy + ry) * SS + self.oy]
            self.dc.ellipse(box, fill=rgba(fill) if fill is not None else None, outline=rgba(ink) if ink else None,
                            width=max(1, int(ink_w * SS)) if ink else 0)
            if h is not None:
                self.dh.ellipse(box, fill=int(h))
            if glow is not None:
                self.dg.ellipse(box, fill=rgba(glow))

    def line(self, pts, fill=None, w: float = 1.0, h=None, glow=None, glow_w: float | None = None) -> None:
        for sx in self._shifts([p[0] for p in pts], w):
            P = self._P(pts, sx)
            width = max(1, int(round(w * SS)))
            if fill is not None:
                self.dc.line(P, fill=rgba(fill), width=width, joint="curve")
            if h is not None:
                self.dh.line(P, fill=int(h), width=width, joint="curve")
            if glow is not None:
                self.dg.line(P, fill=rgba(glow), width=max(1, int(round((glow_w if glow_w is not None else w) * SS))), joint="curve")

    def fill(self, color, h: int = 128) -> None:
        self.dc.rectangle([0, 0, self.col.width, self.col.height], fill=rgba(color))
        self.dh.rectangle([0, 0, self.col.width, self.col.height], fill=h)

    # ---- polygons used everywhere -----------------------------------------------------------------------------------------
    @staticmethod
    def octagon(x0, y0, x1, y1, cut) -> list:
        """Rectangle with all four corners cut: the window shape."""
        return [(x0 + cut, y0), (x1 - cut, y0), (x1, y0 + cut), (x1, y1 - cut), (x1 - cut, y1), (x0 + cut, y1), (x0, y1 - cut), (x0, y0 + cut)]

    @staticmethod
    def cut_top(x0, y0, x1, y1, cut) -> list:
        """Rectangle with the two top corners cut."""
        return [(x0 + cut, y0), (x1 - cut, y0), (x1, y0 + cut), (x1, y1), (x0, y1), (x0, y0 + cut)]

    @contextmanager
    def clip(self, pts):
        """Everything drawn inside the block is clipped to the polygon `pts` (colour, height and glow alike)."""
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        bx0, by0 = max(0, int(math.floor(min(xs) * SS)) - 1), max(0, int(math.floor(min(ys) * SS)) - 1)
        bx1, by1 = min(self.col.width, int(math.ceil(max(xs) * SS)) + 1), min(self.col.height, int(math.ceil(max(ys) * SS)) + 1)
        box = (bx0, by0, bx1, by1)
        saved = (self.col, self.hgt, self.glw, self.ox, self.oy, self.wrap)
        self.col, self.hgt, self.glw = (im.crop(box) for im in (saved[0], saved[1], saved[2]))
        self.ox, self.oy, self.wrap = -bx0, -by0, False
        self._bind()
        try:
            yield
        finally:
            tmp = (self.col, self.hgt, self.glw)
            self.col, self.hgt, self.glw, self.ox, self.oy, self.wrap = saved
            self._bind()
            mask = Image.new("L", (bx1 - bx0, by1 - by0), 0)
            ImageDraw.Draw(mask).polygon([(x * SS - bx0, y * SS - by0) for x, y in pts], fill=255)
            for dst, src in zip((self.col, self.hgt, self.glw), tmp):
                dst.paste(src, (bx0, by0), mask)

    def reserve(self, x0, y0, x1, y1, pad: float = 0.0) -> None:
        self.occ.append((x0 - pad, y0 - pad, x1 + pad, y1 + pad))

    def is_free(self, x0, y0, x1, y1) -> bool:
        for a0, b0, a1, b1 in self.occ:
            if x0 < a1 and x1 > a0 and y0 < b1 and y1 > b0:
                return False
        return True

    # ---- output -----------------------------------------------------------------------------------------------------------
    def finish(self, normal_strength: float = 4.0, glow_sigma: float = 1.1):
        size = (self.w, self.h)
        col = cv2.resize(np.asarray(self.col), size, interpolation=cv2.INTER_AREA)
        hgt = cv2.resize(np.asarray(self.hgt), size, interpolation=cv2.INTER_AREA).astype(np.float32) / 255.0
        g0 = np.asarray(self.glw).astype(np.float32) / 255.0  # premultiplied average: edge colours do not darken
        pre = cv2.resize(np.concatenate([g0[..., :3] * g0[..., 3:4], g0[..., 3:4]], axis=2), size, interpolation=cv2.INTER_AREA)
        glw = np.concatenate([np.clip(pre[..., :3] / np.clip(pre[..., 3:4], 1e-4, 1.0), 0, 1), pre[..., 3:4]], axis=2)
        n = normals(hgt, normal_strength, 1.0)
        n_img = Image.fromarray((np.dstack([n, np.ones(n.shape[:2], np.float32)]) * 255 + 0.5).astype(np.uint8), "RGBA")
        g = soften(glw, glow_sigma)
        return Image.fromarray(col, "RGBA"), n_img, Image.fromarray((g * 255 + 0.5).astype(np.uint8), "RGBA")


def soften(rgba_f: np.ndarray, sigma: float) -> np.ndarray:
    """Light-glow softening: premultiplied blur (colours do not bleed to black) plus a faint wide halo."""
    a = rgba_f[..., 3:4]
    pre = np.concatenate([rgba_f[..., :3] * a, a], axis=2)
    out = np.maximum(cv2.GaussianBlur(pre, (0, 0), sigma), cv2.GaussianBlur(pre, (0, 0), sigma * 3.0) * 0.4)
    alpha = np.clip(out[..., 3:4], 1e-4, 1.0)
    res = np.concatenate([np.clip(out[..., :3] / alpha, 0.0, 1.0), np.clip(out[..., 3:4], 0.0, 1.0)], axis=2)
    return res


# ---- palette ----------------------------------------------------------------------------------------------------------------
DEFAULT_PAL = {
    "ink": "#0b0d1a", "base": "#4a3e58", "light": "#6d5c80", "dark": "#2a2236", "mortar": "#1c1626",
    "frame": "#3a4258", "frame_light": "#6b7898", "glass": "#10182e", "glass_light": "#26385a",
    "metal": "#5a6478", "metal_dark": "#343c4e", "accent": "#a6742e", "accent2": "#2e6f86",
}


def pal_of(cfg: dict) -> dict:
    p = {**DEFAULT_PAL, **(cfg.get("pal") or {})}
    out = {k: ([hexc(c) for c in v] if k == "tones" else hexc(v)) for k, v in p.items()}
    out.setdefault("tones", [out["base"]])
    return out


# ---- walls ------------------------------------------------------------------------------------------------------------------

def wall_plaster(c: Canvas, p: dict, w: dict) -> None:
    """Plaster: flat base, hard two-tone groove rows (ink line + lit lip), stain patches and a crack."""
    u, W, H = c.u, c.w, c.h
    c.fill(p["base"], 128)
    step = float(w.get("groove", 8.0)) * u
    y = step
    while y < H - 0.5 * u:
        c.rect(0, y - 0.18 * u, W, y + 0.18 * u, p["mortar"], 100)
        c.rect(0, y + 0.18 * u, W, y + 0.55 * u, p["light"], 140)
        y += step
    for _ in range(int(w.get("stains", 5))):
        r = c.rng.uniform(1.6, 4.2) * u
        cx, cy = c.rng.uniform(0, W), c.rng.uniform(0, H)
        pts = [(cx + math.cos(a) * r * c.rng.uniform(0.6, 1.2), cy + math.sin(a) * r * 0.6 * c.rng.uniform(0.6, 1.2)) for a in np.linspace(0, math.tau, 9, endpoint=False)]
        c.poly(pts, mix(p["base"], p["dark"], 0.55), 124)
    for _ in range(int(w.get("cracks", 1))):
        x, y = c.rng.uniform(4 * u, W - 4 * u), c.rng.uniform(2 * u, H - 8 * u)
        pts = [(x, y)]
        for _i in range(5):
            x, y = x + c.rng.uniform(-1.2, 1.2) * u, y + c.rng.uniform(0.8, 2.0) * u
            pts.append((x, y))
        c.line(pts, p["mortar"], 0.25 * u, 80)


def wall_brick(c: Canvas, p: dict, w: dict) -> None:
    u, W, H = c.u, c.w, c.h
    bh, bw = float(w.get("row_h", 2.0)) * u, float(w.get("brick_w", 8.0)) * u
    rows = int(round(H / bh))
    bh = H / rows
    per = int(round(W / bw))
    bw = W / per
    mortar = 0.3 * u
    c.fill(p["mortar"], 90)
    for r in range(rows):
        shift = bw / 2 if r % 2 else 0
        for i in range(-1, per + 1):
            x0, y0 = i * bw - shift + mortar / 2, r * bh + mortar / 2
            x1, y1 = x0 + bw - mortar, y0 + bh - mortar
            base = c.rng.choice(p["tones"])
            c.rect(x0, y0, x1, y1, base, 150)
            c.rect(x0, y0, x1, y0 + 0.34 * u, mix(base, p["light"], 0.55), 160)      # lit top
            c.rect(x0, y1 - 0.5 * u, x1, y1, mul(base, 0.68), 135)                    # shaded bottom
            if c.rng.random() < float(w.get("chip", 0.12)):                           # chipped corner
                c.poly([(x1, y1), (x1 - 1.4 * u, y1), (x1, y1 - 0.9 * u)], p["mortar"], 90)
            if c.rng.random() < float(w.get("stain", 0.1)):
                c.rect(x0 + 0.6 * u, y0 + 0.5 * u, x1 - 0.6 * u, y1 - 0.5 * u, mul(base, 0.8), 145)


def wall_corrugated(c: Canvas, p: dict, w: dict) -> None:
    u, W, H = c.u, c.w, c.h
    ribs = int(w.get("ribs", 16))
    rw = W / ribs
    c.fill(p["base"], 128)
    for i in range(ribs):
        x0 = i * rw
        c.rect(x0, 0, x0 + rw * 0.30, H, mix(p["base"], p["light"], 0.55), 160)
        c.rect(x0 + rw * 0.30, 0, x0 + rw * 0.70, H, p["base"], 175)
        c.rect(x0 + rw * 0.70, 0, x0 + rw, H, mul(p["base"], 0.62), 120)
        c.rect(x0 + rw - 0.15 * u, 0, x0 + rw + 0.15 * u, H, p["mortar"], 70)
    for _ in range(int(w.get("rust", 5))):
        cx, cy = c.rng.uniform(0, W), c.rng.uniform(0, H)
        r = c.rng.uniform(1.0, 2.6) * u
        rust = p.get("accent", p["dark"])
        pts = [(cx + math.cos(a) * r * c.rng.uniform(0.6, 1.2), cy + math.sin(a) * r * c.rng.uniform(0.6, 1.4)) for a in np.linspace(0, math.tau, 8, endpoint=False)]
        c.poly(pts, mul(rust, 0.7), None)
    for _ in range(int(w.get("streaks", 6))):
        sx, sy = c.rng.uniform(0, W), c.rng.uniform(0, H)
        c.rect(sx, sy, sx + 0.35 * u, sy + c.rng.uniform(3, 9) * u, mul(p["base"], 0.72), None)


def wall_slab(c: Canvas, p: dict, w: dict) -> None:
    """Concrete cladding panels: flat tone per panel, bevel strips, ink joints, corner bolts, stains and cracks."""
    u, W, H = c.u, c.w, c.h
    cols, rows = int(w.get("cols", 4)), int(w.get("rows", 2))
    pw, ph = W / cols, H / rows
    gap = 0.5 * u
    c.fill(p["mortar"], 90)
    for r in range(rows):
        for i in range(cols):
            x0, y0, x1, y1 = i * pw + gap / 2, r * ph + gap / 2, (i + 1) * pw - gap / 2, (r + 1) * ph - gap / 2
            base = c.rng.choice(p["tones"])
            c.rect(x0, y0, x1, y1, base, 140)
            c.rect(x0, y0, x1, y0 + 0.4 * u, mix(base, p["light"], 0.5), 155)
            c.rect(x0, y0, x0 + 0.4 * u, y1, mix(base, p["light"], 0.4), 150)
            c.rect(x0, y1 - 0.6 * u, x1, y1, mul(base, 0.7), 128)
            c.rect(x1 - 0.5 * u, y0, x1, y1, mul(base, 0.76), 128)
            for bx, by in ((x0 + 1.4 * u, y0 + 1.4 * u), (x1 - 1.6 * u, y0 + 1.4 * u), (x0 + 1.4 * u, y1 - 1.8 * u), (x1 - 1.6 * u, y1 - 1.8 * u)):
                c.ellipse(bx, by, 0.42 * u, 0.42 * u, mul(base, 0.6), 165, p["mortar"], 0.13 * u)
    for _ in range(int(w.get("stains", 7))):
        r = c.rng.uniform(1.8, 4.5) * u
        cx, cy = c.rng.uniform(0, W), c.rng.uniform(0, H)
        pts = [(cx + math.cos(a) * r * c.rng.uniform(0.6, 1.2), cy + math.sin(a) * r * 0.7 * c.rng.uniform(0.6, 1.2)) for a in np.linspace(0, math.tau, 9, endpoint=False)]
        c.poly(pts, mul(c.rng.choice(p["tones"]), 0.78), 124)
    for _ in range(int(w.get("cracks", 2))):
        x, y = c.rng.uniform(2 * u, W - 2 * u), c.rng.uniform(1 * u, H - 8 * u)
        pts = [(x, y)]
        for _i in range(5):
            x, y = x + c.rng.uniform(-1.1, 1.1) * u, y + c.rng.uniform(0.7, 1.8) * u
            pts.append((x, y))
        c.line(pts, p["mortar"], 0.22 * u, 80)


def wall_panel(c: Canvas, p: dict, w: dict) -> None:
    """Steel wall panels in a grid with bevels, rivets and an optional stripe (facility walls)."""
    u, W, H = c.u, c.w, c.h
    cols, rows = int(w.get("cols", 4)), int(w.get("rows", 4))
    pw, ph = W / cols, H / rows
    gap = 0.45 * u
    c.fill(p["mortar"], 90)
    for r in range(rows):
        for i in range(cols):
            x0, y0, x1, y1 = i * pw + gap / 2, r * ph + gap / 2, (i + 1) * pw - gap / 2, (r + 1) * ph - gap / 2
            base = c.rng.choice(p["tones"])
            c.rect(x0, y0, x1, y1, base, 145)
            c.poly([(x0, y0), (x1, y0), (x1 - 0.5 * u, y0 + 0.5 * u), (x0 + 0.5 * u, y0 + 0.5 * u), (x0 + 0.5 * u, y1 - 0.5 * u), (x0, y1)], mix(base, p["light"], 0.55), 160)
            c.poly([(x1, y1), (x0, y1), (x0 + 0.5 * u, y1 - 0.5 * u), (x1 - 0.5 * u, y1 - 0.5 * u), (x1 - 0.5 * u, y0 + 0.5 * u), (x1, y0)], mul(base, 0.62), 122)
            if w.get("rivets", True):
                for rx, ry in ((x0 + 1.3 * u, y0 + 1.3 * u), (x1 - 1.3 * u, y0 + 1.3 * u), (x0 + 1.3 * u, y1 - 1.3 * u), (x1 - 1.3 * u, y1 - 1.3 * u)):
                    c.ellipse(rx, ry, 0.38 * u, 0.38 * u, mix(base, p["light"], 0.5), 175, p["mortar"], 0.12 * u)
            if w.get("vent") and (r + i) % 3 == 0:
                vx, vy = (x0 + x1) / 2, (y0 + y1) / 2
                for j in range(-1, 2):
                    c.rect(vx - 2.0 * u, vy + j * 1.0 * u - 0.22 * u, vx + 2.0 * u, vy + j * 1.0 * u + 0.22 * u, p["mortar"], 85)
    if w.get("stripe"):  # a painted band across the wall (continues across module edges)
        y = H * float(w["stripe"])
        c.rect(0, y - 0.8 * u, W, y + 0.8 * u, p["accent"], 150, p["mortar"], 0.15 * u)


def wall_curtain(c: Canvas, p: dict, w: dict) -> None:
    """Curtain wall: dark glass panels split by metal fins, each with a hard diagonal glare band."""
    u, W, H = c.u, c.w, c.h
    cols, rows = int(w.get("cols", 4)), int(w.get("rows", 2))
    pw, ph = W / cols, H / rows
    c.fill(p["mortar"], 90)
    for r in range(rows):
        for i in range(cols):
            x0, y0, x1, y1 = i * pw + 0.3 * u, r * ph + 0.3 * u, (i + 1) * pw - 0.3 * u, (r + 1) * ph - 0.3 * u
            base = c.rng.choice(p["tones"])
            c.rect(x0, y0, x1, y1, base, 120)
            band = c.rng.uniform(0.1, 0.4)
            g = [(x0 + (x1 - x0) * band, y0), (x0 + (x1 - x0) * (band + 0.18), y0), (x0 + (x1 - x0) * (band - 0.12), y1), (x0 + (x1 - x0) * (band - 0.3), y1)]
            with c.clip([(x0, y0), (x1, y0), (x1, y1), (x0, y1)]):
                c.poly(g, mix(base, p["light"], 0.3), None)
                c.rect(x0, y1 - (y1 - y0) * 0.2, x1, y1, mul(base, 0.7), None)
    for i in range(cols):
        x = i * pw
        c.rect(x - 0.35 * u, 0, x + 0.35 * u, H, p["metal"], 160)
        c.rect(x - 0.35 * u, 0, x - 0.1 * u, H, p["frame_light"], 170)
    for r in range(rows):
        y = r * ph
        c.rect(0, y - 0.3 * u, W, y + 0.3 * u, p["metal_dark"], 150)


WALLS = {"plaster": wall_plaster, "brick": wall_brick, "corrugated": wall_corrugated, "slab": wall_slab, "panel": wall_panel, "curtain": wall_curtain}


def paint_wall(c: Canvas, p: dict, wall: dict) -> None:
    kind = wall.get("kind", "plaster")
    if kind not in WALLS:
        raise KeyError(f"unknown facade wall kind '{kind}' (known: {', '.join(WALLS)})")
    WALLS[kind](c, p, wall)


# ---- floor ledge and shadow (identical in every body variant so floors stack) ------------------------------------------------

def floor_edges(c: Canvas, p: dict, top_shadow: bool = True, bottom_ledge: bool = True) -> None:
    """Hard shadow under the ledge of the floor above (top) and this floor's own ledge (bottom)."""
    u, W, H = c.u, c.w, c.h
    if top_shadow:
        c.rect(0, 0, W, 0.9 * u, mix(p["base"], p["dark"], 0.8), 112)
    if bottom_ledge:
        c.rect(0, H - 2.0 * u, W, H, p["light"], 160)
        c.rect(0, H - 1.5 * u, W, H - 0.55 * u, mix(p["base"], p["dark"], 0.45), 135)
        c.rect(0, H - 0.55 * u, W, H, p["ink"], 80)
        c.rect(0, H - 2.0 * u, W, H - 1.75 * u, mix(p["light"], (255, 255, 255), 0.25), 175)


# ---- windows ----------------------------------------------------------------------------------------------------------------

def lit_color(rng: random.Random, colors: list, gain: float) -> tuple:
    return tuple(int(255 * min(1.0, ch * gain * rng.uniform(0.78, 1.0))) for ch in rng.choice(colors))


def window(c: Canvas, p: dict, box: tuple, spec: dict, lit: tuple | None, rng: random.Random) -> None:
    """Chamfered octagon window: hard drop shade, ink-outlined frame, glass with glare, panes, sill (and grill / blind)."""
    u = c.u
    x0, y0, x1, y1 = box
    fw = float(spec.get("frame", 0.9)) * u
    cut = max(1.0, min(x1 - x0, y1 - y0) * float(spec.get("chamfer", 0.3)))
    outer = Canvas.octagon(x0 - fw, y0 - fw, x1 + fw, y1 + fw, cut + fw * 0.6)
    inner = Canvas.octagon(x0, y0, x1, y1, cut)
    c.reserve(x0 - fw - 1.0 * u, y0 - fw - 0.3 * u, x1 + fw + 1.4 * u, y1 + fw + 1.5 * u)
    # hard drop shade, down-right (light comes from the upper left)
    c.poly([(x + 0.9 * u, y + 0.9 * u) for x, y in outer], mix(p["base"], p["dark"], 0.85), 118)
    c.poly(outer, p["frame"], 150, p["ink"], 0.3 * u, 70)
    # lit top-left frame edges, shaded bottom-right edges
    c.line([outer[7], outer[0], outer[1]], p["frame_light"], 0.32 * u, 175)
    c.line([outer[3], outer[4], outer[5]], mul(p["frame"], 0.6), 0.32 * u, 120)
    glass = p["glass"] if lit is None else mix(p["glass"], lit, 0.42)
    c.poly(inner, glass, 70, p["ink"], 0.22 * u, 60)
    with c.clip(inner):
        gl = mix(glass, p["glass_light"] if lit is None else lit, 0.55 if lit is None else 0.2)
        wd = x1 - x0
        g0 = x0 + wd * float(spec.get("glare", 0.18))
        c.poly([(g0, y0 - u), (g0 + wd * 0.2, y0 - u), (g0 + wd * 0.2 - (y1 - y0) * 0.3, y1 + u), (g0 - (y1 - y0) * 0.3, y1 + u)], gl, None)
    pc, pr = (spec.get("panes") or [2, 2])
    bar = 0.42 * u
    bars = []
    for i in range(1, int(pc)):
        x = x0 + (x1 - x0) * i / pc
        bars.append([(x, y0), (x, y1)])
    for j in range(1, int(pr)):
        y = y0 + (y1 - y0) * j / pr
        bars.append([(x0, y), (x1, y)])
    for seg in bars:
        c.line(seg, p["frame"], bar, 145)
    if spec.get("grill"):  # iron bars in front of the glass
        n = int(spec["grill"])
        for i in range(1, n):
            x = x0 + (x1 - x0) * i / n
            c.line([(x, y0 + cut * 0.4), (x, y1 - cut * 0.4)], p["ink"], 0.3 * u, 100)
    if lit is not None:
        c.poly(inner, None, None, glow=lit + (235,))
        blind = float(spec.get("blind", 0.0))
        if blind > 0 and rng.random() < 0.35:  # half-drawn blind: a dimmer hard-edged band at the top
            with c.clip(inner):
                c.rect(x0 - u, y0 - u, x1 + u, y0 + (y1 - y0) * blind, None, None, glow=mul(lit, 0.42) + (235,))
        for seg in bars:
            c.line(seg, None, bar, None, glow=(0, 0, 0, 0))
    if spec.get("sill", True):
        sx0, sx1, sy = x0 - 1.0 * u, x1 + 1.0 * u, y1 + fw
        c.rect(sx0 + 0.6 * u, sy + 0.5 * u, sx1 + 0.6 * u, sy + 1.4 * u, mix(p["base"], p["dark"], 0.85), 115)  # shade under the sill
        c.rect(sx0, sy, sx1, sy + 0.95 * u, p["frame"], 155, p["ink"], 0.2 * u, 70)
        c.rect(sx0, sy, sx1, sy + 0.3 * u, p["frame_light"], 175)


def window_grid(c: Canvas, p: dict, spec: dict, rng: random.Random, colors: list, chance: float, gain: float, y_center: float,
                min_lit: int = 1) -> tuple[list, list]:
    """Windows in a grid; each is lit or dark as a whole (at least `min_lit` are lit). Returns (all boxes, lit boxes)."""
    u, W, H = c.u, c.w, c.h
    cols, rows = int(spec.get("cols", 3)), int(spec.get("rows", 1))
    w, h = float(spec["w"]) * u, float(spec["h"]) * u
    row_gap = float(spec.get("row_gap", 2.0)) * u
    total_h = rows * h + (rows - 1) * row_gap
    top = H * y_center - total_h / 2
    boxes = []
    margin = float(spec.get("margin", 0.0)) * u
    for r in range(rows):
        for i in range(cols):
            cx = margin + (i + 0.5) * (W - 2 * margin) / cols
            y0 = top + r * (h + row_gap)
            boxes.append((cx - w / 2, y0, cx + w / 2, y0 + h))
    lit_idx = {i for i in range(len(boxes)) if rng.random() < chance}
    while len(lit_idx) < min(min_lit, len(boxes)):
        lit_idx.add(rng.randrange(len(boxes)))
    for i, b in enumerate(boxes):
        window(c, p, b, spec, lit_color(rng, colors, gain) if i in lit_idx else None, rng)
    return boxes, [boxes[i] for i in sorted(lit_idx)]


# ---- ground-floor openings --------------------------------------------------------------------------------------------------

def shutter(c: Canvas, p: dict, cx: float, w: float, top: float, bottom: float, hazard: bool = False, lamp: tuple | None = None) -> None:
    """Roller shutter: slats in two flat tones, guide rails, a heavy bottom bar, a lock plate; optional hazard frame and lamp."""
    u = c.u
    x0, x1 = cx - w / 2, cx + w / 2
    c.reserve(x0 - 1.2 * u, top - 2.5 * u, x1 + 1.2 * u, bottom)
    c.poly([(x + 0.8 * u, y + 0.5 * u) for x, y in Canvas.cut_top(x0 - 0.9 * u, top - 0.9 * u, x1 + 0.9 * u, bottom, 2.2 * u)], mix(p["base"], p["dark"], 0.85), 118)
    frame = Canvas.cut_top(x0 - 0.9 * u, top - 0.9 * u, x1 + 0.9 * u, bottom, 2.2 * u)
    c.poly(frame, p["accent"] if hazard else p["frame"], 150, p["ink"], 0.3 * u, 70)
    if hazard:  # hazard frame: diagonal ink stripes over the accent colour (clipped to the frame)
        with c.clip(frame):
            for i in range(-3, int((x1 - x0 + 2 * u) / (1.8 * u)) + 6):
                xx = x0 - 0.9 * u + i * 1.8 * u
                c.poly([(xx, bottom), (xx + 0.9 * u, bottom), (xx + 0.9 * u + (bottom - top), top - 1 * u), (xx + (bottom - top), top - 1 * u)], p["ink"], None)
    door = Canvas.cut_top(x0, top, x1, bottom, 1.6 * u)
    c.poly(door, p["metal_dark"], 100, p["ink"], 0.22 * u, 60)
    with c.clip(door):
        y, i = top, 0
        while y < bottom:
            band = p["metal"] if i % 2 == 0 else mul(p["metal"], 0.8)
            c.rect(x0, y, x1, y + 1.5 * u, band, 130 + (i % 2) * 14)
            c.rect(x0, y, x1, y + 0.3 * u, mix(band, p["frame_light"], 0.5), 160)
            c.rect(x0, y + 1.5 * u - 0.22 * u, x1, y + 1.5 * u, p["ink"], 80)
            y += 1.5 * u
            i += 1
        c.rect(x0 + 0.3 * u, top, x0 + 0.9 * u, bottom, mul(p["metal"], 0.6), 118)  # guide rails
        c.rect(x1 - 0.9 * u, top, x1 - 0.3 * u, bottom, mul(p["metal"], 0.6), 118)
        c.rect(x0, bottom - 2.0 * u, x1, bottom, mul(p["metal"], 0.55), 160, p["ink"], 0.2 * u, 70)
        c.rect(x0, bottom - 2.0 * u, x1, bottom - 1.6 * u, p["frame_light"], 175)
    lx = cx + w * 0.22
    c.poly(Canvas.octagon(lx - 0.8 * u, bottom - 3.6 * u, lx + 0.8 * u, bottom - 2.3 * u, 0.35 * u), p["accent2"], 170, p["ink"], 0.15 * u)
    if lamp is not None:
        lamp_x, lamp_y = cx, top - 1.6 * u
        c.poly(Canvas.octagon(lamp_x - 1.6 * u, lamp_y - 0.5 * u, lamp_x + 1.6 * u, lamp_y + 0.5 * u, 0.3 * u), lamp, 165, p["ink"], 0.15 * u, glow=lamp + (240,))


def door(c: Canvas, p: dict, cx: float, w: float, top: float, bottom: float, lit: tuple | None, sign: tuple | None = None) -> None:
    """Steel door in a frame, a chamfered porthole (lit or dark), a push bar and an optional glowing sign above."""
    u = c.u
    x0, x1 = cx - w / 2, cx + w / 2
    c.reserve(x0 - 1.0 * u, top - 3.0 * u, x1 + 1.0 * u, bottom)
    frame = Canvas.cut_top(x0 - 0.8 * u, top - 0.8 * u, x1 + 0.8 * u, bottom, 1.3 * u)
    c.poly([(x + 0.8 * u, y + 0.5 * u) for x, y in frame], mix(p["base"], p["dark"], 0.85), 118)
    c.poly(frame, p["frame"], 150, p["ink"], 0.3 * u, 70)
    leaf = Canvas.cut_top(x0, top, x1, bottom, 1.0 * u)
    c.poly(leaf, p["metal"], 135, p["ink"], 0.2 * u, 70)
    c.rect(x1 - 0.8 * u, top, x1, bottom, mul(p["metal"], 0.62), 122)   # shaded edge
    c.rect(x0, top, x0 + 0.4 * u, bottom, p["frame_light"], 160)
    c.rect(x0 + 0.8 * u, top + (bottom - top) * 0.55, x1 - 1.0 * u, top + (bottom - top) * 0.55 + 0.4 * u, p["ink"], 80)
    pw, ph = w * 0.4, (bottom - top) * 0.28
    box = (cx - pw / 2, top + 1.6 * u, cx + pw / 2, top + 1.6 * u + ph)
    glass = p["glass"] if lit is None else mix(p["glass"], lit, 0.42)
    oct_ = Canvas.octagon(*box, 0.28 * min(pw, ph))
    c.poly(oct_, glass, 70, p["ink"], 0.25 * u, 60)
    if lit is not None:
        c.poly(oct_, None, None, glow=lit + (235,))
    c.rect(cx - 0.3 * u, bottom - (bottom - top) * 0.42, cx + 0.3 * u, bottom - (bottom - top) * 0.42 + 2.2 * u, p["frame_light"], 175, p["ink"], 0.12 * u)  # push bar
    if sign is not None:
        sx, sy = cx, top - 2.3 * u
        c.poly(Canvas.octagon(sx - w * 0.45, sy - 0.9 * u, sx + w * 0.45, sy + 0.9 * u, 0.5 * u), p["metal_dark"], 150, p["ink"], 0.2 * u)
        c.poly(Canvas.octagon(sx - w * 0.35, sy - 0.45 * u, sx + w * 0.35, sy + 0.45 * u, 0.25 * u), mix(p["glass"], sign, 0.5), None, glow=sign + (240,))


def shop_window(c: Canvas, p: dict, cx: float, w: float, top: float, bottom: float, lit: tuple, rng: random.Random, awning: tuple | None = None) -> None:
    """Lit display window (octagon, shelf and box silhouettes inside) under a zig-zag awning."""
    u = c.u
    x0, x1 = cx - w / 2, cx + w / 2
    c.reserve(x0 - 1.0 * u, top - 4.5 * u, x1 + 1.0 * u, bottom + 1.0 * u)
    ch = 0.22 * min(w, bottom - top)
    outer = Canvas.octagon(x0 - 1.0 * u, top - 1.0 * u, x1 + 1.0 * u, bottom + 1.0 * u, ch + 0.8 * u)
    inner = Canvas.octagon(x0, top, x1, bottom, ch)
    c.poly([(x + 0.9 * u, y + 0.9 * u) for x, y in outer], mix(p["base"], p["dark"], 0.85), 118)
    c.poly(outer, p["frame"], 150, p["ink"], 0.3 * u, 70)
    c.line([outer[7], outer[0], outer[1]], p["frame_light"], 0.32 * u, 175)
    c.poly(inner, mix(p["glass"], lit, 0.5), 70, p["ink"], 0.22 * u, 60)
    c.poly(inner, None, None, glow=lit + (235,))
    with c.clip(inner):  # interior silhouettes: shelf lines, boxes, a counter (transparent in the glow = dark shapes)
        shelf_y = [top + (bottom - top) * f for f in (0.38, 0.7)]
        for sy in shelf_y:
            c.rect(x0, sy, x1, sy + 0.5 * u, p["ink"], 80, glow=mul(lit, 0.55) + (235,))
        for _ in range(int(w / (3.4 * u))):
            bx = rng.uniform(x0 + 1.5 * u, x1 - 3 * u)
            sy = rng.choice(shelf_y)
            bw, bh = rng.uniform(1.4, 2.6) * u, rng.uniform(1.4, 3.0) * u
            c.rect(bx, sy - bh, bx + bw, sy, mul(lit, 0.28), None, glow=mul(lit, 0.5) + (235,))
        c.rect(x0, bottom - 3.0 * u, x1, bottom, p["ink"], 80, glow=mul(lit, 0.3) + (235,))  # counter
        mid = (x0 + x1) / 2
        c.line([(mid, top), (mid, bottom)], p["frame"], 0.45 * u, 145, glow=(0, 0, 0, 0))
    if awning is not None:
        ay = top - 1.0 * u
        a0, a1 = x0 - 1.8 * u, x1 + 1.8 * u
        c.rect(a0, ay - 3.2 * u, a1, ay, awning, 160, p["ink"], 0.25 * u, 70)
        n = max(2, int((a1 - a0) / (3.2 * u)))
        sw = (a1 - a0) / n
        for i in range(n):  # alternate stripes + zig-zag hem
            if i % 2 == 0:
                c.rect(a0 + i * sw, ay - 3.2 * u, a0 + (i + 1) * sw, ay, mul(awning, 0.62), 150)
            c.poly([(a0 + i * sw, ay), (a0 + (i + 1) * sw, ay), (a0 + (i + 0.5) * sw, ay + 1.1 * u)], awning if i % 2 else mul(awning, 0.62), 150, p["ink"], 0.2 * u)
        c.rect(a0, ay - 3.2 * u, a1, ay - 2.7 * u, mix(awning, (255, 255, 255), 0.35), 175)


def vent_grate(c: Canvas, p: dict, cx: float, w: float, top: float, bottom: float) -> None:
    u = c.u
    x0, x1 = cx - w / 2, cx + w / 2
    c.reserve(x0 - 0.8 * u, top - 0.8 * u, x1 + 0.8 * u, bottom + 0.8 * u)
    oct_ = Canvas.octagon(x0 - 0.8 * u, top - 0.8 * u, x1 + 0.8 * u, bottom + 0.8 * u, 1.6 * u)
    c.poly([(x + 0.8 * u, y + 0.8 * u) for x, y in oct_], mix(p["base"], p["dark"], 0.85), 118)
    c.poly(oct_, p["frame"], 150, p["ink"], 0.3 * u, 70)
    inner = Canvas.octagon(x0, top, x1, bottom, 1.2 * u)
    c.poly(inner, p["glass"], 70, p["ink"], 0.2 * u, 60)
    with c.clip(inner):
        y = top + 0.5 * u
        while y < bottom:
            c.rect(x0, y, x1, y + 0.9 * u, p["metal"], 140)
            c.rect(x0, y, x1, y + 0.25 * u, p["frame_light"], 165)
            y += 1.6 * u


def plinth(c: Canvas, p: dict, y0: float) -> None:
    """Ground-floor foot: a dark kerb band with a lit lip."""
    u, W, H = c.u, c.w, c.h
    c.rect(0, y0, W, H, mix(p["base"], p["dark"], 0.7), 122)
    c.rect(0, y0, W, y0 + 0.4 * u, p["light"], 160)
    c.rect(0, y0 + 0.4 * u, W, y0 + 0.65 * u, p["ink"], 80)
    c.rect(0, H - 0.5 * u, W, H, p["ink"], 80)


# ---- roof caps --------------------------------------------------------------------------------------------------------------

def _antenna(c: Canvas, p: dict, x: float, base_y: float, height: float, beacon: bool) -> None:
    u = c.u
    c.line([(x, base_y), (x, base_y - height)], p["metal_dark"], 0.5 * u, 150)
    c.line([(x - 0.15 * u, base_y), (x - 0.15 * u, base_y - height)], p["frame_light"], 0.18 * u, 170)
    c.line([(x - 1.2 * u, base_y - height * 0.55), (x + 1.2 * u, base_y - height * 0.55)], p["metal_dark"], 0.35 * u, 150)
    if beacon:
        r = 0.55 * u
        c.ellipse(x, base_y - height - 0.3 * u, r, r, (255, 40, 40), 175, p["ink"], 0.12 * u, glow=(255, 20, 20, 255))


def _vent(c: Canvas, p: dict, x: float, base_y: float, w: float, h: float) -> None:
    u = c.u
    c.poly([(x, base_y), (x, base_y - h + 0.8 * u), (x + 0.8 * u, base_y - h), (x + w - 0.8 * u, base_y - h), (x + w, base_y - h + 0.8 * u), (x + w, base_y)],
           p["metal"], 150, p["ink"], 0.2 * u, 70)
    c.rect(x + w * 0.65, base_y - h + 0.5 * u, x + w, base_y, mul(p["metal"], 0.62), 125)
    c.rect(x + 0.5 * u, base_y - h * 0.6, x + w - 0.5 * u, base_y - h * 0.6 + 0.3 * u, p["ink"], 80)


def _dish(c: Canvas, p: dict, x: float, base_y: float, r: float) -> None:
    u = c.u
    c.line([(x, base_y), (x, base_y - r * 0.9)], p["metal_dark"], 0.45 * u, 140)
    pts = [(x - r, base_y - r * 1.5), (x + r * 0.35, base_y - r * 2.0), (x + r * 0.35, base_y - r * 1.2), (x - r * 0.5, base_y - r * 0.8)]
    c.poly(pts, p["frame_light"], 160, p["ink"], 0.2 * u, 70)
    c.line([(x + r * 0.1, base_y - r * 1.6), (x + r * 1.0, base_y - r * 2.2)], p["metal_dark"], 0.3 * u, 140)


def _tank(c: Canvas, p: dict, x: float, base_y: float, w: float, h: float) -> None:
    u = c.u
    for lx in (x + 0.7 * u, x + w - 0.7 * u):
        c.line([(lx, base_y), (lx, base_y - 1.0 * u)], p["metal_dark"], 0.35 * u, 140)
    top = base_y - h
    c.poly([(x, base_y - 1.0 * u), (x, top + 0.9 * u), (x + 0.9 * u, top), (x + w - 0.9 * u, top), (x + w, top + 0.9 * u), (x + w, base_y - 1.0 * u)],
           p["accent2"], 150, p["ink"], 0.22 * u, 70)
    c.rect(x + w * 0.66, top + 0.6 * u, x + w, base_y - 1.0 * u, mul(p["accent2"], 0.6), 125)
    c.rect(x, base_y - 1.0 * u - h * 0.3, x + w, base_y - 1.0 * u - h * 0.3 + 0.3 * u, p["ink"], 85)


CLUTTER = {"antenna": lambda c, p, x, y: _antenna(c, p, x, y, min(3.6 * c.u, y - 1.3 * c.u), True),
           "mast": lambda c, p, x, y: _antenna(c, p, x, y, min(2.6 * c.u, y - 1.0 * c.u), False),
           "vent": lambda c, p, x, y: _vent(c, p, x, y, 3.2 * c.u, 2.4 * c.u), "dish": lambda c, p, x, y: _dish(c, p, x, y, 1.5 * c.u),
           "tank": lambda c, p, x, y: _tank(c, p, x, y, 4.4 * c.u, 3.4 * c.u)}


def cap_module(c: Canvas, p: dict, spec: dict, rng: random.Random) -> None:
    """Roof cap (8 u, transparent above the roofline): coping, a patterned frieze and a little roof clutter."""
    u, W, H = c.u, c.w, c.h
    kind = spec.get("kind", "parapet")
    wall_y = 4.4 * u  # roofline of the frieze
    base_col = p["base"]
    if kind == "saw":  # sawtooth industrial roof: four teeth with a vertical lit face
        n = int(spec.get("teeth", 4))
        tw = W / n
        c.rect(0, wall_y + 1.0 * u, W, H, base_col, 132)
        for i in range(n):
            x0 = i * tw
            c.poly([(x0, wall_y + 1.4 * u), (x0 + tw, 2.6 * u), (x0 + tw, H), (x0, H)], base_col, 138, p["ink"], 0.28 * u, 70)
            c.poly([(x0, wall_y + 1.4 * u), (x0 + tw, 2.6 * u), (x0 + tw, 3.2 * u), (x0, wall_y + 2.0 * u)], p["light"], 165)
            c.rect(x0 + tw - 1.0 * u, 3.2 * u, x0 + tw, H, mul(base_col, 0.66), 120)
            c.poly(Canvas.octagon(x0 + tw * 0.3, wall_y + 1.0 * u, x0 + tw * 0.75, H - 1.1 * u, 0.5 * u), p["glass"], 70, p["ink"], 0.18 * u)
        floor_y = wall_y + 1.4 * u
    elif kind == "pediment":  # parapet with a central triangular pediment
        c.rect(0, wall_y, W, H, base_col, 135, p["ink"], 0.28 * u, 70)
        px0, px1, apex = W * 0.28, W * 0.72, 0.8 * u
        c.poly([(px0, wall_y), ((px0 + px1) / 2, apex), (px1, wall_y)], base_col, 138, p["ink"], 0.3 * u, 70)
        c.poly([(px0, wall_y), ((px0 + px1) / 2, apex), ((px0 + px1) / 2, apex + 0.7 * u), (px0 + 1.0 * u, wall_y)], p["light"], 160)
        c.poly(Canvas.octagon(W / 2 - 1.5 * u, wall_y - 2.2 * u, W / 2 + 1.5 * u, wall_y - 0.3 * u, 0.6 * u), p["glass"], 70, p["ink"], 0.2 * u)
        floor_y = wall_y
    elif kind == "stepped":  # raised centre block with chamfered corners, lower wings with a lit coping
        c.rect(0, wall_y, W, H, base_col, 135)
        cx0, cx1, top = W * 0.32, W * 0.68, 2.0 * u
        c.poly(Canvas.octagon(cx0, top, cx1, wall_y + 1.4 * u, 1.0 * u), base_col, 140, p["ink"], 0.28 * u, 70)
        c.line([(cx0 + 0.2 * u, top + 1.0 * u), (cx0 + 1.0 * u, top + 0.2 * u), (cx1 - 1.0 * u, top + 0.2 * u)], p["light"], 0.4 * u, 175)
        c.rect(cx1 - 2.4 * u, top + 1.0 * u, cx1 - 0.15 * u, wall_y + 1.4 * u, mul(base_col, 0.66), 122)
        for i in range(3):  # louvre slits on the centre block
            lx = cx0 + 3.0 * u + i * 3.2 * u
            c.rect(lx, top + 1.2 * u, lx + 1.8 * u, top + 1.6 * u, p["ink"], 85)
        floor_y = wall_y
    else:  # parapet
        c.rect(0, wall_y, W, H, base_col, 135)
        floor_y = wall_y
    # frieze + coping (continues across the module edges)
    if kind not in ("stepped", "saw"):
        c.rect(0, wall_y - 0.2 * u, W, wall_y + 1.0 * u, p["light"], 165, p["ink"], 0.25 * u, 75)
    c.rect(0, H - 0.55 * u, W, H, p["ink"], 80)
    c.rect(0, floor_y + 1.6 * u, W, floor_y + 2.0 * u, mix(base_col, p["dark"], 0.45), 118)
    n = int(W / (2.0 * u))
    for i in range(n):  # dentils: small hard-shaded blocks under the coping
        x = (i + 0.5) * W / n
        if kind in ("saw", "stepped"):
            break
        c.rect(x - 0.45 * u, wall_y + 1.2 * u, x + 0.45 * u, wall_y + 2.4 * u, mul(base_col, 0.72), 125)
    for item in ([] if kind == "saw" else spec.get("clutter", [])):
        name = item["t"] if isinstance(item, dict) else item
        if rng.random() > (item.get("chance", 1.0) if isinstance(item, dict) else 1.0):
            continue
        x = (item["x"] if isinstance(item, dict) and "x" in item else rng.uniform(0.15, 0.8)) * W
        CLUTTER[name](c, p, x, floor_y)
