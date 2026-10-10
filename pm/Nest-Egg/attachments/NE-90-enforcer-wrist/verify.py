"""Reproduce the adopted enforcer wrist source override and compare formal outputs."""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys
import tempfile

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[4]
BUILDER_PATH = ROOT / "art_src/characters/enforcer/wrist_repair/rebuild.py"
SOURCE_DIR = BUILDER_PATH.parent
FORMAL = ROOT / "art/characters/enforcer"
PARTS = {
    "arm_lower": {
        "file": "parts/arm_lower.png",
        "normal": "parts/arm_lower_n.png",
        "size": [132, 206],
        "pivot": [51.61, 10.58],
        "texture_sha256": "51f2dac017d37eb437d5bca720e9330419313e435c3dedae0a0a6d5651a75b95",
        "normal_sha256": "ff0d36aa1cec85d1d33d9a125334083825007ce2da538282c419bb09cd912cc7",
    },
    "hand": {
        "file": "parts/hand.png",
        "normal": "parts/hand_n.png",
        "size": [111, 107],
        "pivot": [-5.66, 75.01],
        "texture_sha256": "d90ee46e9f457ced959d3d6ae8de4ce837e85bc37d0612052bc6f883a22a5967",
        "normal_sha256": "9cde2d25a13f260e8acdb54ff5c35556c07decb51c185acd423fc0f6bf4d883c",
    },
}


def file_sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def png_sha(array: np.ndarray) -> str:
    from io import BytesIO
    output = BytesIO()
    Image.fromarray(array).save(output, format="PNG")
    return hashlib.sha256(output.getvalue()).hexdigest()


