"""Procedural cel-shaded sky painter (NE-111).

Paints one seamless sky strip with flat colour bands, flat-coloured clouds with a hard second shade colour and an
optional bright rim, stars / sun / moon and a stepped horizon glow. Nothing is random per run: the seed lives in the
sky's "cel" block of assets_src/pipeline/backdrop.json, so a rebuild gives the same picture.

Everything that wraps horizontally (cloud puffs, bank rows, stars, band waves) is drawn at +-width offsets or built
from whole-number sine cycles, so the left and right edges meet without a seam.

  render(cel, width, height) -> uint8 RGB array (height x width x 3); alpha / WebP output stays in process_sky.py

"cel" block (all lengths in final pixels, y values are fractions of the height, 0 = top, 1 = bottom):
  seed, supersample (default 2)
  palette  [hex, ...]  top to bottom colour stops; bands = number of hard-edged steps; wave = band edge wobble in px
  orbs     [{x, y, r, color, dark?, crescent?[dx, dy], halo?[[radius multiple, alpha], ...], halo_color?}]
  stars    {count, y[min, max], color, size[min, max], sparkle}
  layers   far to near; each {type, ...}:
             cumulus  count, y[min, max] (flat base), width[], height[], puffs[], base, shade, rim?, alpha?, belly?
             stratus  count, y[min, max], width[], height[], base, shade, rim?, alpha?
             bank     y (top of the mass), radius[min, max], rows, base, shade, rim?, deep? (colour of the lowest row)
           common: light [lx, ly] (default [0.6, 1.0]: shade falls to the lower right), shade_depth (0..1 of the
           puff size, default 0.3), rim_width (px, 0 = none)
  horizon_glow  {color, strength, falloff, steps, sway?}  additive, quantised to `steps` flat levels
"""
from __future__ import annotations

import math
import random

import cv2
import numpy as np

Color = tuple[int, int, int]


def hexc(c) -> Color:
    if isinstance(c, str):
        c = c.lstrip("#")
        return int(c[0:2], 16), int(c[2:4], 16), int(c[4:6], 16)
    return int(c[0]), int(c[1]), int(c[2])


def mix(a: Color, b: Color, t: float) -> Color:
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))  # type: ignore[return-value]


def _periodic_wave(rng: random.Random, n: int, width: int, cycles=(1, 2, 3, 5, 8)) -> np.ndarray:
    """Sum of sines with whole-number cycles over `width`, so the curve joins itself at the wrap. Range about -1..1."""
    x = np.arange(n, dtype=np.float32) * (2.0 * math.pi / width)
    out = np.zeros(n, dtype=np.float32)
    weights = 0.0
    for k in cycles:
        w = 1.0 / k
        out += w * np.sin(x * k + rng.uniform(0.0, 2.0 * math.pi))
        weights += w
    return out / weights * 1.6


class _Cloud:
    """A local colour buffer (loc) plus the mask of painted pixels (um), composited onto the sky afterwards."""

    def __init__(self, w: int, h: int):
        self.loc = np.zeros((h, w, 3), dtype=np.uint8)
        self.um = np.zeros((h, w), dtype=bool)

    def paint(self, full: np.ndarray, ox: int, oy: int, cols, light, depth: float, rim_w: int, belly_y: int | None = None):
        """Stamp `full` (bool ROI mask whose top-left sits at ox, oy): shade colour everywhere, base colour where the
        neighbour toward the light is also inside the shape, rim colour on the lit edge."""
        base, shade, rim = cols
        h, w = full.shape
        lh, lw = self.um.shape
        sx, sy = int(round(light[0] * depth)), int(round(light[1] * depth))
        lit = full & np.roll(full, (-sy, -sx), (0, 1))
        if belly_y is not None:
            lit[belly_y:, :] = False
        rimm = None
        if rim is not None and rim_w > 0:
            rimm = full & lit & ~np.roll(full, (int(round(rim_w * light[1])), int(round(rim_w * light[0]))), (0, 1))
        y0, y1 = max(oy, 0), min(oy + h, lh)
        x0, x1 = max(ox, 0), min(ox + w, lw)
        if y0 >= y1 or x0 >= x1:
            return
        sl = (slice(y0 - oy, y1 - oy), slice(x0 - ox, x1 - ox))
        dst = (slice(y0, y1), slice(x0, x1))
        f, l = full[sl], lit[sl]
        self.loc[dst][f] = shade
        self.loc[dst][l] = base
        if rimm is not None:
            self.loc[dst][rimm[sl]] = rim
        self.um[dst] |= f


