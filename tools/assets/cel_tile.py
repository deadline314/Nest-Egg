"""Procedural cel-shaded tile painter for terrain materials (BG-1) and generated facade walls (BG-2).

A Tile is a colour image plus a height image, painted with flat colours, clean dark ink lines and hard-edged two-tone
shading (light from the upper left). Everything wraps around the edges, so a finished tile repeats without a seam,
and every shape is also written into the height image, which becomes the normal map. Nothing is random per run: the
seed comes from the material id, so a rebuild gives the same picture.

  t = Tile(px=512, k=8, seed=1)       px pixels square, k pixels per logical pixel
  t.fill(base); t.bevel_rect(...); t.blob(...); t.crack(...)
  rgb, height = t.finish()            float arrays at px x px (rgb 0..1, height 0..1)
  normals(height, strength)           OpenGL (Y+ up) normal map, the convention Godot 2D lighting expects

Painters per material kind live at the bottom (PAINTERS); their parameters come from assets_src/pipeline/materials.json.
"""
from __future__ import annotations

import math
import random

import cv2
import numpy as np
from PIL import Image, ImageDraw

SS = 3  # supersampling: edges are drawn at 3x and averaged down, so cel edges are clean but not jagged


def hexc(c) -> tuple[int, int, int]:
    """'#rrggbb' or [r, g, b] (0..255) -> tuple."""
    if isinstance(c, str):
        c = c.lstrip("#")
        return int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)
    return int(c[0]), int(c[1]), int(c[2])


def mix(a, b, t: float) -> tuple[int, int, int]:
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))  # type: ignore[return-value]


def mul(c, f: float) -> tuple[int, int, int]:
    return tuple(int(max(0, min(255, round(v * f)))) for v in c)  # type: ignore[return-value]


