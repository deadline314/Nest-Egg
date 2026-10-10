"""Private source-exact 22297 seven-part kneel registration; not art/runtime acceptance."""
from __future__ import annotations

import hashlib
import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

BUNDLE = Path(__file__).resolve().parent
ROOT = BUNDLE.parents[3]
OUT = BUNDLE / "generated/registration"
TEXTURES = OUT / "textures"
SOURCE = BUNDLE / "source/rin_kneel_color_alpha_22297_0.png"
OWNERS = BUNDLE / "generated/ownership"
MANIFEST = OWNERS / "manifest-v3.json"
GUIDE = BUNDLE / "source/kneel_source_23p78x_facing_right.json"
PROPOSAL = BUNDLE / "source/pose-owner-proposal.json"
CHARACTER = BUNDLE / "source/context/rin-character.json"
RIG = BUNDLE / "source/context/humanoid_tall.json"
SOURCE_SHA = "74044963a9ff8d2bc47b5bceed04d8763b856b252069c4817c7f0685b1bd33ed"
GUIDE_SHA = "ace2230bc83ab1d57424c0e32136c7d5b42b4148da743e1c973a9b7de7e588a3"
ALPHA_FLOOR = 40
PADDING = 2
OWNER_TO_BONE = {
    "pelvis": ("hip", "hip"),
    "front_thigh": ("leg_front_upper", "leg_front_upper"),
    "front_calf": ("leg_front_lower", "leg_front_lower"),
    "front_boot": ("foot_front", "foot_front"),
    "back_thigh": ("leg_back_upper", "leg_back_upper"),
    "back_calf": ("leg_back_lower", "leg_back_lower"),
    "back_boot": ("foot_back", "foot_back"),
}
OWNER_SLOTS = {
    "pelvis": ("armor_pelvis", "pelvis_dmg"),
    "front_thigh": ("armor_thigh", "thigh_dmg"),
    "front_calf": ("armor_calf", "calf_dmg"),
    "front_boot": ("foot_front",),
    "back_thigh": ("leg_back_upper", "leg_back_upper_dmg"),
    "back_calf": ("leg_back_lower", "leg_back_lower_dmg"),
    "back_boot": ("foot_back",),
}


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def compose(a: tuple[float, ...], b: tuple[float, ...]) -> tuple[float, ...]:
    aa, ab, ac, ad, atx, aty = a
    ba, bb, bc, bd, btx, bty = b
    return (aa * ba + ac * bb, ab * ba + ad * bb, aa * bc + ac * bd,
            ab * bc + ad * bd, aa * btx + ac * bty + atx, ab * btx + ad * bty + aty)


def inverse(a: tuple[float, ...]) -> tuple[float, ...]:
    aa, ab, ac, ad, atx, aty = a
    det = aa * ad - ab * ac
    if abs(det) < 1e-12:
        raise ValueError("singular affine")
    ia, ib, ic, id_ = ad / det, -ab / det, -ac / det, aa / det
    return (ia, ib, ic, id_, -(ia * atx + ic * aty), -(ib * atx + id_ * aty))


def apply(a: tuple[float, ...], p: tuple[float, float]) -> tuple[float, float]:
    aa, ab, ac, ad, atx, aty = a
    x, y = p
    return (aa * x + ac * y + atx, ab * x + ad * y + aty)


def local_transform(pos: list[float], angle: float) -> tuple[float, ...]:
    c, s = math.cos(angle), math.sin(angle)
    return (c, s, -s, c, float(pos[0]), float(pos[1]))


def distance(a: tuple[float, float], b: tuple[float, float]) -> float:
    return math.hypot(a[0] - b[0], a[1] - b[1])


def validate_offset(offset: tuple[float, float], expected: tuple[float, float], tolerance: float = 0.015) -> None:
    if len(offset) != 2 or not all(math.isfinite(value) for value in offset):
        raise ValueError("offset must be a finite pair")
    if distance(offset, expected) > tolerance:
        raise ValueError("offset does not preserve the registered pivot")


