"""Normal maps for flat cel-shaded props from a height field estimated from the silhouette (BG-8).

The old normal map came from blurred luminance plus a linear bevel: on flat cel colours that gives a weak, sticker-like
relief, and noise from texture detail shows up as fake bumps on flat panels. This module builds a height field instead:

  profile "pillow"      flat plateau with a circular-profile rounded edge (doors, signs, boxes: flat faces, round rims)
  profile "cylinder"    every horizontal run of the shape bulges like a vertical cylinder (barrels, tanks, poles, lamps)
  profile "cylinder_h"  the same for a horizontal axis (pipes, beams)
  profile "dome"        distance from the silhouette edge, rounded over the whole shape (bushes, sacks, round things)
  profile "flat"        only a thin rim, no inflation

plus *gated* surface detail: edges between flat colours (panel lines, ink outlines) raise a groove, but luminance
differences below `gate` are ignored, so flat areas stay flat.

  depth_normal_map(rgba, profile="pillow", ...) -> RGBA float, OpenGL tangent normals (Y+ up), alpha copied

No model and no download: it is geometry from the picture's own outline, deterministic and fast.
"""
from __future__ import annotations

import cv2
import numpy as np

LUMA = np.array([0.299, 0.587, 0.114], dtype=np.float32)
PROFILES = ("pillow", "cylinder", "cylinder_h", "dome", "flat")


def _round_profile(t: np.ndarray) -> np.ndarray:
    """0 at the edge, 1 inside: a quarter circle, so the slope is vertical at the rim and flat in the middle."""
    t = np.clip(t, 0.0, 1.0)
    return np.sqrt(1.0 - (1.0 - t) ** 2)


def _runs_cylinder(mask: np.ndarray, cap_px: float) -> np.ndarray:
    """Per row, every run of mask pixels gets a half-circle bulge whose height is the run's half width (capped)."""
    h, w = mask.shape
    out = np.zeros((h, w), dtype=np.float32)
    for y in range(h):
        row = mask[y]
        if not row.any():
            continue
        d = np.diff(np.concatenate([[0], row.astype(np.int8), [0]]))
        for a, b in zip(np.flatnonzero(d == 1), np.flatnonzero(d == -1)):
            half = (b - a) / 2.0
            if half < 1.0:
                continue
            x = np.arange(a, b, dtype=np.float32) + 0.5
            u = np.clip((x - (a + half)) / half, -1.0, 1.0)
            out[y, a:b] = np.sqrt(1.0 - u * u) * min(half, cap_px)
    return out


def height_field(alpha: np.ndarray, profile: str, round_px: float, relief: float) -> np.ndarray:
    mask = alpha > 0.5
    if profile == "flat":
        dist = cv2.distanceTransform(mask.astype(np.uint8), cv2.DIST_L2, 5)
        return _round_profile(dist / max(round_px * 0.35, 1.0)) * relief * round_px * 0.35
    if profile == "cylinder":
        return _runs_cylinder(mask, round_px * 6.0) * relief
    if profile == "cylinder_h":
        return _runs_cylinder(np.ascontiguousarray(mask.T), round_px * 6.0).T * relief
    dist = cv2.distanceTransform(mask.astype(np.uint8), cv2.DIST_L2, 5)
    if profile == "dome":
        top = max(float(dist.max()), 1.0)
        return _round_profile(dist / top) * top * relief
    return _round_profile(dist / max(round_px, 1.0)) * round_px * relief  # pillow


def surface_detail(rgb: np.ndarray, alpha: np.ndarray, sigma: float, gate: float) -> np.ndarray:
    """Grooves from edges between flat colours. Luminance steps smaller than `gate` (0..1) are dropped completely, so
    flat faces and soft gradients add nothing; the result is zero outside the silhouette and near its rim."""
    lum = rgb @ LUMA
    fine = cv2.GaussianBlur(lum, (0, 0), sigma)
    coarse = cv2.GaussianBlur(lum, (0, 0), sigma * 4.0)
    dog = fine - coarse
    dog = np.sign(dog) * np.maximum(np.abs(dog) - gate, 0.0)
    inside = cv2.erode((alpha > 0.5).astype(np.uint8), np.ones((3, 3), np.uint8)).astype(np.float32)
    return dog * cv2.GaussianBlur(inside, (0, 0), 1.0)


def depth_normal_map(rgba: np.ndarray, profile: str = "pillow", round_px: float | None = None, relief: float = 1.0,
                     detail: float = 0.6, detail_sigma: float = 1.2, gate: float = 0.05, strength: float = 1.0) -> np.ndarray:
    """RGBA float image (0..1) -> RGBA normal map. `round_px` defaults to 7% of the shorter side of the drawn part;
    `relief` scales the inflation, `detail` the groove height in the same units (pixels), `strength` the final tilt."""
    if profile not in PROFILES:
        raise KeyError(f"unknown normal profile '{profile}' (known: {', '.join(PROFILES)})")
    rgb, alpha = rgba[..., :3], rgba[..., 3]
    ys, xs = np.nonzero(alpha > 0.5)
    if len(xs) == 0:
        flat = np.zeros(alpha.shape + (4,), dtype=np.float32)
        flat[..., 0] = flat[..., 1] = 0.5
        flat[..., 2] = 1.0
        return flat
    short = max(1.0, min(xs.max() - xs.min() + 1, ys.max() - ys.min() + 1))
    r = float(round_px) if round_px else max(2.0, float(short) * 0.07)
    height = height_field(alpha, profile, r, relief)
    height = height + surface_detail(rgb, alpha, detail_sigma, gate) * detail * r * 2.0
    height = cv2.GaussianBlur(height.astype(np.float32), (0, 0), 0.8)
    gx = cv2.Sobel(height, cv2.CV_32F, 1, 0, ksize=3) / 8.0
    gy = cv2.Sobel(height, cv2.CV_32F, 0, 1, ksize=3) / 8.0
    # image y grows downwards, "up" is -y: n = (-dh/dx, +dh/dy_image, 1) in Y+ up space (same convention as qwen_matte.normal_map)
    nx, ny, nz = -gx * strength, gy * strength, np.ones_like(gx)
    norm = np.sqrt(nx * nx + ny * ny + nz * nz)
    out = np.dstack([nx / norm * 0.5 + 0.5, ny / norm * 0.5 + 0.5, nz / norm * 0.5 + 0.5, alpha])
    return np.clip(out, 0.0, 1.0)


def lit_preview(rgba: np.ndarray, normal: np.ndarray, light_dir=(-0.75, 0.45, 0.5), ambient: float = 0.38) -> np.ndarray:
    """Lambert shading of a sprite under one directional light (for before/after sheets; the game uses Godot's lights)."""
    n = normal[..., :3] * 2.0 - 1.0
    n /= np.maximum(np.linalg.norm(n, axis=2, keepdims=True), 1e-6)
    ld = np.array(light_dir, dtype=np.float32)
    ld /= np.linalg.norm(ld)
    lam = np.clip(n @ ld, 0.0, 1.0)
    shade = ambient + (1.0 - ambient) * lam
    return np.dstack([np.clip(rgba[..., :3] * shade[..., None] * 1.15, 0.0, 1.0), rgba[..., 3]])