class Tile:
    def __init__(self, px: int, k: int, seed: int):
        self.px, self.k = px, k
        self.n = px * SS
        self.rng = random.Random(seed)
        self.col = Image.new("RGB", (self.n, self.n))
        self.hgt = Image.new("L", (self.n, self.n), 128)
        self.dc, self.dh = ImageDraw.Draw(self.col), ImageDraw.Draw(self.hgt)

    # ---- drawing (coordinates in final pixels, floats allowed) ---------------------------------------------------
    def _shifts(self, xs, ys, margin: float):
        sx = [0] + ([self.px] if min(xs) - margin < 0 else []) + ([-self.px] if max(xs) + margin > self.px else [])
        sy = [0] + ([self.px] if min(ys) - margin < 0 else []) + ([-self.px] if max(ys) + margin > self.px else [])
        return [(a, b) for a in sx for b in sy]

    def poly(self, pts, fill=None, h=None, ink=None, ink_w: float = 0.0, ink_h: int | None = None) -> None:
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        for ox, oy in self._shifts(xs, ys, ink_w):
            P = [((x + ox) * SS, (y + oy) * SS) for x, y in pts]
            if fill is not None:
                self.dc.polygon(P, fill=fill)
            if h is not None:
                self.dh.polygon(P, fill=h)
            if ink is not None and ink_w > 0:
                w = max(1, int(round(ink_w * SS)))
                self.dc.line(P + [P[0]], fill=ink, width=w, joint="curve")
                if ink_h is not None:
                    self.dh.line(P + [P[0]], fill=ink_h, width=w, joint="curve")

    def rect(self, x0, y0, x1, y1, fill=None, h=None, ink=None, ink_w: float = 0.0, ink_h: int | None = None) -> None:
        self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], fill, h, ink, ink_w, ink_h)

    def ellipse(self, cx, cy, rx, ry, fill=None, h=None, ink=None, ink_w: float = 0.0) -> None:
        for ox, oy in self._shifts([cx - rx, cx + rx], [cy - ry, cy + ry], ink_w):
            box = [(cx + ox - rx) * SS, (cy + oy - ry) * SS, (cx + ox + rx) * SS, (cy + oy + ry) * SS]
            self.dc.ellipse(box, fill=fill, outline=ink, width=max(1, int(ink_w * SS)) if ink else 0)
            if h is not None:
                self.dh.ellipse(box, fill=h)

    def line(self, pts, fill=None, w: float = 1.0, h: int | None = None) -> None:
        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
        for ox, oy in self._shifts(xs, ys, w):
            P = [((x + ox) * SS, (y + oy) * SS) for x, y in pts]
            width = max(1, int(round(w * SS)))
            if fill is not None:
                self.dc.line(P, fill=fill, width=width, joint="curve")
            if h is not None:
                self.dh.line(P, fill=h, width=width, joint="curve")

    def fill(self, color, h: int = 128) -> None:
        self.dc.rectangle([0, 0, self.n, self.n], fill=color)
        self.dh.rectangle([0, 0, self.n, self.n], fill=h)

    # ---- composite shapes ------------------------------------------------------------------------------------------
    def bevel_rect(self, x0, y0, x1, y1, base, hi, lo, bw: float, ink=None, ink_w: float = 0.0, h: int = 150) -> None:
        """A raised plate: flat base, light strips on the top and left edges, dark strips on the bottom and right (hard
        cel shading, no gradients), an ink outline, and a stepped height so the normal map tilts at the bevel."""
        self.rect(x0, y0, x1, y1, base, h - 22)
        self.rect(x0 + bw, y0 + bw, x1 - bw, y1 - bw, base, h)
        self.poly([(x0, y0), (x1, y0), (x1 - bw, y0 + bw), (x0 + bw, y0 + bw), (x0 + bw, y1 - bw), (x0, y1)], hi)
        self.poly([(x1, y1), (x0, y1), (x0 + bw, y1 - bw), (x1 - bw, y1 - bw), (x1 - bw, y0 + bw), (x1, y0)], lo)
        if ink is not None:
            self.rect(x0, y0, x1, y1, None, None, ink, ink_w, 70)

    def blob(self, cx, cy, r, fill, h=None, wobble: float = 0.35, pts: int = 11, ink=None, ink_w: float = 0.0, squash: float = 1.0) -> None:
        a0 = self.rng.uniform(0, math.tau)
        poly = []
        for i in range(pts):
            a = a0 + math.tau * i / pts
            rr = r * (1.0 + self.rng.uniform(-wobble, wobble))
            poly.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr * squash))
        self.poly(poly, fill, h, ink, ink_w)

    def crack(self, x, y, length, color, w: float, angle: float | None = None, branch: int = 2, h: int = 60) -> None:
        """Jagged ink crack with a few side branches."""
        ang = self.rng.uniform(0, math.tau) if angle is None else angle
        pts = [(x, y)]
        step = max(4.0, length / 9.0)
        for _ in range(int(length / step)):
            ang += self.rng.uniform(-0.7, 0.7)
            x, y = x + math.cos(ang) * step, y + math.sin(ang) * step
            pts.append((x, y))
        self.line(pts, color, w, h)
        for _ in range(branch):
            i = self.rng.randrange(1, len(pts))
            self.crack(pts[i][0], pts[i][1], length * self.rng.uniform(0.25, 0.45), color, max(1.0, w * 0.7),
                       ang + self.rng.choice([-1, 1]) * self.rng.uniform(0.6, 1.2), 0, h)

    def finish(self) -> tuple[np.ndarray, np.ndarray]:
        rgb = cv2.resize(np.asarray(self.col), (self.px, self.px), interpolation=cv2.INTER_AREA).astype(np.float32) / 255.0
        hgt = cv2.resize(np.asarray(self.hgt), (self.px, self.px), interpolation=cv2.INTER_AREA).astype(np.float32) / 255.0
        return rgb, hgt


def normals(height: np.ndarray, strength: float = 8.0, blur: float = 0.7) -> np.ndarray:
    """Height (0..1) -> OpenGL tangent normal map (Y+ up) as float RGB 0..1. The picture wraps, so the filter wraps too."""
    pad = 8  # OpenCV cannot wrap filters, so pad with the opposite edge and crop
    hh = cv2.GaussianBlur(np.pad(height, pad, mode="wrap"), (0, 0), blur)
    gx = (cv2.Sobel(hh, cv2.CV_32F, 1, 0, ksize=3) / 8.0)[pad:-pad, pad:-pad]
    gy = (cv2.Sobel(hh, cv2.CV_32F, 0, 1, ksize=3) / 8.0)[pad:-pad, pad:-pad]
    nx, ny, nz = -gx * strength, gy * strength, np.ones_like(gx)
    norm = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.dstack([nx / norm, ny / norm, nz / norm]) * 0.5 + 0.5