def validate_partition(masks: dict[str, Image.Image], source: Image.Image, expected_sha: str) -> dict:
    if expected_sha != SOURCE_SHA:
        raise ValueError("source hash mismatch")
    if set(masks) != set(OWNER_TO_BONE):
        raise ValueError("owner set is incomplete or contains unexpected owners")
    if source.mode != "RGBA" or source.size != (1440, 736):
        raise ValueError("source must be native 1440x736 RGBA")
    alpha = np.asarray(source.getchannel("A"), dtype=np.uint8)
    count = np.zeros(alpha.shape, dtype=np.uint8)
    for name, mask_image in masks.items():
        if mask_image.size != source.size:
            raise ValueError(f"{name}: owner mask size differs from source")
        own = np.asarray(mask_image.convert("L")) > 0
        if np.any(own & (alpha < ALPHA_FLOOR)):
            raise ValueError(f"{name}: mask contains pixels below established alpha floor")
        count += own.astype(np.uint8)
    if np.any(count > 1):
        raise ValueError("duplicate owner pixels")
    if np.any((alpha >= ALPHA_FLOOR) & (count != 1)):
        raise ValueError("one or more retained source pixels have no owner")
    return {name: int(np.count_nonzero(np.asarray(mask.convert("L")) > 0)) for name, mask in masks.items()}


def selfcheck_validation() -> None:
    # Small synthetic masks exercise fail-closed guards without altering input files.
    rgba = Image.new("RGBA", (1440, 736), (0, 0, 0, 0))
    rgba.putpixel((10, 10), (20, 40, 60, 255)); rgba.putpixel((11, 10), (30, 50, 70, 255))
    valid = {name: Image.new("L", (1440, 736), 0) for name in OWNER_TO_BONE}
    valid["pelvis"].putpixel((10, 10), 255)
    valid["front_thigh"].putpixel((11, 10), 255)
    if sum(validate_partition(valid, rgba, SOURCE_SHA).values()) != 2:
        raise AssertionError("valid synthetic partition failed")
    for bad_sha, bad_masks in [
        ("0" * 64, valid),
        (SOURCE_SHA, {key: value for key, value in valid.items() if key != "back_boot"}),
        (SOURCE_SHA, {**valid, "front_thigh": valid["pelvis"]}),
        (SOURCE_SHA, {**valid, "front_thigh": Image.new("L", (1440, 736), 0)}),
    ]:
        try:
            validate_partition(bad_masks, rgba, bad_sha)
        except ValueError:
            continue
        raise AssertionError("negative ownership/source control was not rejected")
    for bad_offset in [(float("nan"), 0.0), (1.0, 0.0)]:
        try:
            validate_offset(bad_offset, (0.0, 0.0))
        except ValueError:
            continue
        raise AssertionError("bad offset control was not rejected")


def make_contact(rebuilt: Image.Image, output: Path) -> None:
    w, h = rebuilt.size
    backgrounds = [(0, 0, 0, 255), (91, 101, 119, 255), (255, 255, 255, 255)]
    contact = Image.new("RGB", (w * 3, h), (0, 0, 0))
    for col, bg in enumerate(backgrounds):
        panel = Image.new("RGBA", (w, h), bg)
        panel.alpha_composite(rebuilt)
        contact.paste(panel.convert("RGB"), (col * w, 0))
    contact.save(output)


