"""Restore this retained-source contract after field_spec --force recalibrates the arm.

No model or source image is edited. Parts, appearance and native acceptance remain separate.
"""
import json
import hashlib
from pathlib import Path

root = Path(__file__).resolve().parents[3]
path = root / "tools/comfyui/specs/guest_zheng_side.json"
spec = json.loads(path.read_text(encoding="utf-8"))
work = Path(__file__).resolve().parent
review_path = work / "02_pose/reviewed_masks.json"
if review_path.exists():
    review = json.loads(review_path.read_text(encoding="utf-8"))
    if hashlib.sha256((work / "base_rgba.png").read_bytes()).hexdigest() != review["source_sha256"]:
        raise ValueError("Reviewed masks belong to a different native source")
    for relative, digest in review["mask_sha256"].items():
        if hashlib.sha256((work / relative).read_bytes()).hexdigest() != digest:
            raise ValueError(f"Reviewed ownership mask changed: {relative}")
    # Pose pivots follow the measured mask center; valid segmentation prompts do
    # not have to move with those pivots or rerun an unchanged segmentation job.
    spec["groups"] = review["groups"]
spec["description"] = ("鄭先生的保留中性站姿來源；關節來自明示人工 authored rig reference，"
                       "不是模型預測或被遮住解剖的量測。分件、完整底層、接點與原生動作另驗。")
spec["preserve_source_alpha"] = True
# field_spec's single-column sole estimate (1510) put both rendered soles 1.2106
# stage pixels below the formal floor at 3.7x. The cut, straightened native foot
# requires ground 1519. Keep the intended H=56 and native k=1, not a stage offset.
spec["ground_y"] = 1519
spec["illustration_px_per_wp"] = round((1519 - spec["joints"]["head_top"][1]) / 56.0, 3)
spec["tex_px_per_wp"] = spec["illustration_px_per_wp"]
for stage in spec["stages"]:
    stage["resolution"] = 0  # Already 32-aligned native source; refuse resampling.
spec["refine"]["alpha_floor"] = 40
spec["refine"]["speckle"] = 30
# These retained lines already have clean source colors/coverage. A generic blur
# and edge repaint discards valid one-pixel contour material during reassembly.
spec["refine"].pop("smooth_alpha", None)
spec["refine"].pop("defringe", None)
# Do not silently paint arbitrary gaps in a newly adopted body. Inspect the actual
# underlayer and repair a demonstrated defect at its source before accepting it.
spec["refine"].pop("fill_holes", None)
# Source-ownership cleanup, measured on the native layer review: a far-shoe
# outline must not follow the near foot, and the shoelace must follow the shoe,
# not the calf. No general silhouette blur or threshold change is involved.
spec["refine"]["erase"] = [
    {"part": "foot", "poly": [[520, 1423], [585, 1423], [585, 1436], [530, 1436], [520, 1432]],
     "reason": "thin far-shoe outline outside near-foot material"},
    {"part": "leg_lower", "poly": [[489, 1408], [501, 1408], [501, 1420], [482, 1420], [484, 1413]],
     "reason": "shoelace belongs to the independent foot layer, which retains these source pixels"},
]
# The traced rendered hole maps to hand-source (456.61,747.40), beneath opaque
# forearm material, not the wrist pivot. Extend actual hand skin under that cuff
# locally. The earlier pivot-centred 49px forearm overlap did not fix the hole.
spec["refine"]["underlap"] = [
    entry for entry in spec["refine"]["underlap"]
    if (entry["part"], entry["under"]) not in [("arm_lower", "hand"), ("hand", "arm_lower")]
] + [{"part": "hand", "under": "arm_lower", "inset": 2,
      "material_point": [483, 785],
      "poly": [[445, 732], [468, 732], [478, 752], [468, 768], [445, 762]]}]
# Retain the native finger sampling footprint while adding hidden cuff material.
# This is the measured old 171x100 cut, not a new joint or a resized texture.
spec["parts"]["hand"]["crop_phase"] = {
    "origin": [-33.40700232243931, -43.18540513892454],
    "size": [171, 100], "k": 1.0,
    "affine": [[0.2020915299654007, -0.979366660118103, 526.5430908203125],
               [0.979366660118103, 0.2020915299654007, 720.5548706054688]],
}
for use in spec["parts"]["arm_upper"]["uses"]:
    use["root_attach"] = True
spec.setdefault("eye_states", {}).setdefault("eye_mask", [[553, 99], [585, 99], [585, 120], [553, 120]])
path.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