# ---- painters ------------------------------------------------------------------------------------------------------------
# Each takes (tile, params). params["pal"] holds the palette; names a painter does not use are ignored.

def _pal(p: dict) -> dict:
    """Palette from the JSON: "tones" is a list of colours, every other entry one colour ('#rrggbb')."""
    return {k: ([hexc(c) for c in v] if k == "tones" else hexc(v)) for k, v in p["pal"].items()}


def paint_plates(t: Tile, p: dict) -> None:
    """Steel plates in a grid (floors, wall panels): bevelled plates, ink seams, corner rivets, scratches, optional stripe."""
    pal, u = _pal(p), t.k
    cols, rows = int(p.get("cols", 2)), int(p.get("rows", 2))
    pw, ph = t.px / cols, t.px / rows
    gap = p.get("gap", 0.9) * u
    t.fill(pal["ink"], 90)
    for r in range(rows):
        shift = (pw / 2 if (p.get("stagger") and r % 2) else 0)
        for c in range(cols):
            x0, y0 = c * pw + shift + gap / 2, r * ph + gap / 2
            x1, y1 = x0 + pw - gap, y0 + ph - gap
            base = t.rng.choice(pal["tones"])
            t.bevel_rect(x0, y0, x1, y1, base, mix(base, pal["light"], 0.55), mul(base, 0.62), p.get("bevel", 0.9) * u, None, 0, 150)
            inset = p.get("rivet_inset", 2.2) * u
            if p.get("rivets", True):
                for rx, ry in ((x0 + inset, y0 + inset), (x1 - inset, y0 + inset), (x0 + inset, y1 - inset), (x1 - inset, y1 - inset)):
                    t.ellipse(rx, ry, 0.55 * u, 0.55 * u, mul(base, 0.55), 175, pal["ink"], 0.18 * u)
                    t.ellipse(rx - 0.15 * u, ry - 0.15 * u, 0.2 * u, 0.2 * u, pal["light"])
            for _ in range(int(p.get("scratches", 3))):  # short bright scratches
                sx, sy = t.rng.uniform(x0 + 2 * u, x1 - 6 * u), t.rng.uniform(y0 + 2 * u, y1 - 2 * u)
                ln = t.rng.uniform(1.5, 4.5) * u
                t.line([(sx, sy), (sx + ln, sy - ln * 0.3)], mix(base, pal["light"], 0.45), 0.22 * u, 160)
            if p.get("vent") and (r + c) % 2 == 0:  # three louvre slits
                vx, vy = (x0 + x1) / 2, (y0 + y1) / 2
                for i in range(-1, 2):
                    t.rect(vx - 2.2 * u, vy + i * 1.1 * u - 0.25 * u, vx + 2.2 * u, vy + i * 1.1 * u + 0.25 * u, pal["ink"], 90)
            if p.get("stripe") and r == p["stripe"]:
                t.rect(x0, (y0 + y1) / 2 - 0.9 * u, x1, (y0 + y1) / 2 + 0.9 * u, pal["accent"], 158, pal["ink"], 0.15 * u)
    for _ in range(int(p.get("stains", 0))):  # hard-edged grime patches
        t.blob(t.rng.uniform(0, t.px), t.rng.uniform(0, t.px), t.rng.uniform(1.5, 4) * u, mul(pal["tones"][0], 0.7), None, 0.4)


