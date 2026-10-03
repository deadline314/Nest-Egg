"""Cel-shaded surface decoration for facade modules (NE-59, redone for NE-74): pipe runs, AC units, wall cameras, emergency
lamps, balconies, circuit traces, LED rows, hazard stripes and the rooftop beacon.

Everything draws on a cel_facade.Canvas (colour, height and glow at once) in logical units (c.u = pixels per logical px),
with clean ink outlines and hard two-tone shading (light from the upper left). Nothing here is a plain rectangle or arc
only: boxes get cut corners, vents get louvres, lamps are octagons.
Glow elements use pure colours so the in-game window shader (game/level/environment/window_life.gdshader) can pulse them;
pure red (255, 20, 20) is a beacon and blinks, so use it only for beacons and camera LEDs.
"""
from __future__ import annotations

import math
import random

from cel_facade import Canvas
from cel_tile import mix, mul

RED = (255, 20, 20)


def pipe_run(c: Canvas, p: dict, x: float, y0: float = 0.0, y1: float | None = None, width: float = 2.2) -> None:
    """A vertical pipe: lit side, body, shaded side (three flat bands), ink outline, bracket rings with a bolt each."""
    u, H = c.u, c.h
    y1 = H if y1 is None else y1
    w = width * u
    c.reserve(x - 0.5 * u, y0, x + w + 0.5 * u, y1)
    c.rect(x + 0.5 * u, y0, x + w + 0.5 * u, y1, mix(p["base"], p["dark"], 0.85), 118)  # hard drop shade
    c.rect(x, y0, x + w, y1, p["metal"], 160, p["ink"], 0.22 * u, 60)
    c.rect(x + 0.18 * u, y0, x + w * 0.32, y1, p["frame_light"], 180)
    c.rect(x + w * 0.68, y0, x + w - 0.18 * u, y1, mul(p["metal"], 0.6), 130)
    y = y0 + 3.0 * u
    while y < y1 - 1.0 * u:
        c.rect(x - 0.35 * u, y, x + w + 0.35 * u, y + 1.0 * u, p["metal_dark"], 175, p["ink"], 0.18 * u, 70)
        c.rect(x - 0.35 * u, y, x + w + 0.35 * u, y + 0.28 * u, p["frame_light"], 190)
        c.ellipse(x + w / 2, y + 0.5 * u, 0.2 * u, 0.2 * u, p["frame_light"], 195)
        y += 9.0 * u


def ac_unit(c: Canvas, p: dict, x: float, y: float, w: float = 7.0, h: float = 4.5) -> None:
    """Wall-mounted AC condenser: cut-corner box, a fan ring with blades on the left, louvres on the right, bracket and drip."""
    u = c.u
    w, h = w * u, h * u
    c.reserve(x - 0.5 * u, y - 0.3 * u, x + w + 1.0 * u, y + h + 1.8 * u)
    for bx in (x + 0.9 * u, x + w - 1.5 * u):  # brackets
        c.poly([(bx, y + h - 0.2 * u), (bx + 0.6 * u, y + h - 0.2 * u), (bx + 0.6 * u, y + h + 1.6 * u)], p["metal_dark"], 140, p["ink"], 0.15 * u)
    cut = 0.7 * u
    body = Canvas.octagon(x, y, x + w, y + h, cut)
    c.poly([(px + 0.7 * u, py + 0.7 * u) for px, py in body], mix(p["base"], p["dark"], 0.85), 118)
    c.poly(body, p["metal"], 160, p["ink"], 0.25 * u, 70)
    c.rect(x + cut, y + 0.1 * u, x + w - cut, y + 0.5 * u, p["frame_light"], 180)
    c.rect(x + w - 1.1 * u, y + cut, x + w - 0.1 * u, y + h - cut, mul(p["metal"], 0.58), 125)
    fx, fy, fr = x + w * 0.34, y + h / 2, h * 0.36
    c.ellipse(fx, fy, fr, fr, p["ink"], 80)
    c.ellipse(fx, fy, fr * 0.82, fr * 0.82, p["metal_dark"], 130)
    for a in (0.5, 0.5 + math.pi / 2, 0.5 + math.pi, 0.5 + 3 * math.pi / 2):  # fan blades
        c.line([(fx, fy), (fx + math.cos(a) * fr * 0.8, fy + math.sin(a) * fr * 0.8)], p["frame_light"], 0.34 * u, 150)
    c.ellipse(fx, fy, 0.3 * u, 0.3 * u, p["ink"], 80)
    for i in range(3):  # louvres
        ly = y + h * (0.28 + 0.22 * i)
        c.rect(x + w * 0.62, ly, x + w - 1.4 * u, ly + 0.28 * u, p["ink"], 85)
    c.ellipse(x + w - 0.45 * u, y + h * 0.5, 0.16 * u, 0.16 * u, p["accent2"], 175)  # status lamp (unlit, colour only)