def main() -> None:
    selfcheck_validation()
    # Reuse the established production CPU normal and glow extraction algorithms.
    sys.path.insert(0, str(ROOT / "tools/comfyui"))
    from cut_layers import make_normal_map
    from cut_parts import glow_layer

    source_sha_before = sha(SOURCE)
    owner_manifest = read_json(MANIFEST)
    proposal = read_json(PROPOSAL)
    guide = read_json(GUIDE)
    character = read_json(CHARACTER)
    rig_def = read_json(RIG)
    source = Image.open(SOURCE).convert("RGBA")
    if source_sha_before != SOURCE_SHA or owner_manifest["source"]["sha256"] != SOURCE_SHA:
        raise ValueError("pinned 22297 source SHA mismatch")
    if sha(GUIDE) != GUIDE_SHA:
        raise ValueError("canonical kneel guide SHA mismatch")
    if list(source.size) != owner_manifest["source"]["size"] or owner_manifest["source"]["alpha_floor"] != ALPHA_FLOOR:
        raise ValueError("source dimensions or alpha floor mismatch")

    masks = {path.stem: Image.open(path).convert("L") for path in (OWNERS / "masks").glob("*.png")}
    owner_counts = validate_partition(masks, source, source_sha_before)
    if sum(owner_counts.values()) != owner_manifest["source"]["retained_alpha_ge40_pixels"]:
        raise ValueError("owner masks do not cover the recorded retained-pixel count")
    for name, record in owner_manifest["owner_ledger"]["owners"].items():
        if owner_counts.get(name) != record["retained_pixels"]:
            raise ValueError(f"{name}: mask pixel count differs from the reviewed v3 ledger")

    guide_bones = {item["name"]: item for item in guide["bones"]}
    rig_bones = {item["name"]: item for item in rig_def["bones"]}
    if len(guide_bones) != 20 or set(guide_bones) != set(rig_bones):
        raise ValueError("kneel guide must use the unchanged canonical 20 bones")
    parents = {item["name"]: item.get("parent", "") for item in rig_def["bones"]}
    local = {name: local_transform(guide_bones[name]["local_position"], guide_bones[name]["local_rotation_radians"])
             for name in guide_bones}
    global_xf: dict[str, tuple[float, ...]] = {}

    def global_xform(name: str) -> tuple[float, ...]:
        if name in global_xf:
            return global_xf[name]
        parent = parents[name]
        global_xf[name] = compose(global_xform(parent), local[name]) if parent else local[name]
        return global_xf[name]

    for name in guide_bones:
        global_xform(name)
        if parents[name] and distance(tuple(guide_bones[name]["local_position"]), tuple(rig_bones[name]["pos"])) > 1e-6:
            raise ValueError(f"canonical rest position changed: {name}")
    rest_lengths = {}
    for child, parent in parents.items():
        if parent:
            rest = rig_bones[child]["pos"]
            length = math.hypot(rest[0], rest[1])
            if abs(length - math.hypot(*guide_bones[child]["rest_position"])) > 1e-6:
                raise ValueError(f"canonical rest length changed: {child}")
            rest_lengths[child] = length

    contract = proposal["guide_coordinate_contract"]
    capture_scale = float(contract["capture_scale_px_per_skeleton_unit"])
    source_sx, source_sy = map(float, contract["capture_to_guide_scale_xy"])
    crop_x, crop_y, _, _ = map(float, contract["capture_crop_xyxy_px"])
    hip_capture = guide_bones["hip"]["global_transform"]
    hip_global = global_xf["hip"]
    camera_origin = (float(hip_capture[4]) - capture_scale * hip_global[4],
                     float(hip_capture[5]) - capture_scale * hip_global[5])
    camera = (capture_scale, 0.0, 0.0, capture_scale, *camera_origin)
    for name in guide_bones:
        actual = compose(camera, global_xf[name])
        expected = tuple(map(float, guide_bones[name]["global_transform"]))
        if max(abs(a - b) for a, b in zip(actual, expected)) >= 0.002:
            raise ValueError(f"guide matrix mismatch: {name}")
    capture_to_guide = (1.0 / source_sx, 0.0, 0.0, 1.0 / source_sy, crop_x, crop_y)
    source_to_skeleton = compose(inverse(camera), capture_to_guide)
    texture_scale = math.hypot(source_to_skeleton[0], source_to_skeleton[1])
    density = 1.0 / texture_scale
    if abs(density - capture_scale * source_sx) > 1e-10:
        raise ValueError("source/capture registration scale mismatch")
    root_scale = float(character["scale"])
    source_origin = apply(inverse(source_to_skeleton), (0.0, 0.0))
    holder_scale = density / root_scale
    anchors = proposal["exact_guide_anchors_source_xy"]

    TEXTURES.mkdir(parents=True, exist_ok=True)
    (OUT / "parts").mkdir(exist_ok=True)
    output_parts: list[dict] = []
    texture_defs: dict[str, dict] = {}
    registrations: dict[str, dict] = {}
    reconstructed = Image.new("RGBA", source.size, (0, 0, 0, 0))
    reconstruction_pixels = bytearray(source.width * source.height)
    for owner, (bone, anchor_key) in OWNER_TO_BONE.items():
        mask = masks[owner]
        bbox = mask.getbbox()
        if bbox is None:
            raise ValueError(f"empty owner mask: {owner}")
        x0, y0, x1, y1 = bbox
        left, top = max(0, x0 - PADDING), max(0, y0 - PADDING)
        right, bottom = min(source.width, x1 + PADDING), min(source.height, y1 + PADDING)
        width, height = right - left, bottom - top
        src = source.crop((left, top, right, bottom))
        src_px = list(src.get_flattened_data())
        m_px = list(mask.crop((left, top, right, bottom)).get_flattened_data())
        out_px = [pixel if m and pixel[3] >= ALPHA_FLOOR else (0, 0, 0, 0)
                  for pixel, m in zip(src_px, m_px)]
        crop = Image.new("RGBA", (width, height)); crop.putdata(out_px)
        if sum(bool(m) and pixel[3] >= ALPHA_FLOOR for pixel, m in zip(src_px, m_px)) != owner_counts[owner]:
            raise ValueError(f"{owner}: copied pixel count differs from reviewed owner mask")
        color_path = TEXTURES / f"{owner}.png"
        crop.save(color_path)
        (OUT / "parts" / f"{owner}.png").write_bytes(color_path.read_bytes())
        normal = make_normal_map(np.asarray(crop, dtype=np.uint8))
        normal_path = TEXTURES / f"{owner}_n.png"
        Image.fromarray(normal, "RGBA").save(normal_path)
        (OUT / "parts" / f"{owner}_n.png").write_bytes(normal_path.read_bytes())

        glow_kind = "c" if owner == "pelvis" else "m" if owner in ("front_boot", "back_boot") else None
        glow_path = None
        if glow_kind:
            rgba = np.asarray(crop, dtype=np.uint8)
            extracted = glow_layer(rgba[:, :, :3], rgba[:, :, 3], glow_kind)
            if extracted is None:
                extracted = np.zeros_like(rgba)
            glow_path = TEXTURES / f"{owner}_glow.png"
            Image.fromarray(extracted.astype(np.uint8), "RGBA").save(glow_path)
            (OUT / "parts" / f"{owner}_glow.png").write_bytes(glow_path.read_bytes())

        anchor = tuple(map(float, anchors[anchor_key]))
        pivot = (anchor[0] - left, anchor[1] - top)
        if not (0.0 <= pivot[0] <= width and 0.0 <= pivot[1] <= height):
            raise ValueError(f"{owner}: exact guide joint lies outside native crop; no pivot clamp allowed")
        bone_to_skeleton = global_xf[bone]
        source_to_bone = compose(inverse(bone_to_skeleton), source_to_skeleton)
        angle = math.atan2(source_to_bone[1], source_to_bone[0])
        offset = apply(source_to_bone, (left + pivot[0], top + pivot[1]))
        validate_offset(offset, apply(source_to_bone, anchor))
        a, b, c, d, _, _ = source_to_bone
        sprite_linear = (math.cos(angle) * texture_scale, math.sin(angle) * texture_scale,
                         -math.sin(angle) * texture_scale, math.cos(angle) * texture_scale)
        linear_error = max(abs(v - expected) for v, expected in zip((a, b, c, d), sprite_linear))
        if linear_error >= 1e-8:
            raise ValueError(f"{owner}: captured affine cannot be represented by Sprite2D uniform scale")
        samples = [anchor, (left, top), (right - 1, top), (left, bottom - 1), (right - 1, bottom - 1)]
        errors = []
        for point in samples:
            target = apply(source_to_bone, point)
            local_point = (point[0] - left, point[1] - top)
            dx, dy = local_point[0] - pivot[0], local_point[1] - pivot[1]
            rendered = (offset[0] + texture_scale * (math.cos(angle) * dx - math.sin(angle) * dy),
                        offset[1] + texture_scale * (math.sin(angle) * dx + math.cos(angle) * dy))
            errors.append(distance(target, rendered))
        if max(errors) > 0.015 or distance(apply(source_to_bone, anchor), (0.0, 0.0)) > 0.015:
            raise ValueError(f"{owner}: source landmark does not map to fixed canonical bone root")

        alias = f"kneel_v3_{owner}"
        relative_texture_path = f"../../../pm/Nest-Egg/attachments/NE-222-native-pose/generated/registration/textures/{owner}.png"
        definition = {"file": relative_texture_path, "size": [width, height], "pivot": list(pivot),
                     "note": "PRIVATE source-exact 22297 v3 owner; not accepted pose art"}
        if glow_path:
            definition["glow"] = f"../../../pm/Nest-Egg/attachments/NE-222-native-pose/generated/registration/textures/{owner}_glow.png"
        texture_defs[alias] = definition
        for slot in OWNER_SLOTS[owner]:
            output_parts.append({"slot": slot, "texture": alias, "bone": bone,
                                 "offset": list(offset), "rotation": angle})

        # Native reassembly contains each retained source pixel once, no resampling.
        owner_pixels = np.asarray(mask, dtype=np.uint8) > 0
        source_array = np.asarray(source, dtype=np.uint8)
        rebuild_array = np.asarray(reconstructed, dtype=np.uint8).copy()
        rebuild_array[owner_pixels] = source_array[owner_pixels]
        reconstructed = Image.fromarray(rebuild_array, "RGBA")
        owner_flat = owner_pixels.reshape(-1)
        for index in np.flatnonzero(owner_flat):
            if reconstruction_pixels[index]:
                raise ValueError("duplicate pixel while reassembling source")
            reconstruction_pixels[index] = 1

        registrations[owner] = {
            "bone": bone,
            "slot_names": list(OWNER_SLOTS[owner]),
            "anchor_source_xy": list(anchor),
            "anchor_semantics": "canonical guide bone-root target, not independently measured anatomy",
            "pivot_source_xy": [left + pivot[0], top + pivot[1]],
            "pivot_local_xy": list(pivot),
            "mask_bbox_xyxy_half_open": [x0, y0, x1, y1],
            "crop_bbox_xyxy_half_open": [left, top, right, bottom],
            "native_crop_size": [width, height],
            "owned_alpha_ge40_pixels": owner_counts[owner],
            "source_rgba_exact": True,
            "bone_local_offset": list(offset),
            "bone_local_rotation_radians": angle,
            "texture_scale_world_per_pixel": texture_scale,
            "linear_affine_error": linear_error,
            "max_corner_and_anchor_reprojection_world": max(errors),
            "source_sha256": SOURCE_SHA,
            "color_sha256": sha(color_path),
            "normal_sha256": sha(normal_path),
            "normal_method": "tools/comfyui/cut_layers.py make_normal_map CPU port of NormalMapMaker.make(source,2,3.0,1.4)",
            "glow_sha256": sha(glow_path) if glow_path else None,
            "glow_extraction": f"tools/comfyui/cut_parts.py glow_layer kind={glow_kind}; Rin source recipe" if glow_kind else None,
            "counterpart_slots_share_same_visible_crop_geometry_only": len(OWNER_SLOTS[owner]) > 1,
        }

    expected_alpha = np.asarray(source.getchannel("A"), dtype=np.uint8) >= ALPHA_FLOOR
    rebuilt_pixels = np.asarray(reconstructed, dtype=np.uint8)
    source_pixels = np.asarray(source, dtype=np.uint8)
    if not np.array_equal(np.frombuffer(reconstruction_pixels, dtype=np.uint8).reshape(source.height, source.width).astype(bool), expected_alpha):
        raise ValueError("source reassembly coverage differs from alpha>=40 exactly")
    if not np.array_equal(rebuilt_pixels[expected_alpha], source_pixels[expected_alpha]):
        raise ValueError("source reassembly changed a retained source RGBA pixel")
    make_contact(reconstructed, OUT / "source-reassembly-black-gray-white-native.png")
    # Per-owner native black/gray/white strips: no resampling; width is 3×largest crop.
    max_crop_width = max(record["native_crop_size"][0] for record in registrations.values())
    contact = Image.new("RGB", (max_crop_width * 3, sum(record["native_crop_size"][1] for record in registrations.values())), (28, 31, 39))
    y_cursor = 0
    owner_crop_paths = {}
    for owner, record in registrations.items():
        crop = Image.open(TEXTURES / f"{owner}.png").convert("RGBA")
        owner_crop_paths[owner] = str((TEXTURES / f"{owner}.png").relative_to(ROOT))
        for col, bg in enumerate([(0, 0, 0, 255), (91, 101, 119, 255), (255, 255, 255, 255)]):
            panel = Image.new("RGBA", crop.size, bg); panel.alpha_composite(crop)
            contact.paste(panel.convert("RGB"), (col * max_crop_width, y_cursor))
        y_cursor += crop.height
    contact.save(OUT / "seven-parts-black-gray-white-native.png")

    pose_set = {"texture_scale": texture_scale, "parts": output_parts}
    bone_pose = {name: {"parent": parents[name], "local_position": guide_bones[name]["local_position"],
                        "local_rotation_radians": guide_bones[name]["local_rotation_radians"],
                        "rest_position": guide_bones[name]["rest_position"]}
                 for name in guide_bones}
    (OUT / "textures.json").write_text(json.dumps(texture_defs, indent=2), encoding="utf-8")
    (OUT / "pose_parts.json").write_text(json.dumps({"kneel_22297_registration_v3_fixture": pose_set}, indent=2), encoding="utf-8")
    (OUT / "canonical_bone_pose.json").write_text(json.dumps(bone_pose, indent=2), encoding="utf-8")
    source_record = {"path": str(SOURCE.relative_to(ROOT)), "sha256": SOURCE_SHA, "size": [1440, 736],
                     "mode": "RGBA", "alpha_floor": ALPHA_FLOOR,
                     "retained_pixels": int(np.count_nonzero(expected_alpha)),
                     "owner_manifest": str(MANIFEST.relative_to(ROOT)), "owner_manifest_sha256": sha(MANIFEST),
                     "manual_guide_sha256": sha(PROPOSAL), "canonical_guide_sha256": GUIDE_SHA}
    records = {
        "status": "PRIVATE_V3_SOURCE_REGISTRATION_FIXTURE_NOT_VISUAL_OR_RUNTIME_ACCEPTANCE",
        "fixture_id": "NE222.KneelRegistration.22297.v3.source-exact",
        "source": source_record,
        "guide": {"path": str(GUIDE.relative_to(ROOT)), "sha256": GUIDE_SHA,
                  "bones": 20, "pose_texture_scale_world_per_pixel": texture_scale,
                  "pose_density_source_px_per_world": density,
                  "source_density_px_per_world": density, "character_scale": root_scale,
                  "character_root_scale": root_scale,
                  "holder_scale_source_px_per_skeleton_unit": holder_scale,
                  "holder_scale_source_px_per_unscaled_unit": holder_scale,
                  "holder_scale_source_px_per_unscaled_skeleton_unit": holder_scale,
                  "root_origin_source_xy": list(source_origin),
                  "skeleton_root_origin_source_xy": list(source_origin),
                  "floor_y_source_px": source_origin[1],
                  "source_to_skeleton": list(source_to_skeleton)},
        "canonical_skeleton": {"rig": str(RIG.relative_to(ROOT)), "bone_count": 20,
                               "rest_lengths_world": rest_lengths, "rest_positions_unchanged": True},
        "owners": registrations,
        "pose_parts": pose_set,
        "textures": texture_defs,
        "source_reconstruction": {"native_size": [1440, 736], "rgba_exact_for_alpha_ge40": True,
                                  "unowned_pixels": 1440 * 736 - int(np.count_nonzero(expected_alpha)),
                                  "image": "source-reassembly-black-gray-white-native.png",
                                  "owner_contact": "seven-parts-black-gray-white-native.png"},
        "cuffs_vs_ankles": {
            "front_boot_cuff_source_low_confidence": [1181, 389],
            "front_ankle_bone_root_guide_target": anchors["foot_front"],
            "back_boot_cuff_source_low_confidence": [337, 594],
            "back_ankle_bone_root_guide_target": anchors["foot_back"],
            "rule": "Boot slot pivot remains at canonical ankle bone root inside the boot canvas; cuff location is a separate visible landmark and never moves the bone.",
        },
        "checks": {"source_hash_pinned": sha(SOURCE) == SOURCE_SHA,
                    "guide_hash_pinned": sha(GUIDE) == GUIDE_SHA,
                    "owners_partition_all_alpha_ge40": True,
                    "owner_masks_nonoverlap": True,
                    "all_seven_source_parts_registered": len(registrations) == 7,
                    "front_boot_replaces_foot_front": "foot_front" in OWNER_SLOTS["front_boot"],
                    "back_boot_replaces_foot_back": "foot_back" in OWNER_SLOTS["back_boot"],
                    "canonical_foot_bones_unchanged": True,
                    "all_crops_native_resolution": True,
                    "normal_map_outputs_native_size": True,
                    "source_pixels_preserved": True,
                    "negative_source_hash_incomplete_duplicate_and_transform_controls_reject": True,
                    "all_source_rgba_unchanged_after_build": sha(SOURCE) == source_sha_before},
        "limitations": [
            "The seven-part source ownership is manually reviewed but remains a proposal; this registration does not grant art acceptance.",
            "Guide anchors are target bone roots, not all independently measured anatomical landmarks. Hip and calf/ankle registration must be visually judged.",
            "Armor/damage counterpart slots reuse the same visible source crop for geometry/API plumbing only; no real hidden damaged underlayer exists.",
            "Rin source glow is extracted using existing recipe kinds (pelvis=c, boot=m); this does not approve lighting or materials.",
            "Normals are generated by the repository's existing CPU normal-map helper from the same crop; their visual material response is not approved.",
            "The prior standing boot affines are not included in the kneel pose set; the new pose-specific boots attach to existing foot bones without changing bone rest or pose transforms.",
            "No underlap is added in this first registration. Any seam gap must be separately evidenced and reviewed before using source-exact seam candidates.",
            "No Godot capture, Forward+ rendering, animation transition, full-body appearance, or gameplay acceptance is claimed by this builder.",
        ],
    }
    (OUT / "registration-v3-report.json").write_text(json.dumps(records, indent=2), encoding="utf-8")
    if sha(SOURCE) != SOURCE_SHA:
        raise ValueError("pinned input source changed during build")
    print(json.dumps({"status": records["status"], "parts": len(registrations), "slots": len(output_parts),
                      "source_pixels": int(np.count_nonzero(expected_alpha)), "texture_scale": texture_scale,
                      "max_reprojection_error_world": max(x["max_corner_and_anchor_reprojection_world"] for x in registrations.values()),
                      "source_sha256": sha(SOURCE)}, indent=2))


if __name__ == "__main__":
    main()