def paint_bricks(t: Tile, p: dict) -> None:
    pal, u = _pal(p), t.k
    rows, per = int(p.get("rows", 12)), int(p.get("per_row", 6))
    bh, bw = t.px / rows, t.px / per
    mortar = p.get("mortar", 0.55) * u
    t.fill(pal["ink"], 80)
    for r in range(rows):
        shift = bw / 2 if r % 2 else 0
        for c in range(per + 1):
            x0, y0 = c * bw - shift + mortar / 2, r * bh + mortar / 2
            x1, y1 = x0 + bw - mortar, y0 + bh - mortar
            base = t.rng.choice(pal["tones"])
            t.bevel_rect(x0, y0, x1, y1, base, mix(base, pal["light"], 0.5), mul(base, 0.6), 0.6 * u, None, 0, 150)
            if t.rng.random() < p.get("chip", 0.25):  # chipped corner: a dark notch
                t.poly([(x1, y1), (x1 - 1.6 * u, y1), (x1, y1 - 1.2 * u)], pal["ink"], 90)
            if t.rng.random() < p.get("stain", 0.18):
                t.rect(x0 + 0.8 * u, y0 + 0.9 * u, x1 - 0.8 * u, y1 - 0.9 * u, mul(base, 0.78), 150)


def paint_corrugated(t: Tile, p: dict) -> None:
    """Vertical corrugated sheet: each rib is a lit side, a mid face and a dark side (three flat bands), ink valleys, rivets."""
    pal, u = _pal(p), t.k
    ribs = int(p.get("ribs", 8))
    rw = t.px / ribs
    t.fill(pal["base"], 128)
    for i in range(ribs):
        x0 = i * rw
        t.rect(x0, 0, x0 + rw * 0.30, t.px, mix(pal["base"], pal["light"], 0.55), 160)
        t.rect(x0 + rw * 0.30, 0, x0 + rw * 0.70, t.px, pal["base"], 175)
        t.rect(x0 + rw * 0.70, 0, x0 + rw, t.px, mul(pal["base"], 0.62), 120)
        t.rect(x0 + rw - 0.22 * u, 0, x0 + rw + 0.22 * u, t.px, pal["ink"], 60)
    for _ in range(int(p.get("streaks", 6))):  # rain streaks: thin darker bars
        sx, sy = t.rng.uniform(0, t.px), t.rng.uniform(0, t.px)
        t.rect(sx, sy, sx + t.rng.uniform(0.3, 0.8) * u, sy + t.rng.uniform(5, 16) * u, mul(pal["base"], 0.7), None)
    if p.get("rust"):
        for _ in range(int(p["rust"])):
            cx, cy = t.rng.uniform(0, t.px), t.rng.uniform(0, t.px)
            r = t.rng.uniform(1.4, 3.4) * u
            t.blob(cx, cy, r, mul(pal["rust"], 0.78), None, 0.45, ink=None)
            t.blob(cx - 0.3 * u, cy - 0.3 * u, r * 0.62, pal["rust"], None, 0.45)
    for y in (0.08, 0.92):  # rivet rows, one per rib
        for i in range(ribs):
            cx, cy = (i + 0.3) * rw, y * t.px
            t.ellipse(cx, cy, 0.5 * u, 0.5 * u, mix(pal["base"], pal["light"], 0.6), 190, pal["ink"], 0.16 * u)
    t.rect(0, 0, t.px, 0.25 * u, pal["ink"], 70)  # a sheet seam across the tile (also the wrap line)
    t.rect(0, t.px - 0.25 * u, t.px, t.px, pal["ink"], 70)