def wall_camera(c: Canvas, p: dict, x: float, y: float) -> None:
    """A security camera on an arm; its tiny red LED blinks in-game."""
    u = c.u
    c.reserve(x - 0.5 * u, y - 0.5 * u, x + 5.5 * u, y + 3.5 * u)
    c.rect(x, y, x + 0.9 * u, y + 2.6 * u, p["metal_dark"], 150, p["ink"], 0.15 * u)
    c.line([(x + 0.9 * u, y + 0.7 * u), (x + 2.0 * u, y + 0.7 * u)], p["metal_dark"], 0.5 * u, 150)
    body = [(x + 1.6 * u, y + 0.2 * u), (x + 4.6 * u, y + 0.9 * u), (x + 4.6 * u, y + 2.3 * u), (x + 1.6 * u, y + 2.0 * u)]
    c.poly([(px + 0.4 * u, py + 0.5 * u) for px, py in body], mix(p["base"], p["dark"], 0.85), 118)
    c.poly(body, p["metal"], 160, p["ink"], 0.2 * u, 70)
    c.line([body[0], body[1]], p["frame_light"], 0.28 * u, 175)
    c.poly(Canvas.octagon(x + 4.0 * u, y + 0.9 * u, x + 5.0 * u, y + 2.3 * u, 0.3 * u), p["ink"], 90)
    c.ellipse(x + 2.2 * u, y + 1.7 * u, 0.28 * u, 0.28 * u, RED, 175, glow=RED + (255,))


def emergency_lamp(c: Canvas, p: dict, x: float, y: float, color=(255, 150, 40)) -> None:
    """A caged amber lamp: octagonal lens with cage bars, a bracket plate; the lens glows."""
    u = c.u
    c.reserve(x - 0.5 * u, y - 0.5 * u, x + 3.5 * u, y + 3.5 * u)
    c.rect(x, y + 0.2 * u, x + 3.0 * u, y + 0.9 * u, p["metal_dark"], 150, p["ink"], 0.15 * u)
    lens = Canvas.octagon(x + 0.2 * u, y + 0.9 * u, x + 2.8 * u, y + 3.0 * u, 0.7 * u)
    c.poly(lens, mix(color, p["ink"], 0.45), 165, p["ink"], 0.2 * u, 70, glow=color + (235,))
    for i in (1, 2):
        c.line([(x + 0.2 * u + i * 0.87 * u, y + 0.9 * u), (x + 0.2 * u + i * 0.87 * u, y + 3.0 * u)], p["ink"], 0.2 * u, 100, glow=(0, 0, 0, 0))


def balcony(c: Canvas, p: dict, x0: float, x1: float, y: float) -> None:
    """Railing: ink top rail with a lit lip, bars with cut ends, a heavy base slab."""
    u = c.u
    h = 2.6 * u
    c.reserve(x0, y, x1, y + h)
    c.rect(x0 + 0.5 * u, y + 0.5 * u, x1 + 0.5 * u, y + h + 0.5 * u, mix(p["base"], p["dark"], 0.85), 118)
    n = max(3, int((x1 - x0) / (1.1 * u)))
    for i in range(n + 1):
        bx = x0 + (x1 - x0) * i / n
        c.line([(bx, y + 0.5 * u), (bx, y + h - 0.4 * u)], p["ink"], 0.3 * u, 100)
    c.rect(x0 - 0.3 * u, y, x1 + 0.3 * u, y + 0.7 * u, p["frame"], 160, p["ink"], 0.2 * u, 70)
    c.rect(x0 - 0.3 * u, y, x1 + 0.3 * u, y + 0.22 * u, p["frame_light"], 180)
    c.rect(x0 - 0.5 * u, y + h - 0.7 * u, x1 + 0.5 * u, y + h, p["frame"], 160, p["ink"], 0.2 * u, 70)
    c.rect(x0 - 0.5 * u, y + h - 0.7 * u, x1 + 0.5 * u, y + h - 0.45 * u, p["frame_light"], 175)


