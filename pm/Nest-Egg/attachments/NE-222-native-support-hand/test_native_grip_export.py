"""Exercise the real cut_layers.main with isolated outputs and pinned Rin inputs."""
from __future__ import annotations

import contextlib
import copy
import hashlib
import importlib
import io
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[4]
OUT = ROOT / ".godot/ne222-native-grip-export-review"
WORK = ROOT / "art_src/characters/rin2"
SPEC_PATH = ROOT / "tools/comfyui/specs/rin_side.json"
REBUILD_DIR = ROOT / "art_src/characters/rin_support_grip_22308"
REBUILD = REBUILD_DIR / "rebuild.py"
MANIFEST_PATH = REBUILD_DIR / "manifest.json"
SOURCE = REBUILD_DIR / "overrides/hand_back.png"
RAW = REBUILD_DIR / "source/rin_ne222_support_context_22308_0.png"
MASK = REBUILD_DIR / "sam/support_hand.png"
CHARACTER = ROOT / "art/characters/rin/character.json"
EXPECTED_CUT_HASH = "5c662add546e3ccc0b23f1e0e8a817f8d86608a4e53dc923cf47e8b7cdf64154"
EXPECTED_GRIP_HASH = "d4da7778be1c6df46797795d2aff09799bb928fa645df278afe16825a2ee4f89"
EXPECTED_RAW_HASH = "993fed5e839300642bb0e0ce9ba841de8d02c6ea7529ef750ecfce1d38d30c3a"
EXPECTED_MASK_HASH = "70a724378cb2f452be7465f845af5ce26db83cc6295ebd88a25316900a888baa"
EXPECTED_SIZE = [226, 142]
EXPECTED_PIVOT = [26.0822, 25.9259]
EXPECTED_SCALE = 0.018283541156251144
EXPECTED_GRIP_OFFSET = [1.67408, -0.01506]
CHECKS = 0


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def check(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if not condition:
        raise AssertionError(message)


def write_json(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2, allow_nan=True) + "\n", encoding="utf-8", newline="\n")


def snapshot_tree(path: Path) -> dict[str, str]:
    if not path.exists():
        return {}
    return {str(file.relative_to(path)): digest(file.read_bytes()) for file in sorted(path.rglob("*")) if file.is_file()}


def snapshot_outputs(char_dir: Path, rig_path: Path) -> dict:
    return {"character": snapshot_tree(char_dir), "rig": digest(rig_path.read_bytes()) if rig_path.exists() else None}


def invoke_main(cut_layers, spec_path: Path, char_dir: Path, rig_path: Path) -> str:
    old_argv = sys.argv
    output = io.StringIO()
    try:
        sys.argv = ["cut_layers.py", "--spec", str(spec_path), "--work", str(WORK),
                    "--char", str(char_dir), "--rig", str(rig_path)]
        with contextlib.redirect_stdout(output):
            cut_layers.main()
    finally:
        sys.argv = old_argv
    return output.getvalue()