def load_builder():
    spec = importlib.util.spec_from_file_location("enforcer_wrist_rebuild", BUILDER_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


def copy_source_clone(builder, work: Path) -> None:
    for relative in builder.SOURCES:
        source = SOURCE_DIR.parent / relative
        target = work / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    hand_union = SOURCE_DIR / "provenance/root-hand-selection/hand-union-fullcanvas.png"
    target = work / "wrist_repair/provenance/root-hand-selection/hand-union-fullcanvas.png"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(hand_union, target)


def cut_outputs(builder, outputs: dict[str, np.ndarray]) -> dict:
    cut_path = ROOT / "tools/comfyui/cut_layers.py"
    sys.path.insert(0, str(cut_path.parent))
    spec = importlib.util.spec_from_file_location("enforcer_cut_layers_replay", cut_path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    config = json.loads((ROOT / "tools/comfyui/specs/enforcer_side.json").read_text(encoding="utf-8"))
    scale = config["tex_px_per_wp"] / config["illustration_px_per_wp"]
    joints = {name: np.asarray(point, dtype=float) * scale for name, point in config["joints"].items()}
    result = {}
    for name, array in outputs.items():
        source = Image.fromarray(array, "RGBA")
        transform = module.part_transform(source, config["parts"][name], joints, scale)
        if transform is None:
            raise AssertionError(f"cut_layers produced empty {name}")
        texture = module.render_part(source, transform, scale)
        normal = module.make_normal_map(texture)
        _, width, height, pivot = transform
        result[name] = {
            "texture": np.asarray(texture),
            "normal": np.asarray(normal),
            "size": [int(width), int(height)],
            "pivot": [round(float(pivot[0]), 2), round(float(pivot[1]), 2)],
        }
    return result


def negative_controls(builder, work: Path) -> dict[str, bool]:
    source, masks = builder.load(work, SOURCE_DIR / "owners")
    checks: dict[str, bool] = {}
    with tempfile.TemporaryDirectory(prefix="enforcer-source-mutant-") as directory:
        changed = Path(directory) / "base_rgba.png"
        changed.write_bytes((work / "base_rgba.png").read_bytes() + b"mutated")
        try:
            builder.pin(changed, builder.SOURCES["base_rgba.png"])
        except ValueError:
            checks["source_sha_mutation_rejected"] = True
        else:
            raise AssertionError("mutated source SHA was accepted")

    arm_names = builder.OWNER_NAMES[:3]
    occupied = masks[arm_names[0]] | masks[arm_names[1]] | masks[arm_names[2]]
    inner = cv2.erode(occupied.astype(np.uint8), np.ones((3, 3), np.uint8), iterations=1)
    y, x = np.argwhere(inner > 0)[0]
    hole = occupied.copy()
    hole[y, x] = False
    try:
        builder.one_component_no_holes(hole, "negative-control arm")
    except ValueError:
        checks["one_pixel_hole_rejected"] = True
    else:
        raise AssertionError("one-pixel enclosed hole was accepted")

    cases = (
        ("one_owner_pixel_removed_rejected", np.argwhere(masks[arm_names[0]])[0]),
        ("extra_source_pixel_rejected", np.argwhere((source["base_rgba.png"][:, :, 3] > 0) & ~occupied)[0]),
    )
    for label, point in cases:
        altered = {name: value.copy() for name, value in masks.items()}
        altered[arm_names[0]][tuple(point)] = not altered[arm_names[0]][tuple(point)]
        try:
            builder.assemble(source, altered)
        except ValueError:
            checks[label] = True
        else:
            raise AssertionError(f"negative control failed: {label}")

    out_dir = work / "overrides/refined"
    before = {name: (out_dir / f"{name}.png").read_bytes() for name in ("arm_lower", "hand")}
    with tempfile.TemporaryDirectory(prefix="enforcer-bad-owner-") as directory:
        bad_owners = Path(directory)
        for name in (*builder.OWNER_NAMES, "seam_clear_overlap.png"):
            shutil.copy2(SOURCE_DIR / "owners" / name, bad_owners / name)
        bad_path = bad_owners / arm_names[0]
        bad_mask = builder.binary_l(bad_path)
        bad_mask[tuple(np.argwhere(bad_mask)[0])] = False
        Image.fromarray(bad_mask.astype(np.uint8) * 255, "L").save(bad_path)
        try:
            builder.build(work, bad_owners)
        except ValueError:
            checks["bad_mask_fails_before_output_write"] = True
        else:
            raise AssertionError("bad owner mask was accepted")
    if any((out_dir / f"{name}.png").read_bytes() != content for name, content in before.items()):
        raise AssertionError("failed preflight modified staged outputs")
    return checks


def verify_formal_metadata() -> dict:
    character = json.loads((FORMAL / "character.json").read_text(encoding="utf-8"))
    result = {}
    for name, expected in PARTS.items():
        texture = character["textures"][name]
        actual = {"file": texture["file"], "size": texture["size"], "pivot": texture["pivot"]}
        wanted = {"file": expected["file"], "size": expected["size"], "pivot": expected["pivot"]}
        if actual != wanted:
            raise AssertionError(f"formal character.json metadata changed for {name}: {actual}")
        result[name] = actual
    return result


def main() -> None:
    builder = load_builder()
    verify_formal_metadata()
    runs = []
    negative = None
    for run_index in range(2):
        with tempfile.TemporaryDirectory(prefix=f"enforcer-wrist-replay-{run_index + 1}-") as directory:
            work = Path(directory)
            copy_source_clone(builder, work)
            report = builder.build(work)
            replay = {name: Image.open(work / "overrides/refined" / f"{name}.png").convert("RGBA") for name in PARTS}
            outputs = {name: np.asarray(image).copy() for name, image in replay.items()}
            cuts = cut_outputs(builder, outputs)
            per_run = {"source_replay": report["full_canvas"], "formal_pngs": {}, "cut": {}}
            for name, result in cuts.items():
                expected = PARTS[name]
                formal_texture = FORMAL / expected["file"]
                formal_normal = FORMAL / expected["normal"]
                texture_hash = png_sha(result["texture"])
                normal_hash = png_sha(result["normal"])
                checks = {
                    "size_matches_manifest": result["size"] == expected["size"],
                    "pivot_matches_manifest": result["pivot"] == expected["pivot"],
                    "texture_matches_manifest": texture_hash == expected["texture_sha256"],
                    "normal_matches_manifest": normal_hash == expected["normal_sha256"],
                    "texture_matches_formal": texture_hash == file_sha(formal_texture),
                    "normal_matches_formal": normal_hash == file_sha(formal_normal),
                }
                if not all(checks.values()):
                    raise AssertionError(f"formal cut comparison failed for {name}: {checks}")
                per_run["cut"][name] = {"size": result["size"], "pivot": result["pivot"], "checks": checks}
                per_run["formal_pngs"][name] = {
                    "texture_sha256": file_sha(formal_texture),
                    "normal_sha256": file_sha(formal_normal),
                }
            if negative is None:
                negative = negative_controls(builder, work)
                if len(negative) != 5 or not all(negative.values()):
                    raise AssertionError(f"negative controls failed: {negative}")
            runs.append(per_run)

    if runs[0] != runs[1]:
        raise AssertionError("the two temporary source-clone runs differ")
    final = {
        "status": "source replay and formal cut outputs verified; not complete pose acceptance",
        "temporary_clones": 2,
        "same_replay_and_cut_results": True,
        "formal_character_metadata": verify_formal_metadata(),
        "runs": runs,
        "negative_controls": negative,
        "native_scope": "Seven non-dead wrist poses passed with zero failures across 6,720 samples; all eight poses total 7,680 samples. The dead-pose wrist check has 256 failed samples and the elbow check has 208 failed samples; this CPU verifier does not change those results.",
    }
    print(json.dumps(final, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
