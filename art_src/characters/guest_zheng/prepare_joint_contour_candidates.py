"""Bounded material repair candidates at measured true hip/knee locations; no live writes."""
import hashlib
import json
from pathlib import Path
import sys

import cv2
import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parents[3]
WORK = Path(__file__).resolve().parent
OUT = WORK / "repair_candidates/joint-contours-v1"
REGIONS = {"pelvis": (622, 760, 642, 807), "leg_lower": (380, 1095, 394, 1113)}
sys.path.insert(0, str(ROOT / "tools/comfyui"))
from cut_layers import part_transform, render_part


def main():
    OUT.mkdir(parents=True, exist_ok=False)
    spec = json.loads((ROOT / "tools/comfyui/specs/guest_zheng_side.json").read_text(encoding="utf8"))
    k = spec["tex_px_per_wp"] / spec["illustration_px_per_wp"]
    joints = {key: np.asarray(v) * k for key, v in spec["joints"].items()}
    records = []
    for name, box in REGIONS.items():
        source = WORK / "07_refined" / (name + ".png")
        old = np.array(Image.open(source).convert("RGBA"))
        alpha = old[:, :, 3]
        x0, y0, x1, y1 = box
        mask = np.zeros(alpha.shape, np.uint8)
        mask[y0:y1, x0:x1] = 1
        weight = np.minimum(ndimage.distance_transform_edt(mask) / 4, 1)
        expanded = cv2.dilate(alpha, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (9, 9)))
        proposed = np.rint(alpha + (expanded.astype(float) - alpha) * weight).astype(np.uint8)
        repair = (alpha < 128) & (proposed > alpha)
        new = old.copy()
        new[:, :, 3][repair] = proposed[repair]
        _, indices = ndimage.distance_transform_edt(alpha < 128, return_indices=True)
        missing_rgb = repair & (alpha == 0)
        new[:, :, :3][missing_rgb] = old[indices[0][missing_rgb], indices[1][missing_rgb], :3]
        assert np.array_equal(old[alpha >= 128], new[alpha >= 128])
        assert np.array_equal(old[mask == 0], new[mask == 0])
        Image.fromarray(new).save(OUT / (name + ".png"))
        transform = part_transform(Image.fromarray(new), spec["parts"][name], joints, k)
        runtime = render_part(Image.fromarray(new), transform, k)
        Image.fromarray(runtime).save(OUT / (name + "-runtime.png"))
        records.append(dict(part=name, native_source_box=list(box), radius_source_pixels=4,
                            region_feather_source_pixels=4, k=k,
                            input_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                            output_sha256=hashlib.sha256((OUT / (name + ".png")).read_bytes()).hexdigest(),
                            changed_pixels=int(np.count_nonzero(repair)),
                            original_opaque_rgba_exact=True, outside_region_rgba_exact=True,
                            new_runtime_size=[runtime.shape[1], runtime.shape[0]], pivot=transform[3].tolist()))
    (OUT / "candidates.json").write_text(json.dumps(dict(
        classification="unadopted CPU local joint material candidates; not native acceptance",
        live_assets_unchanged=True, candidates=records), indent=2) + "\n", encoding="utf8")
    print(json.dumps(records, indent=2))


if __name__ == "__main__":
    main()
