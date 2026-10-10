"""Rebuild heavy_gunner's arm_lower override twice and verify adopted cut outputs."""
from __future__ import annotations

import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[4]
BUILDER_PATH = ROOT / "art_src/characters/heavy_gunner/wrist_repair/rebuild.py"
SOURCE_DIR = BUILDER_PATH.parent
FORMAL = ROOT / "art/characters/heavy_gunner"


def file_sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def png_sha(array: np.ndarray) -> str:
    from io import BytesIO
    stream = BytesIO()
    Image.fromarray(array).save(stream, format="PNG")
    return hashlib.sha256(stream.getvalue()).hexdigest()


def load_builder():
    spec = importlib.util.spec_from_file_location("heavy_gunner_wrist_rebuild", BUILDER_PATH)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


def load_cut_layers():
    path = ROOT / "tools/comfyui/cut_layers.py"
    import sys
    sys.path.insert(0, str(path.parent))
    spec = importlib.util.spec_from_file_location("heavy_gunner_public_cut_layers", path)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


def make_source_clone(builder, work: Path) -> None:
    source_root = SOURCE_DIR.parent
    for relative in builder.SOURCES:
        source = source_root / relative
        target = work / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)


def render_part(builder, cut_layers, fullcanvas: np.ndarray) -> dict:
    spec = json.loads((ROOT / "tools/comfyui/specs/heavy_gunner_side.json").read_text(encoding="utf-8"))
    scale = spec["tex_px_per_wp"] / spec["illustration_px_per_wp"]
    joints = {name: np.asarray(point, dtype=float) * scale for name, point in spec["joints"].items()}
    image = Image.fromarray(fullcanvas, "RGBA")
    transform = cut_layers.part_transform(image, spec["parts"]["arm_lower"], joints, scale)
    if transform is None:
        raise AssertionError("cut_layers returned an empty arm_lower")
    texture = cut_layers.render_part(image, transform, scale)
    normal = cut_layers.make_normal_map(texture)
    _, width, height, pivot = transform
    return {
        "texture": np.asarray(texture),
        "normal": np.asarray(normal),
        "size": [int(width), int(height)],
        "pivot": [round(float(value), 2) for value in pivot],
    }


def check_formal(character: dict, cut: dict) -> dict:
    texture_meta = character["textures"]["arm_lower"]
    expected_meta = {"file": "parts/arm_lower.png", "size": cut["size"], "pivot": cut["pivot"]}
    actual_meta = {"file": texture_meta["file"], "size": texture_meta["size"], "pivot": texture_meta["pivot"]}
    if actual_meta != expected_meta:
        raise AssertionError(f"formal arm_lower character.json metadata mismatch: {actual_meta}")
    diffuse_path = FORMAL / texture_meta["file"]
    normal_path = FORMAL / "parts/arm_lower_n.png"
    diffuse_hash, normal_hash = file_sha(diffuse_path), file_sha(normal_path)
    if diffuse_hash != png_sha(cut["texture"]):
        raise AssertionError("rebuilt diffuse PNG differs from formal arm_lower")
    if normal_hash != png_sha(cut["normal"]):
        raise AssertionError("rebuilt normal PNG differs from formal arm_lower_n")
    with Image.open(diffuse_path) as image:
        if image.mode != "RGBA" or image.size != tuple(cut["size"]):
            raise AssertionError(f"formal diffuse dimensions/mode mismatch: {image.mode} {image.size}")
        if not np.array_equal(np.asarray(image), cut["texture"]):
            raise AssertionError("formal diffuse pixels differ")
    with Image.open(normal_path) as image:
        if image.mode != "RGBA" or image.size != tuple(cut["size"]):
            raise AssertionError(f"formal normal dimensions/mode mismatch: {image.mode} {image.size}")
        if not np.array_equal(np.asarray(image), cut["normal"]):
            raise AssertionError("formal normal pixels differ")
    return {
        "character_metadata": actual_meta,
        "diffuse_sha256": diffuse_hash,
        "normal_sha256": normal_hash,
        "diffuse_pixel_match": True,
        "normal_pixel_match": True,
    }