def paint_slabs(t: Tile, p: dict) -> None:
    """Concrete slabs: flat tone per slab, ink joints with a lit lip, hard-edged stains, cracks, pits."""
    pal, u = _pal(p), t.k
    cols, rows = int(p.get("cols", 2)), int(p.get("rows", 2))
    pw, ph = t.px / cols, t.px / rows
    joint = p.get("joint", 0.7) * u
    t.fill(pal["ink"], 90)
    for r in range(rows):
        shift = pw / 2 if (p.get("stagger") and r % 2) else 0
        for c in range(cols + (1 if shift else 0)):
            x0, y0 = c * pw - shift + joint / 2, r * ph + joint / 2
            base = t.rng.choice(pal["tones"])
            t.bevel_rect(x0, y0, x0 + pw - joint, y0 + ph - joint, base, mix(base, pal["light"], 0.4), mul(base, 0.72), 0.5 * u, None, 0, 140)
    for _ in range(int(p.get("stains", 8))):
        r = t.rng.uniform(2, 7) * u
        t.blob(t.rng.uniform(0, t.px), t.rng.uniform(0, t.px), r, mul(t.rng.choice(pal["tones"]), 0.82), 124, 0.4, squash=t.rng.uniform(0.5, 1.0))
    for _ in range(int(p.get("lit", 5))):  # worn lighter patches
        t.blob(t.rng.uniform(0, t.px), t.rng.uniform(0, t.px), t.rng.uniform(1.5, 4) * u, mix(t.rng.choice(pal["tones"]), pal["light"], 0.25), 134, 0.4)
    for _ in range(int(p.get("cracks", 4))):
        t.crack(t.rng.uniform(0, t.px), t.rng.uniform(0, t.px), t.rng.uniform(8, 18) * u, pal["ink"], 0.28 * u)
    for _ in range(int(p.get("pits", 40))):
        pr = t.rng.uniform(0.2, 0.45) * u
        t.ellipse(t.rng.uniform(0, t.px), t.rng.uniform(0, t.px), pr, pr, mul(pal["tones"][0], 0.55), 100)
    if p.get("marks"):  # painted lane marks across the slabs (hangar floor)
        y = t.px * p.get("marks_y", 0.5)
        t.rect(0, y - 0.7 * u, t.px, y + 0.7 * u, pal["mark"], 150, pal["ink"], 0.15 * u)
        for x in range(0, t.px, int(6 * u)):
            t.poly([(x, y - 0.7 * u), (x + 2.4 * u, y - 0.7 * u), (x + 1.2 * u, y + 0.7 * u), (x - 1.2 * u, y + 0.7 * u)], pal["ink"])


def paint_asphalt(t: Tile, p: dict) -> None:
    """Asphalt: flat base, big hard-edged tone patches, aggregate dots, patched repairs, ink cracks, wet-light streaks."""
    pal, u = _pal(p), t.k
    t.fill(pal["base"], 128)
    for _ in range(int(p.get("patches", 16))):
        t.blob(t.rng.uniform(0, t.px), t.rng.uniform(0, t.px), t.rng.uniform(5, 11) * u, t.rng.choice(pal["tones"]), 130, 0.45, squash=t.rng.uniform(0.5, 1.0))
    for _ in range(int(p.get("repairs", 2))):
        x, y = t.rng.uniform(0, t.px), t.rng.uniform(0, t.px)
        w, h = t.rng.uniform(7, 13) * u, t.rng.uniform(4, 8) * u
        t.rect(x, y, x + w, y + h, mul(pal["base"], 0.82), 140, pal["ink"], 0.28 * u, 70)
        t.rect(x + 0.3 * u, y + 0.3 * u, x + w - 0.3 * u, y + 0.5 * u, mix(pal["base"], pal["light"], 0.25))
    for _ in range(int(p.get("grit", 500))):
        gx, gy = t.rng.uniform(0, t.px), t.rng.uniform(0, t.px)
        gr = t.rng.uniform(0.18, 0.4) * u
        t.ellipse(gx, gy, gr, gr, mix(pal["base"], pal["light"], t.rng.uniform(0.2, 0.55)) if t.rng.random() < 0.6 else mul(pal["base"], 0.7), 134)
    for _ in range(int(p.get("cracks", 4))):
        t.crack(t.rng.uniform(0, t.px), t.rng.uniform(0, t.px), t.rng.uniform(10, 24) * u, pal["ink"], 0.32 * u)
    for _ in range(int(p.get("streaks", 10))):  # wet sheen
        sx, sy = t.rng.uniform(0, t.px), t.rng.uniform(0, t.px)
        ln = t.rng.uniform(3, 9) * u
        t.rect(sx, sy, sx + ln, sy + 0.35 * u, mix(pal["base"], pal["light"], 0.3), 138)


