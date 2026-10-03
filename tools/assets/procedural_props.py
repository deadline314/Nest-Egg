"""Procedural ground decals that a generative model cannot draw well (NE-62 / NE-63): rain puddles and floor markings.

Usage: python tools/assets/procedural_props.py

Writes art/environment/props/{puddle,floor_marking}{,_n,_glow}.png and patches the prop data (has_glow, ripple).
Seeds are fixed, so a rerun gives identical pictures. The puddle's glow layer carries the neon reflections and a faint alpha
over the whole water surface; puddle_ripple.gdshader draws the raindrop rings inside that alpha at runtime.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
from build_props import DATA, OUT, set_field  # noqa: E402
import qwen_matte as qm  # noqa: E402

SCALE = 8


def fbm(h: int, w: int, rng: np.random.Generator, octaves=4, base=6) -> np.ndarray:
    out = np.zeros((h, w), np.float32)
    amp, total = 1.0, 0.0
    for o in range(octaves):
        n = rng.random((max(2, base * 2**o // 4 + 2), base * 2**o + 2)).astype(np.float32)
        out += cv2.resize(n, (w, h), interpolation=cv2.INTER_CUBIC) * amp
        total += amp
        amp *= 0.5
    return out / total


def puddle() -> None:
    rng = np.random.default_rng(7)
    w, h = 40 * SCALE, 4 * SCALE
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    # irregular ellipse
    nx, ny = (xx - w / 2) / (w / 2), (yy - h / 2) / (h / 2)
    wobble = 0.12 * (fbm(h, w, rng, 3, 5) - 0.5) * 2
    dist = np.sqrt(nx**2 + ny**2) + wobble
    alpha = np.clip((1.0 - dist) / 0.22, 0.0, 1.0)
    alpha = cv2.GaussianBlur(alpha, (0, 0), 1.2)
    # dark water, a bit lighter towards the far (upper) edge where it mirrors the sky
    sky = np.clip(0.5 - ny * 0.5, 0, 1)
    rgb = np.dstack([0.035 + 0.05 * sky, 0.05 + 0.07 * sky, 0.085 + 0.12 * sky]).astype(np.float32)
    rgb += (fbm(h, w, rng, 4, 14)[..., None] - 0.5) * 0.04
    rim = np.clip(1.0 - np.abs(dist - 0.88) / 0.1, 0, 1)[..., None] * np.array([0.1, 0.13, 0.17], np.float32)
    rgb = np.clip(rgb + rim * 0.7, 0, 1)
    color = np.dstack([rgb, alpha * 0.92])
    qm.to_image(color).save(OUT / "puddle.png", optimize=True)
    flat = np.dstack([np.full((h, w), 0.5), np.full((h, w), 0.5), np.ones((h, w)), alpha]).astype(np.float32)
    qm.to_image(flat).save(OUT / "puddle_n.png", optimize=True)
    # neon reflections: vertical smeared streaks of magenta and cyan, plus a faint base sheen over all the water
    glow = np.zeros((h, w, 3), np.float32)
    for centre, tint in ((0.28, (1.0, 0.18, 0.55)), (0.5, (0.2, 0.85, 1.0)), (0.74, (1.0, 0.6, 0.25))):
        cx = centre * w + rng.normal(0, 4)
        streak = np.exp(-((xx - cx) ** 2) / (2 * (w * 0.045) ** 2)) * np.clip(1.0 - np.abs(ny) * 0.7, 0, 1)
        streak *= 0.6 + 0.4 * fbm(h, w, rng, 3, 20)
        glow += streak[..., None] * np.array(tint, np.float32) * 0.8
    glow = np.clip(glow, 0, 1) * alpha[..., None]
    sheen = alpha * 0.22
    ga = np.clip(np.maximum(glow.max(axis=2), sheen), 0, 1)
    base = np.array([0.35, 0.5, 0.7], np.float32)
    grgb = np.where(glow.max(axis=2, keepdims=True) > 0.05, glow, base * sheen[..., None])
    qm.to_image(np.dstack([grgb, ga]).astype(np.float32)).save(OUT / "puddle_glow.png", optimize=True)
    patch("puddle", {"has_glow": "true", "ripple": "true"})


def floor_marking() -> None:
    rng = np.random.default_rng(3)
    w, h = 64 * SCALE, 4 * SCALE
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    period = 22.0
    band = ((xx + yy * 1.0) % period) < period * 0.5
    paint = np.where(band[..., None], np.array([0.78, 0.6, 0.12], np.float32), np.array([0.05, 0.05, 0.06], np.float32))
    wear = fbm(h, w, rng, 5, 24)
    chips = (fbm(h, w, rng, 4, 40) > 0.62).astype(np.float32)  # paint chipped off, showing grey concrete
    concrete = np.array([0.22, 0.23, 0.26], np.float32)
    rgb = paint * (0.75 + 0.35 * wear[..., None])
    rgb = rgb * (1 - chips[..., None] * 0.7) + concrete * chips[..., None] * 0.7
    # dirty edge, slightly ragged
    edge = np.clip(np.minimum(yy, h - 1 - yy) / 3.0, 0, 1)
    alpha = np.clip(edge * (0.85 + 0.3 * wear), 0, 1)
    alpha[:, :6] *= np.linspace(0.3, 1, 6)
    alpha[:, -6:] *= np.linspace(1, 0.3, 6)
    rgb *= (0.8 + 0.2 * edge[..., None])
    color = np.dstack([np.clip(rgb, 0, 1), alpha])
    qm.to_image(color).save(OUT / "floor_marking.png", optimize=True)
    qm.to_image(qm.normal_map(color, strength=1.2, bevel_px=2.0, bevel_weight=0.3)).save(OUT / "floor_marking_n.png", optimize=True)
    (OUT / "floor_marking_glow.png").unlink(missing_ok=True)
    patch("floor_marking", {"has_glow": "false"})


def patch(pid: str, fields: dict) -> None:
    path = DATA / f"{pid}.tres"
    tres = path.read_text(encoding="utf-8")
    for key, value in fields.items():
        if key == "has_glow" and value == "false" and not re.search(r"^has_glow = true", tres, re.M):
            continue
        tres = set_field(tres, key, value)
    path.write_text(tres, encoding="utf-8")
    print(f"ok    {pid}")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    puddle()
    floor_marking()