def negative_controls(builder, work: Path) -> dict[str, bool]:
    output = work / "overrides/refined/arm_lower.png"
    before = output.read_bytes()
    results: dict[str, bool] = {}

    base_path = work / "base_rgba.png"
    base_bytes = base_path.read_bytes()
    base_path.write_bytes(base_bytes + b"corrupt")
    try:
        builder.build(work)
    except ValueError:
        results["corrupt_source_rejected_before_write"] = True
    else:
        raise AssertionError("corrupt source was accepted")
    finally:
        base_path.write_bytes(base_bytes)
    if output.read_bytes() != before:
        raise AssertionError("corrupt-source rejection changed the output")

    for result_name, mask_name, add_pixel in (
        ("owner_omission_rejected_before_write", "stage_P.png", False),
        ("extra_owner_pixel_rejected_before_write", "lower_07.png", True),
    ):
        with tempfile.TemporaryDirectory(prefix="heavy-wrist-negative-owner-") as temp:
            bad_owners = Path(temp)
            for name in builder.OWNERS:
                shutil.copy2(SOURCE_DIR / "owners" / name, bad_owners / name)
            path = bad_owners / mask_name
            mask = builder.binary_mask(path)
            y, x = np.argwhere(~mask if add_pixel else mask)[0]
            mask[y, x] = add_pixel
            Image.fromarray(mask.astype(np.uint8) * 255, "L").save(path)
            try:
                builder.build(work, bad_owners)
            except ValueError:
                results[result_name] = True
            else:
                raise AssertionError(f"mutated mask accepted: {result_name}")
        if output.read_bytes() != before:
            raise AssertionError(f"{result_name} changed the output")

    band_path = SOURCE_DIR / "owners/upper_band18.png"
    band = builder.binary_mask(band_path)
    _, _, stats, _ = cv2.connectedComponentsWithStats(band.astype(np.uint8), 8)
    x, y, width, height, _ = map(int, stats[1])
    interior = band[y + 1:y + height - 1, x + 1:x + width - 1]
    hy, hx = np.argwhere(interior)[len(np.argwhere(interior)) // 2]
    hole = band.copy()
    hole[y + 1 + hy, x + 1 + hx] = False
    try:
        builder.one_component_no_holes(hole, "negative-control band18 owner")
    except ValueError:
        results["one_pixel_enclosed_hole_rejected"] = True
    else:
        raise AssertionError("one-pixel hole passed the topology check")

    with tempfile.TemporaryDirectory(prefix="heavy-wrist-negative-band-") as temp:
        bad_owners = Path(temp)
        for name in builder.OWNERS:
            shutil.copy2(SOURCE_DIR / "owners" / name, bad_owners / name)
        path = bad_owners / "upper_band18.png"
        mask = builder.binary_mask(path)
        mask[tuple(np.argwhere(mask)[0])] = False
        Image.fromarray(mask.astype(np.uint8) * 255, "L").save(path)
        try:
            builder.build(work, bad_owners)
        except ValueError:
            results["corrupt_band_mask_rejected_before_write"] = True
        else:
            raise AssertionError("corrupt band18 mask was accepted")
    if output.read_bytes() != before:
        raise AssertionError("corrupt band-mask preflight changed the output")
    return results


def main() -> None:
    builder = load_builder()
    cut_layers = load_cut_layers()
    character_path = FORMAL / "character.json"
    character = json.loads(character_path.read_text(encoding="utf-8"))
    build_reports = []
    formal_report = None
    negatives = None
    for index in range(2):
        with tempfile.TemporaryDirectory(prefix=f"heavy-wrist-public-replay-{index + 1}-") as temp:
            work = Path(temp)
            make_source_clone(builder, work)
            report = builder.build(work)
            output_path = work / "overrides/refined/arm_lower.png"
            with Image.open(output_path) as image:
                fullcanvas = np.asarray(image).copy()
            if builder.sha(fullcanvas.tobytes()) != builder.TARGET_PIXELS:
                raise AssertionError("temporary source clone failed decoded RGBA target")
            cut = render_part(builder, cut_layers, fullcanvas)
            if cut["size"] != builder.TARGET_SIZE or cut["pivot"] != builder.TARGET_PIVOT:
                raise AssertionError(f"cut size/pivot mismatch: {cut['size']} {cut['pivot']}")
            if png_sha(cut["texture"]) != builder.TARGET_PART_PNG:
                raise AssertionError("cut diffuse differs from pinned target SHA")
            if png_sha(cut["normal"]) != builder.TARGET_NORMAL_PNG:
                raise AssertionError("cut normal differs from pinned target SHA")
            current_formal = check_formal(character, cut)
            if formal_report is not None and current_formal != formal_report:
                raise AssertionError("formal outputs changed between the two source replays")
            formal_report = current_formal
            if negatives is None:
                negatives = negative_controls(builder, work)
                if len(negatives) != 5 or not all(negatives.values()):
                    raise AssertionError(f"negative control failure: {negatives}")
            build_reports.append({
                "source_replay": {"opaque_pixels": report["arm_lower"]["opaque_pixels"], "decoded_rgba_sha256": report["arm_lower"]["decoded_rgba_sha256"]},
                "fullcanvas_png_sha256": file_sha(output_path),
                "cut_size": cut["size"],
                "cut_pivot": cut["pivot"],
                "formal": current_formal,
            })
    if build_reports[0] != build_reports[1]:
        raise AssertionError("temporary source-clone rebuilds are not identical")
    print(json.dumps({
        "status": "two source-only CPU rebuilds match formal arm_lower diffuse/normal and metadata",
        "temporary_builds": build_reports,
        "same_two_builds": True,
        "negative_controls": negatives,
        "native_limit": "This verifier covers source replay and cut output only. Final 14-joint Forward+ acceptance must be reported separately by root; no native pass is inferred here.",
    }, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
