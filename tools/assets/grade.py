"""Shared colour grading for every asset pipeline (NE-66).

Each pipeline entry keeps its own `grade` (and `glow_grade`) in its manifest; on top of that a *master* grade in
assets_src/pipeline/grade_master.json is applied to every body image, so one edit retunes all replaced art at once
(re-run the pipelines afterwards). Glow layers are emissive and never get the master grade.

grade_master.json
  all    grade applied to every kind (identity by default)
  kinds  per-kind grades applied after `all`: material, facade, backdrop, sky, prop, scene

A grade is {gamma, saturation, contrast, brightness, tint[3]}; missing keys mean "unchanged".
Usage: python tools/assets/grade.py --check     (validates grade_master.json, exits 1 on problems)
"""
import json
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
MASTER_PATH = ROOT / "assets_src" / "pipeline" / "grade_master.json"
LUMA = np.array([0.299, 0.587, 0.114], dtype=np.float32)
KINDS = ("material", "facade", "backdrop", "sky", "prop", "scene")
KEYS = ("gamma", "saturation", "contrast", "brightness", "tint")

_master_cache: dict | None = None


def grade(a: np.ndarray, g: dict, pivot: str = "half") -> np.ndarray:
    """Grade an RGB float array in 0..1. `pivot` is the contrast centre: 'half' (0.5) or 'mean' (image mean)."""
    a = a ** float(g.get("gamma", 1.0))
    if pivot == "mean":
        mean = a.mean()
        a = (a - mean) * float(g.get("contrast", 1.0)) + mean
    lum = a @ LUMA
    a = lum[..., None] + (a - lum[..., None]) * float(g.get("saturation", 1.0))
    if pivot != "mean":
        a = (a - 0.5) * float(g.get("contrast", 1.0)) + 0.5
    a = a * float(g.get("brightness", 1.0)) * np.array(g.get("tint", [1, 1, 1]), dtype=np.float32)
    return np.clip(a, 0.0, 1.0)


def master() -> dict:
    """The master grade file (cached). A missing or broken file logs the problem and falls back to 'no master grade'."""
    global _master_cache
    if _master_cache is None:
        _master_cache = {"all": {}, "kinds": {}}
        if MASTER_PATH.exists():
            try:
                _master_cache = json.loads(MASTER_PATH.read_text(encoding="utf-8"))
            except (OSError, ValueError) as err:
                print(f"[grade] cannot read {MASTER_PATH}: {err}; no master grade applied", file=sys.stderr)
    return _master_cache


def is_identity(g: dict) -> bool:
    return all(
        (g.get(k, 1.0) == 1.0) if k != "tint" else all(float(t) == 1.0 for t in g.get(k, [1, 1, 1]))
        for k in KEYS
    )


def grade_asset(a: np.ndarray, entry_grade: dict, kind: str, pivot: str = "half", use_master: bool = True) -> np.ndarray:
    """The entry's own grade, then (unless use_master is False, e.g. for emissive layers) the master grade for `kind`."""
    a = grade(a, entry_grade, pivot)
    if not use_master:
        return a
    m = master()
    for g in (m.get("all", {}), m.get("kinds", {}).get(kind, {})):
        if g and not is_identity(g):
            a = grade(a, g, pivot)
    return a


def grade_image(image, kind: str):
    """Apply the master grade for `kind` to a PIL RGBA/RGB image (used by pipelines that paint straight to PIL).
    Returns the image untouched when the master grade is the identity."""
    m = master()
    grades = [g for g in (m.get("all", {}), m.get("kinds", {}).get(kind, {})) if g and not is_identity(g)]
    if not grades:
        return image
    from PIL import Image

    a = np.asarray(image.convert("RGBA")).astype(np.float32) / 255.0
    for g in grades:
        a[..., :3] = grade(a[..., :3], g)
    return Image.fromarray((a * 255 + 0.5).astype(np.uint8), "RGBA")


def validate(data: dict) -> list[str]:
    """Problems in a master grade document (empty list = fine)."""
    problems = []

    def check(name: str, g: object) -> None:
        if not isinstance(g, dict):
            problems.append(f"{name}: must be an object")
            return
        for k, v in g.items():
            if k not in KEYS:
                problems.append(f"{name}: unknown key '{k}' (allowed: {', '.join(KEYS)})")
        for k in ("gamma", "saturation", "contrast", "brightness"):
            if k not in g:
                continue
            ok = isinstance(g[k], (int, float)) and (g[k] > 0 if k in ("gamma", "contrast") else g[k] >= 0)
            if not ok:
                problems.append(f"{name}.{k}: invalid value {g[k]!r}")
        if "tint" in g and not (isinstance(g["tint"], list) and len(g["tint"]) == 3 and all(isinstance(t, (int, float)) and t >= 0 for t in g["tint"])):
            problems.append(f"{name}.tint: must be three non-negative numbers")

    check("all", data.get("all", {}))
    kinds = data.get("kinds", {})
    if not isinstance(kinds, dict):
        problems.append("kinds: must be an object")
        kinds = {}
    for kind, g in kinds.items():
        if kind not in KINDS:
            problems.append(f"kinds.{kind}: unknown kind (allowed: {', '.join(KINDS)})")
        check(f"kinds.{kind}", g)
    return problems


def main() -> int:
    if "--check" not in sys.argv:
        print(__doc__)
        return 0
    if not MASTER_PATH.exists():
        print(f"missing {MASTER_PATH}")
        return 1
    try:
        data = json.loads(MASTER_PATH.read_text(encoding="utf-8"))
    except ValueError as err:
        print(f"{MASTER_PATH}: not valid JSON: {err}")
        return 1
    problems = validate(data)
    # The identity master grade must not change a pixel.
    probe = np.random.default_rng(1).random((4, 4, 3), dtype=np.float32)
    if not np.allclose(grade(probe, {}), probe):
        problems.append("grade(): empty grade must be a no-op")
    # The master grade really is applied (and not to emissive layers).
    global _master_cache
    saved = _master_cache
    _master_cache = {"all": {"brightness": 0.5}, "kinds": {"sky": {"brightness": 0.5}}}
    if not np.allclose(grade_asset(probe, {}, "prop"), probe * 0.5, atol=1e-5):
        problems.append("grade_asset(): 'all' master grade is not applied")
    if not np.allclose(grade_asset(probe, {}, "sky"), probe * 0.25, atol=1e-5):
        problems.append("grade_asset(): kind master grade is not applied after 'all'")
    if not np.allclose(grade_asset(probe, {}, "prop", use_master=False), probe):
        problems.append("grade_asset(): use_master=False must skip the master grade")
    _master_cache = saved
    for p in problems:
        print(p)
    print("grade master: " + ("OK" if not problems else f"{len(problems)} problem(s)"))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