def _disc_mask(r: int, margin: int) -> np.ndarray:
    n = 2 * (r + margin) + 1
    m = np.zeros((n, n), dtype=np.uint8)
    cv2.circle(m, (r + margin, r + margin), r, 255, -1)
    return m > 0


class SkyPainter:
    def __init__(self, cel: dict, width: int, height: int):
        self.cel = cel
        self.ss = int(cel.get("supersample", 2))
        self.fw, self.fh = width, height
        self.W, self.H = width * self.ss, height * self.ss
        self.rng = random.Random(int(cel.get("seed", 1)))
        self.canvas = np.zeros((self.H, self.W, 3), dtype=np.uint8)

    # ---- helpers ------------------------------------------------------------------------------------------------
    def _rand(self, span, default=(1, 1)) -> float:
        lo, hi = span if span is not None else default
        return self.rng.uniform(lo, hi)

    def _composite(self, cloud: _Cloud, x0: int, y0: int, alpha: float) -> None:
        h, w = cloud.um.shape
        ya, yb = max(y0, 0), min(y0 + h, self.H)
        if ya >= yb:
            return
        dest = (x0 + np.arange(w)) % self.W
        m = cloud.um[ya - y0:yb - y0]
        src = cloud.loc[ya - y0:yb - y0]
        cur = self.canvas[ya:yb][:, dest]
        if alpha < 1.0:
            blended = (cur.astype(np.float32) * (1.0 - alpha) + src.astype(np.float32) * alpha).astype(np.uint8)
        else:
            blended = src
        self.canvas[ya:yb, dest] = np.where(m[..., None], blended, cur)

    # ---- sky colour bands ---------------------------------------------------------------------------------------
    def paint_bands(self) -> None:
        pal = [hexc(c) for c in self.cel["palette"]]
        bands = int(self.cel.get("bands", 6))
        wave = float(self.cel.get("wave", 0.0)) * self.ss
        centers = (np.arange(bands) + 0.5) / bands
        stops = np.linspace(0.0, 1.0, len(pal))
        lut = np.stack([np.interp(centers, stops, [c[i] for c in pal]) for i in range(3)], axis=1)
        lut = np.round(lut).astype(np.uint8)
        y = (np.arange(self.H, dtype=np.float32) + 0.5)[:, None]
        if wave > 0.0:
            off = _periodic_wave(self.rng, self.W, self.W, (2, 3, 5)) * wave
            t = (y + off[None, :]) / self.H
        else:
            t = np.broadcast_to(y / self.H, (self.H, self.W))
        idx = np.clip((t * bands).astype(np.int16), 0, bands - 1)
        self.canvas[:] = lut[idx]

    # ---- stars and orbs -----------------------------------------------------------------------------------------
    def paint_stars(self) -> None:
        s = self.cel.get("stars")
        if not s:
            return
        col = hexc(s["color"])
        ymin, ymax = s.get("y", [0.1, 0.7])
        for _ in range(int(s["count"])):
            x = self.rng.uniform(0, self.W)
            y = self.rng.uniform(ymin, ymax) * self.H
            r = max(1, int(round(self._rand(s.get("size"), (1.0, 2.0)) * self.ss)))
            sparkle = self.rng.random() < float(s.get("sparkle", 0.0))
            for ox in (-self.W, 0, self.W):
                cx = int(x + ox)
                if cx < -4 * r or cx > self.W + 4 * r:
                    continue
                cv2.circle(self.canvas, (cx, int(y)), r, col, -1)
                if sparkle:
                    for dx, dy in ((1, 0), (0, 1)):
                        cv2.line(self.canvas, (cx - dx * r * 4, int(y) - dy * r * 4), (cx + dx * r * 4, int(y) + dy * r * 4), col, max(1, r // 2))

    def _blend_disc(self, cx: float, cy: float, r: int, col: Color, alpha: float, cut=None) -> None:
        """Alpha-blend a flat disc (optionally minus a second disc `cut` = (dx, dy, r)), wrapped horizontally."""
        m = r + 1
        shape = _disc_mask(r, 1)
        if cut is not None:
            dx, dy, cr = cut
            n = shape.shape[0]
            c = np.zeros((n, n), dtype=np.uint8)
            cv2.circle(c, (m + int(dx), m + int(dy)), cr, 255, -1)
            shape = shape & ~(c > 0)
        for ox in (-self.W, 0, self.W):
            x0, y0 = int(cx + ox) - m, int(cy) - m
            ya, yb = max(y0, 0), min(y0 + shape.shape[0], self.H)
            xa, xb = max(x0, 0), min(x0 + shape.shape[1], self.W)
            if ya >= yb or xa >= xb:
                continue
            sub = shape[ya - y0:yb - y0, xa - x0:xb - x0]
            roi = self.canvas[ya:yb, xa:xb]
            roi[sub] = (roi[sub].astype(np.float32) * (1 - alpha) + np.array(col, dtype=np.float32) * alpha).astype(np.uint8)

    def paint_orbs(self) -> None:
        for o in self.cel.get("orbs", []):
            cx, cy, r = o["x"] * self.W, o["y"] * self.H, int(o["r"] * self.ss)
            hcol = hexc(o.get("halo_color", o["color"]))
            for mult, alpha in sorted(o.get("halo", []), reverse=True):
                self._blend_disc(cx, cy, int(r * mult), hcol, alpha)
            if "dark" in o:
                self._blend_disc(cx, cy, r, hexc(o["dark"]), 1.0)
            cut = None
            if "crescent" in o:
                cut = (o["crescent"][0] * r, o["crescent"][1] * r, r)
            self._blend_disc(cx, cy, r, hexc(o["color"]), float(o.get("alpha", 1.0)), cut)

    # ---- clouds -------------------------------------------------------------------------------------------------
    def _common(self, layer: dict):
        cols = (hexc(layer["base"]), hexc(layer["shade"]), hexc(layer["rim"]) if layer.get("rim") else None)
        light = layer.get("light", [0.6, 1.0])
        return cols, light, float(layer.get("shade_depth", 0.3)), int(layer.get("rim_width", 0)) * self.ss

    def paint_cumulus(self, layer: dict) -> None:
        ss = self.ss
        cols, light, depth, rim_w = self._common(layer)
        alpha = float(layer.get("alpha", 1.0))
        for _ in range(int(layer["count"])):
            w = self._rand(layer["width"]) * ss
            h = self._rand(layer["height"]) * ss
            cx = self.rng.uniform(0, self.W)
            base_y = self._rand(layer["y"]) * self.H
            n = int(round(self._rand(layer.get("puffs"), (5, 8))))
            margin = int(h * 0.4) + 8
            lw, lh = int(w + 2 * margin), int(h + 2 * margin)
            cloud = _Cloud(lw, lh)
            ox0, oy0 = int(cx - lw / 2), int(base_y - h - margin)
            base_local = int(h + margin)  # y of the flat base inside the local buffer
            puffs = []
            for i in range(n):
                u = -1.0 + 2.0 * i / max(1, n - 1) + self.rng.uniform(-0.08, 0.08)
                env = max(0.0, 1.0 - abs(u) ** 1.7)
                r = h * (0.28 + 0.5 * env) * self.rng.uniform(0.82, 1.1)
                puffs.append((u * w * 0.5 * 0.82, r))
            puffs.sort(key=lambda p: -p[1])  # big first, small ones sit in front and add the folds
            fold = float(layer.get("fold_depth", 0.12))
            for px, r in puffs:
                r = int(max(6, r))
                cy = base_local - int(r * self.rng.uniform(0.55, 0.8))
                cxl = int(lw / 2 + px)
                m = max(4, int(r * fold) + 4)
                disc = _disc_mask(r, m)
                disc[(base_local - cy + r + m + 1):, :] = False  # flat base: cut everything below it
                cloud.paint(disc, cxl - r - m, cy - r - m, cols, light, max(2, r * fold), rim_w)
            # one big hard shade over the whole silhouette: the lower right edge and the flat underside
            um = cloud.um
            d = max(3, h * depth)
            sx, sy = int(round(light[0] * d)), int(round(light[1] * d))
            under = um & ~np.roll(um, (-sy, -sx), (0, 1))
            cloud.loc[under] = cols[1]
            belly = float(layer.get("belly", 0.0))
            if belly > 0.0:
                low = um.copy()
                low[:int(base_local - h * belly), :] = False
                cloud.loc[low] = cols[1]
            self._composite(cloud, ox0, oy0, alpha)

    def paint_stratus(self, layer: dict) -> None:
        ss = self.ss
        cols, light, depth, rim_w = self._common(layer)
        alpha = float(layer.get("alpha", 1.0))
        for _ in range(int(layer["count"])):
            w = self._rand(layer["width"]) * ss
            h = self._rand(layer["height"]) * ss
            cx = self.rng.uniform(0, self.W)
            cy = self._rand(layer["y"]) * self.H
            margin = int(h * 0.5) + 8
            lw, lh = int(w + 2 * margin), int(h + 2 * margin)
            cloud = _Cloud(lw, lh)
            # lumpy lens: top edge made of a few bumps, bottom edge flatter
            n = 48
            us = np.linspace(-1.0, 1.0, n)
            bumps = _periodic_wave(self.rng, n, n, (3, 4, 6))
            taper = np.clip(1.0 - np.abs(us) ** 2.2, 0.0, 1.0) ** 0.7
            top = -(h * 0.5) * taper * (0.75 + 0.25 * bumps)
            bot = (h * 0.28) * taper
            xs = lw / 2 + us * w / 2
            pts = np.concatenate([np.stack([xs, lh / 2 + top], 1), np.stack([xs[::-1], lh / 2 + bot[::-1]], 1)])
            m = np.zeros((lh, lw), dtype=np.uint8)
            cv2.fillPoly(m, [np.round(pts).astype(np.int32)], 255)
            # a second, smaller lens stacked on top gives the streak a second step
            if self.rng.random() < 0.7:
                w2 = w * self.rng.uniform(0.35, 0.6)
                xo = self.rng.uniform(-0.25, 0.25) * w
                us2 = np.linspace(-1.0, 1.0, 32)
                t2 = np.clip(1.0 - np.abs(us2) ** 2.0, 0.0, 1.0) ** 0.7
                xs2 = lw / 2 + xo + us2 * w2 / 2
                pts2 = np.concatenate([np.stack([xs2, lh / 2 + top.min() * 0.8 * t2 + 2], 1), np.stack([xs2[::-1], lh / 2 + bot.max() * 0.1 + np.zeros(32)], 1)])
                cv2.fillPoly(m, [np.round(pts2).astype(np.int32)], 255)
            full = m > 0
            cloud.paint(full, 0, 0, cols, light, max(2, h * depth), rim_w)
            self._composite(cloud, int(cx - lw / 2), int(cy - lh / 2), alpha)

    def paint_bank(self, layer: dict) -> None:
        """A heavy cloud mass across the whole width: rows of overlapping puffs that darken toward the bottom."""
        ss = self.ss
        cols, light, depth, rim_w = self._common(layer)
        alpha = float(layer.get("alpha", 1.0))
        rmin, rmax = layer["radius"]
        rows = int(layer.get("rows", 3))
        top_y = float(layer["y"]) * self.H
        deep = hexc(layer["deep"]) if layer.get("deep") else cols[1]
        cloud = _Cloud(self.W, self.H)
        # the top row follows a slow periodic skyline so the mass has valleys and towers
        skyline = _periodic_wave(self.rng, self.W, self.W, (2, 3, 4, 7)) * float(layer.get("relief", 0.15)) * self.H
        for row in range(rows):
            t = row / max(1, rows - 1)
            base = mix(cols[0], deep, t * float(layer.get("darken", 1.0)))
            shade = mix(cols[1], deep, t * float(layer.get("darken", 1.0)))
            rim = cols[2] if row == 0 else None
            x = self.rng.uniform(0, rmin * ss)
            row_y = top_y + row * rmin * ss * 0.9
            while x < self.W:
                r = int(self.rng.uniform(rmin, rmax) * ss)
                cy = int(row_y + skyline[int(x) % self.W] * (1.0 - 0.5 * t) + self.rng.uniform(-0.15, 0.15) * r)
                m = max(4, int(r * depth) + 4)
                disc = _disc_mask(r, m)
                for ox in (-self.W, 0, self.W):
                    px = int(x) + ox - r - m
                    if px + disc.shape[1] < 0 or px > self.W:
                        continue
                    cloud.paint(disc, px, cy - r - m, (base, shade, rim), light, max(2, r * depth), rim_w)
                x += r * self.rng.uniform(0.9, 1.3)
        # the mass is solid downward: every column is filled below its first painted pixel, so no valley shows sky
        filled = np.logical_or.accumulate(cloud.um, axis=0)
        cloud.loc[filled & ~cloud.um] = deep
        cloud.um = filled
        self._composite(cloud, 0, 0, alpha)

    def paint_layers(self) -> None:
        for layer in self.cel.get("layers", []):
            kind = layer["type"]
            if kind == "cumulus":
                self.paint_cumulus(layer)
            elif kind == "stratus":
                self.paint_stratus(layer)
            elif kind == "bank":
                self.paint_bank(layer)
            else:
                raise ValueError(f"unknown cloud layer type '{kind}'")

    # ---- output -------------------------------------------------------------------------------------------------
    def finish(self) -> np.ndarray:
        rgb = cv2.resize(self.canvas, (self.fw, self.fh), interpolation=cv2.INTER_AREA) if self.ss > 1 else self.canvas
        glow = self.cel.get("horizon_glow")
        if glow:
            a = rgb.astype(np.float32)
            t = np.linspace(0.0, 1.0, self.fh, dtype=np.float32)[:, None]  # 1 at the bottom (horizon)
            weight = np.broadcast_to(t ** float(glow.get("falloff", 2.0)), (self.fh, self.fw)).copy()
            sway = float(glow.get("sway", 0.0))
            if sway > 0.0:
                weight *= 1.0 + sway * _periodic_wave(self.rng, self.fw, self.fw, (2, 3, 5))[None, :]
            steps = int(glow.get("steps", 4))
            q = np.floor(np.clip(weight, 0.0, 1.0) * steps) / steps * float(glow.get("strength", 0.3))
            a += q[..., None] * np.array(glow["color"], dtype=np.float32) * 255.0
            rgb = np.clip(a + 0.5, 0, 255).astype(np.uint8)
        return rgb


def render(cel: dict, width: int, height: int) -> np.ndarray:
    p = SkyPainter(cel, width, height)
    p.paint_bands()
    p.paint_stars()
    p.paint_orbs()
    p.paint_layers()
    return p.finish()
