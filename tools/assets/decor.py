"""Surface decoration for generated and kit facade modules (NE-59): circuit traces, LED rows, hazard stripes, pipe runs and
mounted props. Everything is drawn on three RGBA PIL images of the same size: colour, normal and glow.

Why: a bare window grid on a wall reads as a placeholder. Facades get the clutter of a real, lived-in cyberpunk wall
(wiring, indicator lights, pipes, AC units) and none of it is a plain rectangle or a plain arc.
Glow elements use pure-ish colours so the in-game window shader (game/level/environment/window_life.gdshader) can
pulse them; red dots are rooftop-style beacons and blink.
"""
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

PROPS = Path(__file__).resolve().parents[2] / "art" / "environment" / "props"


def _line(draw_c, draw_n, draw_g, pts, k, color, glow_color=None, width=1.0):
    w = max(1, int(width * k * 0.5))
    draw_c.line(pts, fill=color, width=w, joint="curve")
    draw_n.line(pts, fill=(128, 128, 235, 255), width=w, joint="curve")
    if glow_color is not None:
        draw_g.line(pts, fill=glow_color, width=max(1, w - 1), joint="curve")


def circuit_traces(c, n, g, size, k, rng, colors, count=4, free=None):
    """Angular wiring: random walks with 90 / 45 degree turns, ending in a node dot (dots pulse in-game)."""
    dc, dn, dg = ImageDraw.Draw(c), ImageDraw.Draw(n), ImageDraw.Draw(g)
    w, h = size
    for _ in range(count):
        x, y = rng.uniform(0.05, 0.95) * w, rng.uniform(0.15, 0.85) * h
        pts = [(x, y)]
        dx, dy = rng.choice([(1, 0), (-1, 0), (0, 1), (0, -1)])
        for _step in range(rng.randint(3, 6)):
            seg = rng.uniform(4, 11) * k
            x, y = min(max(x + dx * seg, 2), w - 2), min(max(y + dy * seg, 2), h - 2)
            pts.append((x, y))
            turn = rng.choice([(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)])
            if turn != (-dx, -dy):
                dx, dy = turn
        col = tuple(int(v * 255) for v in rng.choice(colors))
        _line(dc, dn, dg, pts, k, (int(col[0] * 0.22), int(col[1] * 0.22), int(col[2] * 0.22), 255), col + (200,), 1.0)
        r = max(2, int(k * 0.9))
        ex, ey = pts[-1]
        dc.ellipse((ex - r, ey - r, ex + r, ey + r), fill=col + (255,))
        dg.ellipse((ex - r, ey - r, ex + r, ey + r), fill=col + (255,))


def led_row(c, n, g, size, k, rng, colors, y_frac=None, count=None):
    """A row of small indicator lights along a panel edge."""
    dc, dn, dg = ImageDraw.Draw(c), ImageDraw.Draw(n), ImageDraw.Draw(g)
    w, h = size
    y = int((y_frac if y_frac is not None else rng.uniform(0.2, 0.8)) * h)
    count = count or rng.randint(4, 8)
    x0 = rng.uniform(0.06, 0.4) * w
    gap = rng.uniform(3.0, 4.5) * k
    r = max(1, int(k * 0.55))
    for i in range(count):
        x = x0 + i * gap
        if x > w - 4:
            break
        col = tuple(int(v * 255) for v in rng.choice(colors)) if rng.random() < 0.7 else (60, 62, 70)
        dc.ellipse((x - r, y - r, x + r, y + r), fill=col + (255,))
        dn.ellipse((x - r, y - r, x + r, y + r), fill=(128, 128, 255, 255))
        if col != (60, 62, 70):
            dg.ellipse((x - r, y - r, x + r, y + r), fill=col + (230,))


def hazard_band(c, n, size, k, y_frac=0.9, band=2.4):
    """Diagonal yellow/black warning stripes near the base of a module."""
    w, h = size
    top, bottom = int((y_frac) * h), int(min(h, y_frac * h + band * k))
    d = ImageDraw.Draw(c)
    step = int(3.2 * k)
    for x in range(-bottom, w + bottom, step):
        d.polygon([(x, bottom), (x + step // 2, bottom), (x + step // 2 + (bottom - top), top), (x + (bottom - top), top)], fill=(120, 96, 22, 255))
    ImageDraw.Draw(n).rectangle((0, top, w, bottom), fill=(128, 128, 250, 255))


def pipe_run(c, n, size, k, rng, x_frac=None):
    """A vertical pipe with bracket rings: cylinder shading in the colour map, round normals across its width."""
    w, h = size
    pw = max(4, int(rng.uniform(2.2, 3.4) * k))
    x = int((x_frac if x_frac is not None else rng.choice([0.05, 0.93, rng.uniform(0.2, 0.8)])) * w)
    dc, dn = ImageDraw.Draw(c), ImageDraw.Draw(n)
    for i in range(pw):
        t = (i + 0.5) / pw
        shade = 0.4 + 0.6 * (1 - abs(t - 0.38) * 1.9)
        col = tuple(int(v * max(0.0, min(1.0, shade))) for v in (96, 108, 118)) + (255,)
        nx = int(255 * (0.5 + 0.5 * (t - 0.5) * 1.8))
        dc.line((x + i, 0, x + i, h), fill=col)
        dn.line((x + i, 0, x + i, h), fill=(nx, 128, 215, 255))
    for yy in range(int(h * 0.12), h, int(h * rng.uniform(0.28, 0.4))):
        dc.rectangle((x - 2, yy, x + pw + 2, yy + max(2, int(k * 0.8))), fill=(44, 48, 56, 255))
        dn.rectangle((x - 2, yy, x + pw + 2, yy + max(2, int(k * 0.8))), fill=(128, 150, 225, 255))


def paste_props(c, n, g, size, k, rng, props, glow_alpha, tone=0.6):
    """Mount already-built props (AC units, cameras, emergency lights) on free wall space: not over a lit window."""
    w, h = size
    for spec in props:
        if rng.random() > float(spec.get("chance", 0.4)):
            continue
        art = PROPS / f"{spec['prop']}.png"
        if not art.exists():
            continue
        tex = Image.open(art).convert("RGBA")
        th = int(float(spec.get("height_frac", 0.4)) * h)
        tw = max(2, int(tex.width * th / tex.height))
        tex = tex.resize((tw, max(2, th)), Image.LANCZOS)
        nrm_path = PROPS / f"{spec['prop']}_n.png"
        nrm = Image.open(nrm_path).convert("RGBA").resize(tex.size, Image.LANCZOS) if nrm_path.exists() else None
        for _try in range(14):
            x = rng.randint(0, max(0, w - tw))
            y = int(h * float(spec.get("y_frac", 0.55))) + rng.randint(-int(h * 0.08), int(h * 0.08))
            y = min(max(0, y), h - th)
            if glow_alpha is not None and glow_alpha[y:y + th, x:x + tw].max() > 8:
                continue
            dark = tex.copy()
            arr = np.asarray(dark).astype(np.float32)
            arr[..., :3] *= tone
            dark = Image.fromarray(arr.astype(np.uint8), "RGBA")
            c.alpha_composite(dark, (x, y))
            if nrm is not None:
                n.alpha_composite(nrm, (x, y))
            break


def beacon(g, x, y, k, color=(255, 20, 20)):
    """A rooftop beacon (pure red: the in-game shader blinks these)."""
    r = max(2, int(k * 0.8))
    ImageDraw.Draw(g).ellipse((x - r, y - r, x + r, y + r), fill=color + (255,))
