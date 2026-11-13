"""CPU-only under-cuff candidate. Never writes the live spec/runtime or original source."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
WORK = Path(__file__).resolve().parent
OUT = WORK / "repair_candidates/wrist-v3"
SCRATCH = ROOT / "work/ne267-wrist-candidate-v3"
sys.path.insert(0, str(ROOT / "tools/comfyui"))
from cut_layers import part_transform, render_part


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    OUT.mkdir(parents=True, exist_ok=False)
    SCRATCH.mkdir(parents=True, exist_ok=False)
    (SCRATCH / ".gdignore").touch()
    (SCRATCH / "06_parts").mkdir()
    spec_path = ROOT / "tools/comfyui/specs/guest_zheng_side.json"
    spec = json.loads(spec_path.read_text(encoding="utf8"))
    original_spec_sha = sha(spec_path)
    entry = next(e for e in spec["refine"]["underlap"] if e["part"] == "hand" and e["under"] == "arm_lower")
    before = entry["poly"]
    entry["poly"] = [[445, 732], [468, 732], [478, 752], [468, 768], [445, 762]]
    candidate_spec = OUT / "spec.json"
    candidate_spec.write_text(json.dumps(spec, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
    shutil.copyfile(WORK / "base_rgba.png", SCRATCH / "base_rgba.png")
    for name in spec["parts"]:
        shutil.copyfile(WORK / "06_parts" / (name + ".png"), SCRATCH / "06_parts" / (name + ".png"))
    command = [sys.executable, "-X", "utf8", "tools/comfyui/refine_parts.py", "--spec", str(candidate_spec),
               "--work", str(SCRATCH), "--only", "hand"]
    result = subprocess.run(command, cwd=ROOT, capture_output=True)
    (OUT / "refine.log").write_bytes(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError("CPU candidate refinement rejected; live assets remain untouched")
    source = SCRATCH / "07_refined/hand.png"
    shutil.copyfile(source, OUT / "hand.png")
    old = np.array(Image.open(WORK / "07_refined/hand.png"))
    original = np.array(Image.open(WORK / "06_parts/hand.png"))
    new = np.array(Image.open(source))
    k = spec["tex_px_per_wp"] / spec["illustration_px_per_wp"]
    joints = {key: np.asarray(value) * k for key, value in spec["joints"].items()}
    transform = part_transform(Image.fromarray(new), spec["parts"]["hand"], joints, k)
    runtime = render_part(Image.fromarray(new), transform, k)
    Image.fromarray(runtime).save(OUT / "runtime.png")
    current = Image.open(WORK / "07_refined/hand.png")
    current_transform = part_transform(current, spec["parts"]["hand"], joints, k)
    fixed_canvas = render_part(Image.fromarray(new), current_transform, k)
    Image.fromarray(fixed_canvas).save(OUT / "diagnostic-current-canvas.png")
    opaque = original[:, :, 3] >= 128
    assert np.array_equal(old[opaque], new[opaque])
    assert np.array_equal(old[800:], new[800:])
    assert sha(spec_path) == original_spec_sha
    receipt = dict(classification="unadopted CPU material candidate; no native acceptance claim",
                   source_spec_sha256=original_spec_sha, before_polygon=before, candidate_polygon=entry["poly"],
                   material_point=entry["material_point"], inset=entry["inset"], k=k,
                   changed_source_pixels=int(np.count_nonzero(np.any(new != old, axis=2))),
                   changed_source_alpha_pixels=int(np.count_nonzero(new[:, :, 3] != old[:, :, 3])),
                   original_source_opaque_rgba_exact=True, fingers_below_source_y800_rgba_exact=True,
                   previous_derived_opaque_rgb_changes=int(np.count_nonzero((old[:, :, 3] >= 128) & np.any(old != new, axis=2))),
                   actual_native_canvas=[runtime.shape[1], runtime.shape[0]],
                   native_pivot=transform[3].tolist(), live_spec_unchanged=True, live_runtime_unchanged=True)
    (OUT / "candidate.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf8")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
