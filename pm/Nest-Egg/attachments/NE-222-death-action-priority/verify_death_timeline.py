#!/usr/bin/env python3
"""Verify unmodified raw PNGs and frozen-time metadata in a death timeline pair."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
from collections import Counter
from pathlib import Path


EXPECTED_SKINS = {"enforcer", "heavy_gunner", "warden"}
EXPECTED_FRAMES_PER_SKIN = 5
EXPECTED_SIZE = (1536, 1400)
EXPECTED_HEAD = "a5efd3e48d85b10addfbdbda198cb7f2c395c1af"
ANIMATOR_PATH = "game/rig/humanoid_animator.gd"


def require(ok: bool, message: str) -> None:
    if not ok:
        raise ValueError(message)


def read_png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as source:
        header = source.read(24)
    require(header[:8] == b"\x89PNG\r\n\x1a\n", f"not a PNG: {path}")
    require(header[12:16] == b"IHDR", f"missing PNG IHDR: {path}")
    return struct.unpack(">II", header[16:24])


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_capture(manifest_path: Path, image_root: Path) -> dict:
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    frames = manifest["frames"]
    require(manifest["checkout_head"] == EXPECTED_HEAD, f"unexpected captured HEAD in {manifest_path}")
    require(manifest["checks"] == 158 and not manifest["failures"], f"capture checks/failures invalid: {manifest_path}")
    require(manifest["frames_count"] == 15 and manifest["unique_paths"] == 15, f"expected 15 unique frames: {manifest_path}")
    require(manifest["enemy_physics_enabled"] is True, f"enemy physics flag missing: {manifest_path}")
    require(manifest["facing"] == 1 and "front" in manifest["hit_direction"], f"front-hit setup missing: {manifest_path}")
    require(Counter(row["skin"] for row in frames) == Counter({skin: EXPECTED_FRAMES_PER_SKIN for skin in EXPECTED_SKINS}),
            f"unexpected skin/sample counts: {manifest_path}")
    require(len({row["path"] for row in frames}) == len(frames), f"duplicate paths: {manifest_path}")
    verified = []
    for row in frames:
        require(row["capture_scene_tree_paused"] is True, f"render-freeze marker missing: {row['path']}")
        require(row["capture_simulation_advanced"] is False, f"simulation advanced during capture: {row['path']}")
        require(row["enemy_physics_processing_enabled_during_freeze"] is True,
                f"enemy physics processing flag lost: {row['path']}")
        require(row["rig_dead_input"] is True and row["enemy_dying"] is True, f"not a death sample: {row['path']}")
        before = float(row["death_time_before_render_freeze"])
        after = float(row["death_time_after_render_freeze"])
        actual = float(row["actual_death_time_at_capture"])
        target = float(row["sample_target_death_time"])
        require(abs(before - after) <= 1e-9 and abs(actual - after) <= 1e-9,
                f"death timer changed during render freeze: {row['path']}")
        require(-1e-9 <= actual - target <= 1.0 / 60.0 + 1e-6,
                f"sample missed target timing: {row['path']} ({actual} vs {target})")
        require(row["camera_zoom"] == [3.40000009536743, 3.40000009536743],
                f"unexpected camera zoom metadata: {row['path']}")
        require(row["viewport_render_size"] == list(EXPECTED_SIZE) and row["image_size"] == list(EXPECTED_SIZE),
                f"unexpected source PNG dimensions: {row['path']}")
        image_path = image_root / row["path"]
        require(image_path.is_file(), f"missing raw image: {image_path}")
        require(read_png_size(image_path) == EXPECTED_SIZE, f"PNG header size mismatch: {image_path}")
        image_hash = sha256(image_path)
        require(image_hash == row["image_sha256"], f"PNG hash mismatch: {image_path}")
        verified.append({"skin": row["skin"], "path": row["path"], "sha256": image_hash,
                         "target_time": target, "actual_time": actual,
                         "action": row["action_at_capture"], "action_weight": row["action_weight_at_capture"]})
    return {"manifest_sha256": sha256(manifest_path), "frame_count": len(verified),
            "source_sha256": manifest["source_sha256"], "frames": verified}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--before", type=Path, default=Path(__file__).parent / "before")
    parser.add_argument("--after", type=Path, default=Path(__file__).parent / "after")
    image_root = Path(__file__).resolve().parents[2] / "images/NE-222-death-action-priority"
    parser.add_argument("--before-images", type=Path, default=image_root / "before")
    parser.add_argument("--after-images", type=Path, default=image_root / "after")
    args = parser.parse_args()
    before = verify_capture(args.before / "manifest.json", args.before_images)
    after = verify_capture(args.after / "manifest.json", args.after_images)
    before_sources = before["source_sha256"]
    after_sources = after["source_sha256"]
    require(before_sources.keys() == after_sources.keys(), "source manifest key sets differ")
    changed = sorted(key for key in before_sources if before_sources[key] != after_sources[key])
    require(changed == [ANIMATOR_PATH], f"expected only HumanoidAnimator source to change, got {changed}")
    require(before["manifest_sha256"] != after["manifest_sha256"], "before/after manifests unexpectedly identical")
    for skin in sorted(EXPECTED_SKINS):
        b = next(row for row in before["frames"] if row["skin"] == skin and row["target_time"] == 0.5)
        a = next(row for row in after["frames"] if row["skin"] == skin and row["target_time"] == 0.5)
        require(b["action"] == a["action"], f"staged action differs for {skin}")
        require(b["action_weight"] == 1.0 and a["action_weight"] == 0.0,
                f"expected death action blend 1 -> 0 for {skin}")
        require(abs(b["actual_time"] - a["actual_time"]) <= 1.0 / 60.0 + 1e-6,
                f"before/after sample times differ by more than one simulation tick for {skin}")
    print(json.dumps({"status": "verified", "before": before, "after": after,
                      "changed_source_files": changed,
                      "sample_0p5_action_weight": {skin: {"before": next(row["action_weight"] for row in before["frames"] if row["skin"] == skin and row["target_time"] == 0.5),
                                                         "after": next(row["action_weight"] for row in after["frames"] if row["skin"] == skin and row["target_time"] == 0.5)}
                                                       for skin in sorted(EXPECTED_SKINS)}}, indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, KeyError, ValueError, json.JSONDecodeError) as error:
        raise SystemExit(f"verification failed: {error}") from error
