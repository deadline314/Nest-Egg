#!/usr/bin/env python3
"""CPU-only link, source-pixel, mesh-topology, and evidence validation."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re

import numpy as np
from PIL import Image

BUNDLE = Path(__file__).resolve().parent
PROJECT = BUNDLE.parents[3]
SOURCE_SHA = "74044963a9ff8d2bc47b5bceed04d8763b856b252069c4817c7f0685b1bd33ed"
PREFIX = "pm/Nest-Egg/attachments/NE-222-native-pose/"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def main() -> None:
    source_path = BUNDLE / "source/rin_kneel_color_alpha_22297_0.png"
    assert sha(source_path) == SOURCE_SHA, "pinned 22297 source hash changed"
    source_image = Image.open(source_path)
    assert source_image.mode == "RGBA" and source_image.size == (1440, 736)
    source = np.asarray(source_image)
    retained = source[:, :, 3] >= 40
    alpha = source[:, :, 3]
    assert int(np.count_nonzero(alpha == 0)) == 363146
    assert int(np.count_nonzero(alpha == 1)) == 481772
    assert int(retained.sum()) == 211990

    owner_manifest = read_json(BUNDLE / "generated/ownership/manifest-v3.json")
    names = ("pelvis", "front_thigh", "front_calf", "front_boot", "back_thigh", "back_calf", "back_boot")
    mask_stack = []
    for name in names:
        mask = np.asarray(Image.open(BUNDLE / f"generated/ownership/masks/{name}.png").convert("L")) > 0
        assert mask.shape == retained.shape
        assert not np.any(mask & ~retained), f"{name} owns alpha below the established 40 floor"
        mask_stack.append(mask)
        image = np.asarray(Image.open(BUNDLE / f"generated/registration/textures/{name}.png").convert("RGBA"))
        normal = Image.open(BUNDLE / f"generated/registration/textures/{name}_n.png")
        assert image.shape[2] == 4 and image.shape[:2] == (normal.height, normal.width)
        assert image.shape[2] == 4
        if name in ("pelvis", "front_boot", "back_boot"):
            assert (BUNDLE / f"generated/registration/textures/{name}_glow.png").is_file()
    owners = np.stack(mask_stack).sum(axis=0)
    assert np.array_equal(owners == 1, retained), "source pixels are missing or multiply owned"
    assert int(retained.sum()) == 211990
    assert owner_manifest["status"] == "PRIVATE_V3_SEVEN_PART_SOURCE_OWNERSHIP_PROPOSAL_NOT_ACCEPTED"

    bbox = (656, 129, 1191, 460)
    x0, y0, x1, y1 = bbox
    grid = read_json(BUNDLE / "generated/shared_mesh/shared_grid.json")
    assert grid["common_bbox_xyxy_half_open"] == list(bbox)
    assert grid["grid"]["columns"] == 5 and grid["grid"]["rows"] == 5
    assert len(grid["grid"]["points_source_xy"]) == 25
    assert len(grid["grid"]["triangles"]) == 96
    for owner in ("front_thigh", "front_calf"):
        mask = mask_stack[names.index(owner)][y0:y1, x0:x1] & retained[y0:y1, x0:x1]
        expected = np.zeros((y1 - y0, x1 - x0, 4), dtype=np.uint8)
        source_crop = source[y0:y1, x0:x1]
        expected[mask] = source_crop[mask]
        actual = np.asarray(Image.open(BUNDLE / f"generated/shared_mesh/{owner}_common_bbox.png").convert("RGBA"))
        normal = Image.open(BUNDLE / f"generated/shared_mesh/{owner}_common_bbox_n.png")
        assert actual.shape == expected.shape and np.array_equal(actual, expected), f"{owner} common atlas changed source pixels"
        assert normal.size == (x1 - x0, y1 - y0)

    texture_defs = read_json(BUNDLE / "generated/registration/textures.json")
    for definition in texture_defs.values():
        file_path = definition["file"].replace("\\", "/")
        resolved = (PROJECT / "art/characters/rin" / file_path).resolve()
        assert resolved.is_file(), f"registration texture link is missing: {file_path}"
        if "glow" in definition:
            glow = (PROJECT / "art/characters/rin" / definition["glow"]).resolve()
            assert glow.is_file(), f"registration glow link is missing: {definition['glow']}"

    fixture = read_json(BUNDLE / "formal_pose_data.json")
    pose = fixture["pose_parts"]["kneel_22297_registration_v3_fixture"]
    assert len(pose["bind_pose"]) == 20 and len(pose["parts"]) == 4
    assert {part["slot"] for part in pose["parts"]} == {
        "armor_thigh", "thigh_dmg", "armor_calf", "calf_dmg"
    }
    for definition in fixture["textures"].values():
        path = (PROJECT / "art/characters/rin" / definition["file"]).resolve()
        assert path.is_file(), f"formal fixture texture link is missing: {definition['file']}"
        assert path.with_name(path.stem + "_n.png").is_file(), "formal fixture normal link is missing"

    for scene_name in ("capture_shared_bind.tscn", "formal_pose_native.tscn"):
        scene = (BUNDLE / scene_name).read_text(encoding="utf-8")
        for res_path in re.findall(r'res://[^"\s)]+', scene):
            project_path = (PROJECT / res_path.removeprefix("res://")).resolve()
            assert project_path.is_file(), f"scene resource link is missing: {res_path}"
    for script_name in ("capture_shared_bind.gd", "formal_pose_native.gd"):
        script = (BUNDLE / script_name).read_text(encoding="utf-8")
        assert ".godot/" not in script and ".godot\\" not in script, f"private path remains in {script_name}"

    native_report = read_json(BUNDLE / "evidence/formal-native-v2/report.json")
    failed_native_report = read_json(BUNDLE / "evidence/failed/formal-native-v1/capture-report.json")
    joint_baseline = read_json(BUNDLE / "evidence/baseline-joint-check/report.json")
    assert native_report["samples"] == 480 and native_report["failed_samples"] == 0
    assert len(list((BUNDLE / "evidence/formal-native-v2").glob("*.png"))) == 480
    assert len(list((BUNDLE / "evidence/baseline-joint-check").glob("*.png"))) == 480
    assert len(list((BUNDLE / "evidence/failed/round44-underlap-attempt").glob("*.png"))) == 480
    assert joint_baseline["samples"] == 480 and joint_baseline["failed_samples"] == 64
    assert read_json(BUNDLE / "evidence/failed/round44-underlap-attempt/report.json")["failed_samples"] == 46
    assert failed_native_report["viewport_used"] is True and failed_native_report["acceptance"] is False
    final_capture = read_json(BUNDLE / "evidence/formal-native-v2/capture-report.json")
    assert final_capture["viewport_used"] is True and final_capture["acceptance"] is False
    assert final_capture["rendering_method"] == "forward_plus"
    assert final_capture["checks"] == 2018 and final_capture["failures"] == []
    assert (BUNDLE / "evidence/FAILED-HISTORY.json").is_file()

    manifest_path = BUNDLE / "bundle-manifest.json"
    manifest = read_json(manifest_path)
    recorded = manifest["files_sha256"]
    actual_files = {
        path.relative_to(BUNDLE).as_posix(): sha(path)
        for path in sorted(BUNDLE.rglob("*"))
        if path.is_file() and path != manifest_path and "__pycache__" not in path.parts and path.suffix not in (".pyc", ".import", ".uid")
    }
    assert recorded == actual_files, "bundle manifest is stale or incomplete"
    assert manifest["source_sha256"] == SOURCE_SHA
    assert manifest["native_capture"]["joint_failures"] == 0

    print(json.dumps({"status": "CPU_BUNDLE_LINK_AND_SOURCE_CHECKS_PASS_NOT_RENDER_ACCEPTANCE",
                      "source_sha256": SOURCE_SHA, "source_alpha_ge40_pixels": int(retained.sum()),
                      "exclusive_owners": len(names), "common_grid_vertices": 25,
                      "common_grid_triangles": 32, "baseline_joint_failures": 64,
                      "round44_failed_samples": 46, "native_capture_samples": 480,
                      "native_capture_failures": 0, "acceptance": False}, indent=2))


if __name__ == "__main__":
    main()