def paint_gravel(t: Tile, p: dict) -> None:
    """Gravel-and-tar roof: tar base, roofing-felt seams, clusters of small lit stones, a few patches."""
    pal, u = _pal(p), t.k
    t.fill(pal["base"], 126)
    seams = int(p.get("seams", 2))
    for i in range(seams):
        x = (i + 0.5) * t.px / seams
        t.rect(x - 0.35 * u, 0, x + 0.35 * u, t.px, pal["ink"], 80)
        t.rect(x + 0.35 * u, 0, x + 0.75 * u, t.px, mix(pal["base"], pal["light"], 0.3), 140)
    for _ in range(int(p.get("patches", 10))):
        t.blob(t.rng.uniform(0, t.px), t.rng.uniform(0, t.px), t.rng.uniform(4, 9) * u, t.rng.choice(pal["tones"]), 130, 0.4, squash=0.7)
    for _ in range(int(p.get("stones", 700))):
        sx, sy = t.rng.uniform(0, t.px), t.rng.uniform(0, t.px)
        r = t.rng.uniform(0.35, 0.8) * u
        stone = t.rng.choice(pal["tones"])
        t.ellipse(sx, sy, r, r * 0.8, mul(stone, 0.55), 150)
        t.ellipse(sx - r * 0.18, sy - r * 0.2, r * 0.7, r * 0.55, mix(stone, pal["light"], 0.35))
    for _ in range(int(p.get("puddles", 2))):
        cx, cy = t.rng.uniform(0, t.px), t.rng.uniform(0, t.px)
        t.blob(cx, cy, t.rng.uniform(3, 6) * u, pal["water"], 118, 0.3, squash=0.45, ink=pal["ink"], ink_w=0.22 * u)
        t.rect(cx - 1.5 * u, cy - 0.25 * u, cx + 0.8 * u, cy, mix(pal["water"], pal["light"], 0.5))


def paint_grating(t: Tile, p: dict) -> None:
    """Open metal grating: dark void showing through, lit bars with hard shading, a heavier frame bar."""
    pal, u = _pal(p), t.k
    n = int(p.get("cells", 8))
    pitch = t.px / n
    bar = p.get("bar", 1.0) * u
    t.fill(pal["void"], 70)
    for i in range(n):
        y = i * pitch
        t.rect(0, y, t.px, y + bar, pal["base"], 170)
        t.rect(0, y, t.px, y + bar * 0.35, mix(pal["base"], pal["light"], 0.55), 190)
        t.rect(0, y + bar * 0.75, t.px, y + bar, mul(pal["base"], 0.6), 150)
    for i in range(n):  # thinner cross bars on top
        x = i * pitch
        t.rect(x, 0, x + bar * 0.6, t.px, mul(pal["base"], 0.85), 160)
        t.rect(x, 0, x + bar * 0.2, t.px, mix(pal["base"], pal["light"], 0.35), 175)
    for i in range(n):  # welded joints
        for j in range(n):
            if (i + j) % 2 == 0:
                t.ellipse(i * pitch + bar * 0.3, j * pitch + bar * 0.5, 0.35 * u, 0.35 * u, pal["light"], 195, pal["ink"], 0.1 * u)
    t.rect(0, 0, t.px, 0.22 * u, pal["ink"], 60)