def hazard_band(c: Canvas, p: dict, y0: float, y1: float) -> None:
    """Yellow / ink warning stripes with an ink outline."""
    u, W = c.u, c.w
    top, bot = y0, y1
    c.rect(0, top, W, bot, p["accent"], 150, p["ink"], 0.2 * u, 70)
    step = 2.4 * u
    with c.clip([(0, top), (W, top), (W, bot), (0, bot)]):
        x = -(bot - top)
        while x < W + (bot - top):
            c.poly([(x, bot), (x + step / 2, bot), (x + step / 2 + (bot - top), top), (x + (bot - top), top)], p["ink"], None)
            x += step


def circuit_traces(c: Canvas, p: dict, rng: random.Random, colors: list, count: int = 4) -> None:
    """Angular wiring (90 and 45 degree turns): an ink channel with a coloured core, ending in a node dot. Avoids windows."""
    u, W, H = c.u, c.w, c.h
    for _ in range(count):
        for _try in range(24):
            x, y = rng.uniform(0.06, 0.94) * W, rng.uniform(0.15, 0.85) * H
            pts = [(x, y)]
            dx, dy = rng.choice([(1, 0), (-1, 0), (0, 1), (0, -1)])
            ok = True
            for _step in range(rng.randint(3, 5)):
                seg = rng.uniform(3, 8) * u
                nx, ny = min(max(x + dx * seg, 2 * u), W - 2 * u), min(max(y + dy * seg, 2 * u), H - 3 * u)
                if not c.is_free(min(x, nx) - 0.4 * u, min(y, ny) - 0.4 * u, max(x, nx) + 0.4 * u, max(y, ny) + 0.4 * u):
                    ok = False
                    break
                x, y = nx, ny
                pts.append((x, y))
                turn = rng.choice([(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1), (1, -1), (-1, -1)])
                if turn != (-dx, -dy):
                    dx, dy = turn
            if ok and len(pts) >= 3:
                break
        else:
            continue
        col = tuple(int(255 * v) for v in rng.choice(colors))
        c.line(pts, p["ink"], 0.85 * u, 70)
        c.line(pts, mix(p["metal_dark"], col, 0.28), 0.4 * u, 105, glow=col + (200,), glow_w=0.28 * u)
        ex, ey = pts[-1]
        r = 0.7 * u
        c.poly(Canvas.octagon(ex - r, ey - r, ex + r, ey + r, r * 0.4), col, 165, p["ink"], 0.15 * u, glow=col + (255,))
        c.reserve(min(q[0] for q in pts) - 0.5 * u, min(q[1] for q in pts) - 0.5 * u, max(q[0] for q in pts) + 0.5 * u, max(q[1] for q in pts) + 0.5 * u)


def led_row(c: Canvas, p: dict, rng: random.Random, colors: list, y: float | None = None, count: int | None = None) -> None:
    """A strip of indicator lights on a small dark plate (octagon LEDs; some are off)."""
    u, W, H = c.u, c.w, c.h
    count = count or rng.randint(4, 7)
    gap = rng.uniform(1.9, 2.5) * u
    width = gap * (count - 1) + 3.0 * u
    for _try in range(24):
        yy = (y if y is not None else rng.uniform(0.2, 0.75) * H)
        x0 = rng.uniform(0.06, 0.94) * W - width / 2
        x0 = min(max(x0, 1.0 * u), W - width - 1.0 * u)
        if c.is_free(x0, yy - 1.4 * u, x0 + width, yy + 1.4 * u):
            break
    else:
        return
    c.reserve(x0, yy - 1.4 * u, x0 + width, yy + 1.4 * u)
    c.poly(Canvas.octagon(x0, yy - 1.2 * u, x0 + width, yy + 1.2 * u, 0.6 * u), p["metal_dark"], 150, p["ink"], 0.2 * u, 70)
    for i in range(count):
        cx = x0 + 1.5 * u + i * gap
        on = rng.random() < 0.7
        col = tuple(int(255 * v) for v in rng.choice(colors)) if on else mul(p["metal"], 0.8)
        r = 0.5 * u
        c.poly(Canvas.octagon(cx - r, yy - r, cx + r, yy + r, r * 0.4), col, 175, None, 0, None, glow=(col + (230,)) if on else None)


def beacon(c: Canvas, p: dict, x: float, y: float) -> None:
    """Rooftop beacon: pure red, so the window shader blinks it."""
    u = c.u
    c.poly(Canvas.octagon(x - 0.9 * u, y - 0.9 * u, x + 0.9 * u, y + 0.9 * u, 0.35 * u), (255, 70, 70), 175, p["ink"], 0.15 * u, glow=RED + (255,))
