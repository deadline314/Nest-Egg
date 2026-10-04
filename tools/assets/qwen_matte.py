"""Matting, normal-map and glow helpers for Qwen-generated prop art (NE-62 / NE-63 / NE-61 / NE-65).

Qwen paints each prop on a flat background (white for dark objects, black for neon). These helpers turn that picture
into game textures:
  matte()      background colour -> alpha (flood fill from the border, so enclosed areas of the same colour survive)
  normal_map() a Y+ up tangent-space normal map from luminance detail plus a bevel along the silhouette
  glow_mask()  bright saturated pixels (neon tubes, lamps, screens) or pure-red beacons -> emissive layer
Everything is deterministic; parameters come from assets_src/pipeline/qwen_props.json.
"""
from __future__ import annotations

import cv2
import numpy as np
from PIL import Image
import grade as grade_lib  # noqa: E402

LUMA = np.array([0.299, 0.587, 0.114], dtype=np.float32)


def matte(rgb: np.ndarray, bg: str = "white", tol: float = 0.10, soft: float = 0.12) -> np.ndarray:
    """RGB float image (H, W, 3, 0..1) -> RGBA with the background removed.

    The background is whatever is connected to the image border and within `tol` of the background colour; the band
    from `tol` to `tol + soft` becomes partial alpha, and the background colour is divided out of those edge pixels
    so no white or black fringe is left.
    """
    h, w = rgb.shape[:2]
    ref = np.array({"white": [1, 1, 1], "black": [0, 0, 0]}[bg], dtype=np.float32)
    dist = np.abs(rgb - ref).max(axis=2)
    # background candidates: close to the reference colour
    cand = (dist <= tol + soft).astype(np.uint8)
    # keep only the candidates connected to the border
    count, labels = cv2.connectedComponents(cand, connectivity=4)
    border = np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))
    border = border[border != 0]
    outside = np.isin(labels, border)
    alpha = np.where(outside, np.clip((dist - tol) / soft, 0.0, 1.0), 1.0).astype(np.float32)
    # remove a one pixel halo so the antialiased edge does not carry background colour
    alpha = cv2.erode(alpha, np.ones((2, 2), np.uint8)) if outside.any() else alpha
    alpha = cv2.GaussianBlur(alpha, (0, 0), 0.6)
    a = np.clip(alpha, 1e-3, 1.0)[..., None]
    fg = np.clip((rgb - (1.0 - a) * ref) / a, 0.0, 1.0)
    fg = np.where(alpha[..., None] > 0.98, rgb, fg)
    return np.dstack([fg, alpha])


def silhouette_matte(rgb: np.ndarray, gamma: float = 1.0) -> np.ndarray:
    """Dark-on-white silhouette art -> alpha = darkness. Returns RGBA with black colour (the game tints it)."""
    lum = (rgb @ LUMA) ** gamma
    alpha = np.clip((1.0 - lum - 0.04) / 0.84, 0.0, 1.0)
    return np.dstack([np.zeros_like(rgb), alpha.astype(np.float32)])


def bevel(alpha: np.ndarray, width_px: float) -> np.ndarray:
    """0 at the silhouette edge rising to 1 `width_px` inside (smooth)."""
    mask = (alpha > 0.5).astype(np.uint8)
    d = cv2.distanceTransform(mask, cv2.DIST_L2, 5)
    return np.clip(d / max(width_px, 1e-3), 0.0, 1.0) ** 0.8