def verify_registered_crop(spec: dict) -> dict:
    config = spec["native_grips"]["hand_left_grip"]
    check(config["sha256"] == EXPECTED_GRIP_HASH and digest(SOURCE.read_bytes()) == EXPECTED_GRIP_HASH,
          "native source file agrees with current spec SHA")
    check(config["size"] == EXPECTED_SIZE and config["pivot"] == EXPECTED_PIVOT
          and config["texture_scale"] == EXPECTED_SCALE, "spec exports the registered size/pivot/density")
    with Image.open(SOURCE) as native_image:
        check(native_image.mode == "RGBA" and list(native_image.size) == EXPECTED_SIZE,
              "registered native attachment is RGBA 226x142")
        native_pixels = np.asarray(native_image, dtype=np.uint8).copy()

    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    bbox = manifest["sam"]["bbox_xyxy_exclusive"]
    check(bbox == [267, 358, 493, 500], "registered owner crop uses the pinned half-open bbox")
    check(digest(RAW.read_bytes()) == EXPECTED_RAW_HASH, "raw generation source hash is pinned")
    check(digest(MASK.read_bytes()) == EXPECTED_MASK_HASH, "SAM source owner hash is pinned")
    with Image.open(RAW) as raw_image, Image.open(MASK) as mask_image:
        check(raw_image.mode == "RGBA" and raw_image.size == (768, 768), "raw image is pinned native RGBA")
        check(mask_image.mode == "RGB" and mask_image.size == (768, 768), "SAM mask is pinned native RGB")
        mask_rgb = np.asarray(mask_image, dtype=np.uint8)
        check(np.array_equal(mask_rgb[:, :, 0], mask_rgb[:, :, 1])
              and np.array_equal(mask_rgb[:, :, 0], mask_rgb[:, :, 2]), "SAM channels agree")
        expected = np.asarray(raw_image.crop(tuple(bbox)), dtype=np.uint8).copy()
        owner = np.asarray(mask_image.getchannel("R").crop(tuple(bbox)), dtype=np.uint8)
        expected[:, :, 3] = owner
    check(expected.shape == (142, 226, 4) and np.array_equal(native_pixels, expected),
          "native grip pixels exactly equal the pinned raw crop with SAM alpha")
    check(int(np.count_nonzero(native_pixels[:, :, 3])) == manifest["sam"]["opaque_pixels"] == 23399,
          "native crop keeps exactly the registered owner pixel count")
    return {"source_sha256": EXPECTED_GRIP_HASH, "raw_sha256": EXPECTED_RAW_HASH,
            "mask_sha256": EXPECTED_MASK_HASH, "size": EXPECTED_SIZE, "pivot": EXPECTED_PIVOT,
            "texture_scale": EXPECTED_SCALE, "owner_pixels": 23399, "bbox_xyxy": bbox}


def validate_positive_outputs(native_dir: Path, second_native_dir: Path, control_dir: Path,
                              native_rig: Path, second_rig: Path, control_rig: Path,
                              current_character: dict, native_spec: dict) -> dict:
    native_parts = native_dir / "parts"
    second_parts = second_native_dir / "parts"
    control_parts = control_dir / "parts"
    native_char = json.loads((native_dir / "character.json").read_text(encoding="utf-8"))
    second_char = json.loads((second_native_dir / "character.json").read_text(encoding="utf-8"))
    control_char = json.loads((control_dir / "character.json").read_text(encoding="utf-8"))
    native_rig_bytes, second_rig_bytes, control_rig_bytes = native_rig.read_bytes(), second_rig.read_bytes(), control_rig.read_bytes()

    native_png = native_parts / "hand_left_grip.png"
    expected_bytes = SOURCE.read_bytes()
    check(native_png.read_bytes() == expected_bytes, "cut_layers writes the native PNG byte-for-byte")
    check((second_parts / "hand_left_grip.png").read_bytes() == expected_bytes,
          "second independent main run also writes identical native PNG bytes")
    with Image.open(native_png) as exported:
        check(exported.mode == "RGBA" and list(exported.size) == EXPECTED_SIZE,
              "exported grip keeps native 226x142 RGBA dimensions")

    texture = native_char["textures"]["hand_left_grip"]
    check(texture["size"] == EXPECTED_SIZE and texture["pivot"] == EXPECTED_PIVOT
          and texture["texture_scale"] == EXPECTED_SCALE, "character JSON exports exact native size, pivot and texture_scale")
    current_texture = current_character["textures"].get("hand_left_grip", {})
    native_metadata_diff = {"before": current_texture, "after": texture}

    native_grasp = [part for part in native_char["parts"] if part.get("grip_texture") == "hand_left_grip"]
    control_grasp = [part for part in control_char["parts"] if part.get("grip_texture") == "hand_left_grip"]
    current_grasp = [part for part in current_character["parts"] if part.get("grip_texture") == "hand_left_grip"]
    check(len(native_grasp) == len(control_grasp) == len(current_grasp) == 1, "exactly one actual use carries the legacy grip attachment")
    check(native_grasp[0]["grip_offset"] == control_grasp[0]["grip_offset"], "adding native_grips leaves cut_layers grasp/grip_offset unchanged")
    check(native_grasp[0]["grip_offset"] == EXPECTED_GRIP_OFFSET == current_grasp[0]["grip_offset"],
          "export keeps Rin's existing hand_back grip_offset exactly")

    native_textures = dict(native_char["textures"])
    control_textures = dict(control_char["textures"])
    native_textures.pop("hand_left_grip")
    control_textures.pop("hand_left_grip")
    check(native_textures == control_textures, "all other character texture metadata is identical to no-native-grip fixture")
    check(native_char["parts"] == control_char["parts"], "all part metadata is identical to no-native-grip fixture")
    check(native_rig_bytes == control_rig_bytes == second_rig_bytes,
          "both native runs and no-native control produce byte-identical rig JSON")
    check(native_char == second_char, "two native main runs produce byte-identical character metadata")

    native_files = {p.name for p in native_parts.glob("*.png")}
    control_files = {p.name for p in control_parts.glob("*.png")}
    second_files = {p.name for p in second_parts.glob("*.png")}
    check(native_files == control_files == second_files, "native and control fixtures emit the same part PNG set")
    identical_others = []
    for name in sorted(native_files - {"hand_left_grip.png"}):
        a, b, c = [(path / name).read_bytes() for path in (native_parts, control_parts, second_parts)]
        check(a == b == c, f"non-grip part texture is byte-identical: {name}")
        identical_others.append({"name": name, "sha256": digest(a)})
    check(not (native_parts / "hand_left_grip_n.png").exists(),
          "cut_layers.main does not silently synthesize or replace the separate normal map")
    return {"native_grip_file_sha256": digest(native_png.read_bytes()),
            "character_metadata_before_after": native_metadata_diff,
            "legacy_grip_offset": native_grasp[0]["grip_offset"],
            "other_part_texture_count": len(identical_others), "other_part_textures": identical_others,
            "other_character_texture_metadata_identical": True, "part_metadata_identical": True,
            "rig_sha256": digest(native_rig_bytes), "no_grip_normal_map_written_by_main": True}