def paint_glass(t: Tile, p: dict) -> None:
    """Curtain wall: panes with a hard diagonal glare band, ink-and-metal mullions, a darker reflection of the sky."""
    pal, u = _pal(p), t.k
    cols, rows = int(p.get("cols", 4)), int(p.get("rows", 4))
    pw, ph = t.px / cols, t.px / rows
    mull = p.get("mullion", 0.9) * u
    t.fill(pal["ink"], 90)
    for r in range(rows):
        for c in range(cols):
            x0, y0, x1, y1 = c * pw + mull / 2, r * ph + mull / 2, (c + 1) * pw - mull / 2, (r + 1) * ph - mull / 2
            base = t.rng.choice(pal["tones"])
            t.rect(x0, y0, x1, y1, base, 120)
            band = t.rng.uniform(0.15, 0.4)  # glare: a lighter diagonal band, hard-edged
            glare = [(x0 + (x1 - x0) * band, y0), (x0 + (x1 - x0) * (band + 0.2), y0), (x0 + (x1 - x0) * (band - 0.1), y1), (x0 + (x1 - x0) * (band - 0.3), y1)]
            glare = [(min(max(gx, x0), x1), gy) for gx, gy in glare]
            t.poly(glare, mix(base, pal["light"], 0.28), None)
            t.rect(x0, y1 - (y1 - y0) * 0.22, x1, y1, mul(base, 0.72), None)  # darker lower band = reflected street
            t.rect(x0, y0, x1, y0 + 0.35 * u, mix(base, pal["light"], 0.6), 150)
            t.rect(x0, y0, x0 + 0.3 * u, y1, mix(base, pal["light"], 0.45), 140)
    for c in range(cols):  # metal mullion highlight
        t.rect(c * pw - 0.25 * u, 0, c * pw + 0.1 * u, t.px, pal["metal"], 150)
    for r in range(rows):
        t.rect(0, r * ph - 0.25 * u, t.px, r * ph + 0.1 * u, pal["metal"], 150)


def paint_rust(t: Tile, p: dict) -> None:
    """Rusted sheet: paint base, big hard-edged rust patches with a darker rim, bolts, drips and scratches."""
    pal, u = _pal(p), t.k
    t.fill(pal["base"], 128)
    seams = int(p.get("seams", 2))
    for i in range(seams):  # overlapping sheet seams
        y = (i + 0.5) * t.px / seams
        t.rect(0, y - 0.3 * u, t.px, y + 0.3 * u, pal["ink"], 80)
        t.rect(0, y + 0.3 * u, t.px, y + 0.7 * u, mix(pal["base"], pal["light"], 0.35), 150)
    for _ in range(int(p.get("patches", 14))):
        cx, cy = t.rng.uniform(0, t.px), t.rng.uniform(0, t.px)
        r = t.rng.uniform(2.5, 7) * u
        t.blob(cx, cy, r, mul(pal["rust"], 0.7), 122, 0.5, squash=t.rng.uniform(0.6, 1.0))
        t.blob(cx - 0.4 * u, cy - 0.4 * u, r * 0.66, pal["rust"], 118, 0.5)
        t.blob(cx - 0.8 * u, cy - 0.8 * u, r * 0.28, mix(pal["rust"], pal["light"], 0.3), None, 0.4)
    for _ in range(int(p.get("drips", 8))):
        sx, sy = t.rng.uniform(0, t.px), t.rng.uniform(0, t.px)
        t.rect(sx, sy, sx + 0.5 * u, sy + t.rng.uniform(4, 12) * u, mul(pal["rust"], 0.65), None)
    for _ in range(int(p.get("scratches", 8))):
        sx, sy = t.rng.uniform(0, t.px), t.rng.uniform(0, t.px)
        ln = t.rng.uniform(3, 8) * u
        t.line([(sx, sy), (sx + ln, sy + ln * 0.25)], mix(pal["base"], pal["light"], 0.5), 0.25 * u, 150)
    for i in range(4):
        for j in range(4):
            cx, cy = (i + 0.5) * t.px / 4, (j + 0.5) * t.px / 4
            t.ellipse(cx, cy, 0.6 * u, 0.6 * u, mul(pal["base"], 0.6), 185, pal["ink"], 0.18 * u)
            t.ellipse(cx - 0.18 * u, cy - 0.18 * u, 0.22 * u, 0.22 * u, pal["light"])


PAINTERS = {
    "plates": paint_plates, "bricks": paint_bricks, "corrugated": paint_corrugated, "slabs": paint_slabs,
    "asphalt": paint_asphalt, "gravel": paint_gravel, "grating": paint_grating, "glass": paint_glass, "rust": paint_rust,
}


def paint(kind: str, px: int, k: int, seed: int, params: dict) -> Tile:
    if kind not in PAINTERS:
        raise KeyError(f"unknown cel material kind '{kind}' (known: {', '.join(PAINTERS)})")
    t = Tile(px, k, seed)
    PAINTERS[kind](t, params)
    return t