def normal_map(rgba: np.ndarray, strength: float = 2.0, detail_sigma: float = 1.2, bevel_px: float = 6.0,
               bevel_weight: float = 0.5, profile: str | None = None, **depth) -> np.ndarray:
    """RGBA float image -> RGBA normal map (OpenGL convention: +Y up, which is what Godot 2D lighting expects).

    Height is a blend of blurred luminance (panels, rivets, folds read as relief) and a bevel along the outline.
    Flat areas come out as (0.5, 0.5, 1.0).
    With `profile` (pillow / cylinder / cylinder_h / dome / flat) the height comes from depth_normals.py instead.
    """
    if profile:  # BG-8: height field from the silhouette (see depth_normals.py); `depth` holds its parameters
        import depth_normals
        return depth_normals.depth_normal_map(rgba, profile, **depth)
    lum = rgba[..., :3] @ LUMA
    detail = cv2.GaussianBlur(lum, (0, 0), detail_sigma)
    detail = (detail - cv2.GaussianBlur(lum, (0, 0), detail_sigma * 8)) * 2.0  # drop low-frequency shading
    height = detail * (1.0 - bevel_weight) + bevel(rgba[..., 3], bevel_px) * bevel_weight * 1.5
    gx = cv2.Sobel(height, cv2.CV_32F, 1, 0, ksize=3) / 8.0
    gy = cv2.Sobel(height, cv2.CV_32F, 0, 1, ksize=3) / 8.0
    # image y grows downwards, "up" is -y: n = (-dh/dx, +dh/dy_image, 1) in Y+ up space
    nx, ny, nz = -gx * strength, gy * strength, np.ones_like(gx)
    norm = np.sqrt(nx * nx + ny * ny + nz * nz)
    out = np.dstack([nx / norm * 0.5 + 0.5, ny / norm * 0.5 + 0.5, nz / norm * 0.5 + 0.5, rgba[..., 3]])
    return np.clip(out, 0.0, 1.0)


def rgb_to_hsv(rgb: np.ndarray):
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(axis=2), rgb.min(axis=2)
    d = mx - mn
    h = np.zeros_like(mx)
    nz = d > 1e-6
    rm = nz & (mx == r)
    gm = nz & (mx == g) & ~rm
    bm = nz & ~rm & ~gm
    h[rm] = ((g - b)[rm] / d[rm]) % 6
    h[gm] = (b - r)[gm] / d[gm] + 2
    h[bm] = (r - g)[bm] / d[bm] + 4
    s = np.where(mx > 1e-6, d / np.maximum(mx, 1e-6), 0.0)
    return h * 60.0, s, mx


def glow_mask(rgba: np.ndarray, rules: list[dict]) -> np.ndarray | None:
    """Emissive layer: pixels matching any rule keep their colour (boosted), everything else is transparent.

    A rule is {"hue": [lo, hi] (degrees, optional), "smin": .., "vmin": .., "boost": ..}; "red_beacon": true selects the
    pure-red pixels the window-life shader blinks (r > 0.7, g and b < 0.35) and repaints them pure red.
    Returns RGBA or None when nothing matched.
    """
    rgb, alpha = rgba[..., :3], rgba[..., 3]
    hue, sat, val = rgb_to_hsv(rgb)
    mask = np.zeros(alpha.shape, dtype=np.float32)
    out_rgb = np.zeros_like(rgb)
    for rule in rules:
        if rule.get("red_beacon"):
            m = ((hue < 18) | (hue > 342)) & (sat > rule.get("smin", 0.55)) & (val > rule.get("vmin", 0.6))
            m = m.astype(np.float32)
            m = cv2.GaussianBlur(m, (0, 0), 0.8)
            out_rgb = np.where(m[..., None] > 0.05, np.array([1.0, 0.12, 0.1], dtype=np.float32), out_rgb)
            mask = np.maximum(mask, m)
            continue
        m = (sat >= rule.get("smin", 0.35)) & (val >= rule.get("vmin", 0.7))
        if "hue" in rule:
            lo, hi = rule["hue"]
            m &= ((hue >= lo) & (hue <= hi)) if lo <= hi else ((hue >= lo) | (hue <= hi))
        m = cv2.GaussianBlur(m.astype(np.float32), (0, 0), rule.get("soft", 1.0))
        boost = float(rule.get("boost", 1.0))
        out_rgb = np.where(m[..., None] > mask[..., None], np.clip(rgb * boost, 0, 1), out_rgb)
        mask = np.maximum(mask, m)
    mask *= alpha
    if mask.max() < 0.05:
        return None
    return np.dstack([out_rgb, mask])


def grade(a: np.ndarray, g: dict, kind: str | None = None) -> np.ndarray:
    """Entry grade (gamma, saturation, contrast, brightness, tint); with `kind` ('prop' or 'scene') the shared master
    grade (see grade.py) follows. Emissive layers and glow sources pass no kind."""
    if kind is None:
        return grade_lib.grade(a, g, "half")
    return grade_lib.grade_asset(a, g, kind, "half")

def to_image(a: np.ndarray) -> Image.Image:
    return Image.fromarray((np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA" if a.shape[2] == 4 else "RGB")