def assert_failure_is_transactional(cut_layers, spec: dict, mutation, label: str,
                                    char_dir: Path, rig_path: Path, spec_path: Path) -> dict:
    broken = copy.deepcopy(spec)
    mutation(broken)
    write_json(spec_path, broken)
    before = snapshot_outputs(char_dir, rig_path)
    try:
        invoke_main(cut_layers, spec_path, char_dir, rig_path)
        raise AssertionError(f"negative {label} unexpectedly succeeded")
    except ValueError as error:
        message = str(error)
    after = snapshot_outputs(char_dir, rig_path)
    check(before == after, f"invalid {label} leaves existing character, rig, and parts bytes unchanged")
    check(not (char_dir / "parts.tmp").exists(), f"invalid {label} fails before creating parts.tmp")
    return {"case": label, "error": message, "existing_outputs_unchanged": True}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    sys.path.insert(0, str(ROOT / "tools/comfyui"))
    cut_layers = importlib.import_module("cut_layers")
    spec = json.loads(SPEC_PATH.read_text(encoding="utf-8"))
    current_character = json.loads(CHARACTER.read_text(encoding="utf-8"))
    spec_hash = digest(SPEC_PATH.read_bytes())
    cut_hash = digest((ROOT / "tools/comfyui/cut_layers.py").read_bytes())
    rebuild_text = REBUILD.read_text(encoding="utf-8")
    check(cut_hash == EXPECTED_CUT_HASH, "current cut_layers.py matches the pinned support-grip rebuild helper SHA")
    check(f'"cut_layers": (ROOT / "tools/comfyui/cut_layers.py", "{EXPECTED_CUT_HASH}")' in rebuild_text,
          "source rebuild records the same cut_layers.py hash")
    check(spec["native_grips"]["hand_left_grip"]["source"] == "art_src/characters/rin_support_grip_22308/overrides/hand_back.png",
          "Rin side spec names the registered native support-hand source")
    crop = verify_registered_crop(spec)

    runs = OUT / "runs"
    native1, native2, control = runs / "native-1", runs / "native-2", runs / "without-native"
    for directory in (native1, native2, control):
        directory.mkdir(parents=True, exist_ok=True)
    native1_spec = OUT / "spec-native-1.json"
    native2_spec = OUT / "spec-native-2.json"
    control_spec = OUT / "spec-without-native.json"
    write_json(native1_spec, spec)
    write_json(native2_spec, spec)
    control_value = copy.deepcopy(spec)
    control_value.pop("native_grips")
    write_json(control_spec, control_value)
    native1_rig, native2_rig, control_rig = native1 / "rig.json", native2 / "rig.json", control / "rig.json"
    native1_log = invoke_main(cut_layers, native1_spec, native1, native1_rig)
    native2_log = invoke_main(cut_layers, native2_spec, native2, native2_rig)
    control_log = invoke_main(cut_layers, control_spec, control, control_rig)
    positive = validate_positive_outputs(native1, native2, control, native1_rig, native2_rig, control_rig,
                                         current_character, spec)

    # Seed a stable successful output tree, then exercise every config rejection
    # against it. load_native_grips runs before work/parts.tmp are touched.
    target_char, target_rig = native1, native1_rig
    cases = []
    cases.append(assert_failure_is_transactional(cut_layers, spec,
        lambda d: d["native_grips"]["hand_left_grip"].update(sha256="0" * 64),
        "bad source hash", target_char, target_rig, OUT / "negative-bad-hash.json"))
    cases.append(assert_failure_is_transactional(cut_layers, spec,
        lambda d: d["native_grips"]["hand_left_grip"].update(size=[225, 142]),
        "wrong source size", target_char, target_rig, OUT / "negative-wrong-size.json"))
    cases.append(assert_failure_is_transactional(cut_layers, spec,
        lambda d: d["native_grips"]["hand_left_grip"].update(texture_scale=float("nan")),
        "nonfinite density", target_char, target_rig, OUT / "negative-nonfinite-scale.json"))
    cases.append(assert_failure_is_transactional(cut_layers, spec,
        lambda d: d["native_grips"]["hand_left_grip"].update(texture_scale=0.0),
        "zero density", target_char, target_rig, OUT / "negative-zero-scale.json"))
    cases.append(assert_failure_is_transactional(cut_layers, spec,
        lambda d: d["native_grips"]["hand_left_grip"].update(source="outside/source.png"),
        "invalid source path", target_char, target_rig, OUT / "negative-invalid-path.json"))
    def foreign_slot(d: dict) -> None:
        config = d["native_grips"].pop("hand_left_grip")
        d["native_grips"] = {"foreign_slot": config}
    cases.append(assert_failure_is_transactional(cut_layers, spec, foreign_slot,
        "foreign unreferenced slot", target_char, target_rig, OUT / "negative-foreign-slot.json"))

    report = {
        "status": "CPU_EXPORT_CONTRACT_PASS_NOT_NATIVE_VISUAL_OR_FORMAL_ACCEPTANCE",
        "checks": CHECKS,
        "inputs": {"cut_layers_sha256": cut_hash, "cut_layers_sha_pinned_by_rebuild": EXPECTED_CUT_HASH,
                   "rin_side_spec_sha256": spec_hash, "source_manifest_sha256": digest(MANIFEST_PATH.read_bytes()),
                   "rebuild_script_sha256": digest(REBUILD.read_bytes()), **crop},
        "positive_export": positive,
        "negative_controls": cases,
        "main_logs": {"native_1": native1_log.splitlines()[-1:] if native1_log else [],
                      "native_2": native2_log.splitlines()[-1:] if native2_log else [],
                      "without_native": control_log.splitlines()[-1:] if control_log else []},
        "meaning": "Executed the current production cut_layers.main against the actual Rin side spec and source work tree, writing all outputs only under .godot. No source or formal character files were written. Normal-map regeneration is a separate step and was not tested.",
    }
    report_path = OUT / "report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2, allow_nan=False) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps({"status": report["status"], "checks": CHECKS,
                      "native_sha256": positive["native_grip_file_sha256"],
                      "legacy_grip_offset": positive["legacy_grip_offset"],
                      "other_part_textures": positive["other_part_texture_count"],
                      "negative_cases": len(cases), "report": str(report_path)}, indent=2))


if __name__ == "__main__":
    main()
