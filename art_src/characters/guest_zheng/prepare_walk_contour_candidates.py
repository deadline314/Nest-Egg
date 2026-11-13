"""Bounded source-alpha underlap candidates for measured walk-only join notches.

Never changes live source/art. Immutable originals and all outside/opaque pixels
are checked before producing a same-registration runtime candidate.
"""
import hashlib
import json
import sys
from pathlib import Path

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[3]
WORK = Path(__file__).resolve().parent
OUT = WORK / "repair_candidates/walk-contours-v2"
REGIONS = {"pelvis": (622, 786, 645, 812), "foot": (373, 1385, 390, 1401), "arm_lower": (500, 556, 518, 575)}
sys.path.insert(0, str(ROOT / "tools/comfyui"))
from cut_layers import part_transform, render_part


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    OUT.mkdir(parents=True, exist_ok=False)
    spec = json.loads((ROOT / "tools/comfyui/specs/guest_zheng_side.json").read_text(encoding="utf8"))
    k = spec["tex_px_per_wp"] / spec["illustration_px_per_wp"]
    joints = {name: np.asarray(value) * k for name, value in spec["joints"].items()}
    records = []
    for name, box in REGIONS.items():
        source = WORK / "07_refined" / (name + ".png")
        old = np.array(Image.open(source).convert("RGBA"))
        original_transform = part_transform(Image.fromarray(old), spec["parts"][name], joints, k)
        original_runtime = render_part(Image.fromarray(old), original_transform, k, crop_phase=spec["parts"][name].get("crop_phase"))
        live = np.array(Image.open(ROOT / "art/characters/guest_zheng/parts" / (name + ".png")))
        assert np.array_equal(original_runtime, live), name + ": A/A renderer must reproduce existing pixels exactly"
        Image.fromarray(old).save(OUT / (name + "-original-source.png"))
        Image.fromarray(live).save(OUT / (name + "-original-runtime.png"))
        alpha = old[:, :, 3]
        x0, y0, x1, y1 = box
        region = np.zeros(alpha.shape, np.uint8)
        region[y0:y1, x0:x1] = 1
        # A rectangular fade produced tiny tabs where it ended on the source
        # silhouette. This compact C2 ellipse reaches zero smoothly; measured
        # failed UVs remain in its unattenuated centre. No global contour blur.
        yy, xx = np.mgrid[y0:y1, x0:x1]
        distance = np.sqrt(((xx + .5 - (x0+x1)*.5) / ((x1-x0)*.5))**2
                           + ((yy + .5 - (y0+y1)*.5) / ((y1-y0)*.5))**2)
        phase = np.clip((distance-.55)/.45, 0, 1)
        feather = np.zeros(alpha.shape, np.float32)
        feather[y0:y1, x0:x1] = 1-phase**3*(10-15*phase+6*phase**2)
        _, nearest = ndimage.distance_transform_edt(alpha < 128, return_indices=True)
        for radius in (2, 3, 4):
            folder = OUT / ("radius-%d" % radius)
            folder.mkdir(exist_ok=True)
            expanded = cv2.dilate(alpha, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (radius * 2 + 1, radius * 2 + 1)))
            proposed = np.rint(alpha + (expanded.astype(float) - alpha) * feather).astype(np.uint8)
            repair = (alpha < 128) & (proposed > alpha)
            new = old.copy()
            new[:, :, 3][repair] = proposed[repair]
            new[:, :, :3][repair & (alpha == 0)] = old[nearest[0][repair & (alpha == 0)], nearest[1][repair & (alpha == 0)], :3]
            assert np.array_equal(old[alpha >= 128], new[alpha >= 128])
            assert np.array_equal(old[region == 0], new[region == 0])
            assert np.array_equal(old[feather == 0], new[feather == 0])
            transform = part_transform(Image.fromarray(new), spec["parts"][name], joints, k)
            assert all(np.array_equal(a, b) for a, b in zip(original_transform, transform)), "No crop/pivot/sample-grid drift allowed"
            runtime = render_part(Image.fromarray(new), transform, k, crop_phase=spec["parts"][name].get("crop_phase"))
            Image.fromarray(new).save(folder / (name + "-source.png"))
            Image.fromarray(runtime).save(folder / (name + ".png"))
            records.append(dict(part=name, radius_source_pixels=radius, native_source_box=list(box), region_shape="compact C2 ellipse, inner radius .55; no rectangular cut-off",
                                input_sha256=sha(source), source_sha256=sha(folder / (name + "-source.png")), runtime_sha256=sha(folder / (name + ".png")),
                                original_opaque_rgba_exact=True, outside_region_rgba_exact=True, crop_and_pivot_exact=True,
                                changed_source_pixels=int(repair.sum()), changed_runtime_pixels=int(np.any(runtime != live, axis=2).sum())))
    (OUT / "candidates.json").write_text(json.dumps(dict(classification="CPU-only unadopted local source underlap candidates; native acceptance still required", candidates=records), indent=2) + "\n", encoding="utf8", newline="\n")
    print([(r["part"], r["radius_source_pixels"], r["changed_runtime_pixels"]) for r in records])


if __name__ == "__main__":
    main()
