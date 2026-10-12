"""Procedural ground decals that a generative model cannot draw well (NE-62 / NE-63): rain puddles and floor markings.

Usage: python tools/assets/procedural_props.py

Writes art/environment/props/{puddle,floor_marking,sun_patch}{,_n,_glow}.png and patches the prop data (has_glow, ripple);
sun_patch (the patch of daylight on the floor, BG-45) also writes its own prop data.
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


SUN_PATCH_SIZE = (56, 88)  # world px: a shaft about as wide as a doorway, taller than the hero
SUN_PATCH_TRES = """[gd_resource type="Resource" script_class="PropData" format=3]

[ext_resource type="Script" path="res://data/scripts/prop_data.gd" id="1_prop"]

[resource]
script = ExtResource("1_prop")
id = &"sun_patch"
display_name = "地上的光斑"
category = &"scene"
texture = "res://art/environment/props/sun_patch.png"
size = Vector2(%d, %d)
has_glow = true
light_color = Color(1, 0.93, 0.74, 1)
light_radius = 70.0
light_energy = 0.9
light_offset = Vector2(%d, %d)
"""


def sun_patch() -> None:
    """A patch of daylight falling on the floor (BG-45): a soft shaft that widens downwards and a brighter ellipse where it
    lands. It is all glow (the colour picture is transparent) and every edge fades out, so there is no outline; the prop's
    light does the actual lighting of whoever stands in it."""
    w, h = SUN_PATCH_SIZE[0] * SCALE, SUN_PATCH_SIZE[1] * SCALE
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    v = yy / (h - 1)
    centre = w * 0.5 + (v - 1.0) * w * 0.08          # the shaft leans a little, like light through a high window
    half = w * (0.16 + 0.24 * v)                      # narrow at the top, wide at the floor
    across = np.exp(-(((xx - centre) / half) ** 2) * 1.6)
    along = np.clip(v / 0.25, 0, 1) ** 1.5 * (0.35 + 0.65 * v)   # fades in from nothing at the top
    shaft = across * along * 0.3
    floor_y = h - h * 0.045
    pool = np.exp(-(((xx - w * 0.5) / (w * 0.42)) ** 2 + ((yy - floor_y) / (h * 0.035)) ** 2) * 1.2) * 0.38   # dim: bloom plus the prop's own light already brighten the floor here
    glow = np.clip(shaft + pool, 0, 1)
    warm = np.array([1.0, 0.94, 0.78], np.float32)
    qm.to_image(np.dstack([np.broadcast_to(warm, (h, w, 3)) * glow[..., None], glow])).save(OUT / "sun_patch_glow.png", optimize=True)
    qm.to_image(np.dstack([np.broadcast_to(warm, (h, w, 3)), glow * 0.02])).save(OUT / "sun_patch.png", optimize=True)
    flat = np.zeros((h, w, 4), np.float32)
    flat[..., 0] = 0.5
    flat[..., 1] = 0.5
    flat[..., 2] = 1.0
    flat[..., 3] = 1.0
    qm.to_image(flat).save(OUT / "sun_patch_n.png", optimize=True)
    path = DATA / "sun_patch.tres"
    path.write_text(SUN_PATCH_TRES % (SUN_PATCH_SIZE[0], SUN_PATCH_SIZE[1], SUN_PATCH_SIZE[0] // 2, SUN_PATCH_SIZE[1] - 30), encoding="utf-8", newline=chr(10))
    print("ok    sun_patch")


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
    sun_patch()
    from texture_import import apply_policy
    apply_policy()
