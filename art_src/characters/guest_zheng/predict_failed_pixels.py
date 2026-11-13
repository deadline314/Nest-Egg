"""Read-only linear alpha sampling at old native failures; never changes a verdict."""
from pathlib import Path
import json
import sys
import argparse
import numpy as np
from PIL import Image
from scipy import ndimage
from trace_wrist import uv_points

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs"


def linear(alpha, uv):
    point = uv - .5  # texel centres in the captured pixel-coordinate UVs
    base = np.floor(point).astype(int)
    part = point - base
    x, y = base
    h, w = alpha.shape
    value = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            weight = (part[0] if dx else 1 - part[0]) * (part[1] if dy else 1 - part[1])
            value += alpha[np.clip(y + dy, 0, h - 1), np.clip(x + dx, 0, w - 1)] * weight / 255
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", nargs="?", default="cpu-alpha-replay-baseline.json")
    parser.add_argument("--materials", type=Path, help="explicit same-canvas CPU proxy PNGs; never native acceptance")
    args = parser.parse_args()
    overrides = json.loads(args.materials.read_text(encoding="utf8")) if args.materials else {}
    geometry = json.loads((OUT / "full-failed-cpu-geometry-v2.json").read_text(encoding="utf8"))
    cache = {}
    results = []
    for entry in geometry["results"]:
        failure = entry["failure"]
        file = OUT / entry["run"] / failure["file"]
        if file not in cache:
            cache[file] = np.array(Image.open(file))[:, :, 3]
        native = cache[file]
        x, y, w, h = map(int, failure["rect"])
        radius = int(failure["radius"])
        origin = np.array([w // 2 - radius, h // 2 - radius])
        band = native[y + origin[1]:y + h // 2 + radius, x + origin[0]:x + w // 2 + radius]
        ys, xs = np.nonzero(ndimage.binary_fill_holes(band >= 128) & ~(band >= 128))
        for px, py in zip(xs, ys):
            point = origin + [px + .5, py + .5]
            alpha = 0.0
            materials = []
            for material in entry["geometry"]:
                source = ROOT / material["texture"].removeprefix("res://")
                if source.stem in overrides:
                    source = ROOT / overrides[source.stem]
                if source not in cache:
                    cache[source] = np.array(Image.open(source))[:, :, 3]
                if list(cache[source].shape[::-1]) != material["size"]:
                    raise ValueError("CPU proxy must preserve the captured canvas; never resize a changed crop to fit")
                for uv in uv_points(material, point):
                    a = linear(cache[source], uv)
                    alpha = a + alpha * (1 - a)
                    materials.append(dict(part=material["part"], uv=uv.tolist(), linear_alpha=float(a)))
            results.append(dict(joint=failure["joint"], pose=failure["pose"], frame=failure["frame"],
                                zoom=failure["zoom"], native_alpha=int(band[py, px]),
                                predicted_alpha=float(alpha * 255), materials=materials))
    errors = [abs(p["native_alpha"] - p["predicted_alpha"]) for p in results]
    report = dict(classification="CPU material diagnosis; native report remains authoritative",
                  decoder="captured UVs at native pixel centres, bilinear clamp texture sampling and alpha-over",
                  max_alpha_difference=max(errors), mean_alpha_difference=float(np.mean(errors)),
                  candidate_materials=overrides, results=results)
    path = OUT / args.output
    path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf8")
    print(len(results), "pixels; native/predicted alpha max", max(errors), "mean", np.mean(errors))


if __name__ == "__main__":
    main()
