#!/usr/bin/env python3
"""Verify the preserved NE-221 dual-facing head-only native capture."""

from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path


SKINS = (
    "rin", "old_k", "nurse", "night_worker", "repairman_chen",
    "resident", "ah_po", "wataru", "mei",
)
STATES = ("open", "half", "closed")
STAGES = ("eye-stage-00.png", "eye-stage-15.png", "eye-stage-30.png")
NATIVE_HEAD_ID = "NE-221 dual-facing eye capture v4"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if len(data) < 24 or data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        raise ValueError(f"not a valid PNG/IHDR: {path}")
    return struct.unpack(">II", data[16:24])


def fail(message: str) -> None:
    raise ValueError(message)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path, default=Path.cwd())
    parser.add_argument(
        "--images", type=Path,
        default=Path("pm/Nest-Egg/images/NE-221-eyes-dual-facing"),
    )
    parser.add_argument(
        "--report", type=Path,
        default=Path("pm/Nest-Egg/attachments/NE-221-eyes-dual-facing/native-report.json"),
    )
    parser.add_argument(
        "--attachment", type=Path,
        default=Path("pm/Nest-Egg/attachments/NE-221-eyes-dual-facing"),
    )
    args = parser.parse_args()
    repo = args.repo_root.resolve()
    image_dir = (repo / args.images).resolve()
    report_path = (repo / args.report).resolve()
    attachment = (repo / args.attachment).resolve()
    report = json.loads(report_path.read_text(encoding="utf-8"))
    if report.get("status") != "captured_not_accepted" or report.get("errors"):
        fail("native capture is not a successful captured_not_accepted report")
    if report.get("capture_states_are_natural") is not True or report.get("forced_states") is not False:
        fail("capture is not marked as natural runtime state progression")
    if report.get("full_character_or_clothing_acceptance") is not False:
        fail("scope must remain head-only")
    if int(report.get("wall_elapsed_ms", 0)) < 30000:
        fail("native wall-clock capture is shorter than 30 seconds")
    if int(report.get("processed_frames", 0)) <= 0:
        fail("native report has no processed frames")
    if report.get("hdr_2d") is not True or report.get("readback_helper") != "res://tools/viewport_capture.gd":
        fail("native HDR readback path is not recorded")
    rows = report.get("characters", [])
    if len(rows) != len(SKINS) * 2:
        fail(f"expected 18 skin/facing rows, got {len(rows)}")

    expected_names: set[str] = set(STAGES)
    seen: set[tuple[str, int]] = set()
    completed_cycles = 0
    source_records: dict[str, dict[str, object]] = {}
    for row in rows:
        skin = row.get("skin_id")
        facing = int(row.get("facing", 0))
        if skin not in SKINS or facing not in (-1, 1) or (skin, facing) in seen:
            fail(f"invalid or duplicate skin/facing row: {skin}/{facing}")
        seen.add((skin, facing))
        if row.get("eye_parent_bone") != "head" or row.get("source_density_holder_scale") is None:
            fail(f"runtime head attachment data absent: {skin}/{facing}")
        for state in STATES:
            crop = row.get("rendered_crops", {}).get(state)
            if not crop:
                fail(f"missing rendered {state} crop: {skin}/{facing}")
            name = f"{skin}_face_{facing}_{state}.png"
            expected_names.add(name)
            image_path = image_dir / name
            if not image_path.is_file():
                fail(f"missing PNG: {image_path}")
            if sha256(image_path) != crop.get("sha256"):
                fail(f"rendered crop SHA mismatch: {name}")
            size = png_size(image_path)
            if list(size) != crop.get("size"):
                fail(f"rendered crop dimensions differ from report: {name}")
            density = crop.get("screen_pixel_per_source_pixel", [])
            if len(density) != 2 or any(abs(float(value) - 1.0) > 0.001 for value in density):
                fail(f"rendered crop is not at 1:1 source-pixel density: {name}")

        cycles = row.get("blink_cycles", [])
        if not cycles:
            fail(f"no completed natural cycle: {skin}/{facing}")
        for cycle in cycles:
            if cycle.get("sequence_ok") is not True or cycle.get("duration_ok") is not True:
                fail(f"invalid completed natural cycle: {skin}/{facing}")
        completed_cycles += len(cycles)
        for source in row.get("source_files", {}).values():
            res_path = source.get("res_path", "")
            if not res_path.startswith("res://"):
                fail(f"unexpected source path: {res_path}")
            source_path = repo / Path(res_path.removeprefix("res://"))
            record = source_records.setdefault(res_path, source)
            if not source_path.is_file():
                fail(f"missing current source: {source_path}")
            if source_path.stat().st_size != source.get("size_bytes") or sha256(source_path) != source.get("sha256"):
                fail(f"source SHA/size differs from captured provenance: {res_path}")

    if seen != {(skin, facing) for skin in SKINS for facing in (-1, 1)}:
        fail("not all nine configured skins are present at both facings")
    for name in STAGES:
        path = image_dir / name
        if not path.is_file():
            fail(f"missing stage PNG: {path}")
        width, height = png_size(path)
        if (width, height) != tuple(report.get("window_size", [])):
            fail(f"stage PNG does not match native viewport: {name}")
    actual_pngs = {path.name for path in image_dir.glob("*.png")}
    if actual_pngs != expected_names or len(actual_pngs) != 57:
        fail(f"expected exactly the 57 captured PNGs, got {len(actual_pngs)}")
    if len(source_records) < len(SKINS) * 3:
        fail("source hash ledger is unexpectedly incomplete")

    manifest = {
        "evidence_id": NATIVE_HEAD_ID,
        "source_head": "212768fa4a98e9db5bb1b3f4c067ef6027c7547d",
        "result": "captured_not_accepted",
        "scope": "head-only natural eye-state rendering; not full-scene/cloth/all-motion acceptance",
        "report_sha256": sha256(report_path),
        "pngs": [
            {"path": name, "sha256": sha256(image_dir / name), "size": list(png_size(image_dir / name))}
            for name in sorted(expected_names)
        ],
        "source_file_count": len(source_records),
        "completed_natural_cycles": completed_cycles,
        "interrupted_cycles": sum(len(row.get("interrupted_cycles", [])) for row in rows),
        "native_wall_elapsed_ms": report["wall_elapsed_ms"],
        "processed_frames": report["processed_frames"],
    }
    manifest_path = attachment / "capture-manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(
        f"PASS: 18 rows; {len(actual_pngs)} PNGs; {completed_cycles} completed cycles; "
        f"{manifest['interrupted_cycles']} separately recorded interruptions; "
        f"{len(source_records)} current source hashes; {report['wall_elapsed_ms']} ms / "
        f"{report['processed_frames']} frames; head-only scope retained."
    )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        raise SystemExit(1)
