"""Original 1 stage-pixel material-foot gate, independently from saved affines."""
import argparse
import hashlib
import json
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("folder", type=Path)
parser.add_argument("--project", type=Path, help="Optional original-source project; each image must match the sealed source hash")
parser.add_argument("--out", type=Path, help="Write a separate report; the original acceptance receipt is never overwritten")
args = parser.parse_args()
scenes = json.loads((args.folder / "scenes.json").read_text(encoding="utf8"))
expected = json.loads((args.folder / "material-foot-independent-v1.json").read_text(encoding="utf8"))
project = args.project if args.project is not None else args.folder / "material_sources"
source = {}
rows = []
errors = []
for scene in scenes["scenes"]:
    values, below, unsupported = [], [], []
    for sample in scene["posture_samples"]:
        feet = sample["material_feet"]
        assert len(feet) == 2
        deltas = []
        for foot in feet:
            name = foot["source"]
            if name not in source:
                path = project / name.removeprefix("res://")
                actual_sha = hashlib.sha256(path.read_bytes()).hexdigest()
                assert actual_sha == expected["source_sha256"][name], "Material source differs from the original saved affine observations"
                image = np.array(Image.open(path).convert("RGBA"))
                ys, xs = np.nonzero(image[:, :, 3] >= 128)
                points = np.column_stack([xs + .5, ys + .5]).astype(np.float32)
                hull = cv2.convexHull(points).reshape(-1, 2).astype(np.float64)
                source[name] = dict(hull=hull, sha256=actual_sha)
            points = source[name]["hull"] + foot["rect_origin"]
            affine = np.asarray(foot["source_to_stage"])
            bottom = (points @ affine[:, :2].T + affine[:, 2])[:, 1].max()
            delta = float(bottom - foot["floor_stage_y"])
            errors.append(abs(delta - foot["delta_stage"]))
            assert errors[-1] < .0001
            deltas.append(delta)
            values.append(delta)
            if delta > 1.0:
                below.append(dict(msec=sample["msec"], pose=sample["target_pose"], part=foot["part"], delta=delta))
        if min(abs(delta) for delta in deltas) > 1.0:
            unsupported.append(dict(msec=sample["msec"], pose=sample["target_pose"], deltas=deltas))
    rows.append(dict(id=scene["id"], samples=len(scene["posture_samples"]), material_foot_samples=len(values),
                     range_stage=[min(values), max(values)], below_floor_over_1_stage_pixel=below,
                     frames_without_either_material_within_1_stage_pixel=unsupported))
report = dict(classification="Independent original opaque source pixel-centre hull projected by saved actual sprite affines into the loaded stage; no ankle substitution or complete fixed60Hz claim", unchanged_existing_stage_contact_tolerance=1.0,
              observer_recomputed_max_difference=max(errors), source_sha256={name:value["sha256"] for name,value in source.items()}, rows=rows)
assert report == expected, "Recomputed material contact differs from the original acceptance receipt"
if args.out is not None:
    assert args.out.resolve() != (args.folder / "material-foot-independent-v1.json").resolve()
    assert not args.out.exists(), "Preserve earlier independent reports"
    args.out.write_text(json.dumps(report, indent=2) + "\n", encoding="utf8", newline="\n")
for row in rows:
    print(row["id"], row["range_stage"], "penetrating feet", len(row["below_floor_over_1_stage_pixel"]), "no supported foot", len(row["frames_without_either_material_within_1_stage_pixel"]))
print("observer/source recomputation maximum difference", max(errors))
