#!/usr/bin/env python3
"""Verify the published NE-79 organic-combat evidence without Godot dependencies."""
from __future__ import annotations

import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

ATTACHMENT = Path(__file__).resolve().parent
REPO = ATTACHMENT.parents[3]
IMAGE_DIR = REPO / "pm" / "Nest-Egg" / "images" / "NE-79-organic-combat"
INDEX_PATH = ATTACHMENT / "evidence-index.json"
RAW_PATH = ATTACHMENT / "native-enforcer-preflight.json"
EXPECTED = {
    "NE79_enforcer_windup.png": "06bd2c07bc5d063279dfb9332cad5ed7e70a2eb18494847c3bc5a732884b3ee3",
    "NE79_enforcer_charge_skid.png": "1867ed26e0965705a2669816765f35744044f0e40c86780767148cfe24d5a7c7",
    "NE79_enforcer_rear_hit.png": "da011c081780986c2c2e6c51ad2caa3ef96e4127d9cebaf714beed0aa94efec5",
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def check_png(name: str, data: bytes, expected_sha: str) -> list[str]:
    errors: list[str] = []
    if not data.startswith(b"\x89PNG\r\n\x1a\n") or len(data) < 24:
        return [f"{name}: invalid PNG signature/header"]
    width, height = struct.unpack(">II", data[16:24])
    if (width, height) != (1280, 720):
        errors.append(f"{name}: dimensions are {width}x{height}, expected 1280x720")
    actual_sha = sha256(data)
    if actual_sha != expected_sha:
        errors.append(f"{name}: SHA-256 mismatch ({actual_sha})")
    return errors


def validate() -> tuple[list[str], dict]:
    index = json.loads(INDEX_PATH.read_text(encoding="utf-8"))
    raw_bytes = RAW_PATH.read_bytes()
    raw = json.loads(raw_bytes)
    errors: list[str] = []
    if index.get("raw_manifest_sha256") != sha256(raw_bytes):
        errors.append("raw native JSON SHA-256 differs from evidence index")
    if raw.get("head") != index.get("head") or raw.get("case_filter") != "NE79":
        errors.append("native JSON identity/case does not match the index")
    if raw.get("checks") != 16 or raw.get("failures"):
        errors.append("native run is not the recorded 16-check, zero-failure result")
    if index.get("checks") != 16 or index.get("failures") != 0:
        errors.append("evidence index does not record 16 checks and zero failures")
    if raw.get("godot", {}).get("string") != "4.7.2-stable (official)":
        errors.append("unexpected Godot version in native manifest")
    cpu_log = (ATTACHMENT / "public-replay-cpu.log").read_bytes()
    if sha256(cpu_log) != index.get("public_replay_cpu_log_sha256"):
        errors.append("public CPU replay log SHA-256 differs from evidence index")
    if b"COMBAT_PREFLIGHT checks=13 failures=0" not in cpu_log:
        errors.append("public CPU replay log does not record 13 checks and zero failures")
    cpu_manifest_bytes = (ATTACHMENT / "public-cpu-preflight.json").read_bytes()
    cpu_manifest = json.loads(cpu_manifest_bytes)
    if sha256(cpu_manifest_bytes) != index.get("public_replay_cpu_manifest_sha256"):
        errors.append("public CPU replay manifest SHA-256 differs from evidence index")
    if cpu_manifest.get("head") != index.get("head") or cpu_manifest.get("checks") != 13 or cpu_manifest.get("failures"):
        errors.append("public CPU replay manifest does not match the recorded 13-check run")
    cpu_sources = cpu_manifest.get("source_sha256", {})
    for source_key in ("character_json", "rig_json", "enforcer_texture_sources", "enemy_data", "enemy_behavior"):
        if not cpu_sources.get(source_key):
            errors.append(f"public CPU replay manifest is missing the {source_key} source hash")
    for log_name, index_key, required in (
        ("native-forward-plus.log", "native_log_sha256", b"COMBAT_PREFLIGHT checks=16 failures=0"),
        ("cpu-enforcer-preflight.log", "cpu_log_sha256", b"COMBAT_PREFLIGHT checks=13 failures=0"),
    ):
        log_data = (ATTACHMENT / log_name).read_bytes()
        if sha256(log_data) != index.get(index_key):
            errors.append(f"{log_name}: SHA-256 differs from evidence index")
        if required not in log_data:
            errors.append(f"{log_name}: expected check summary is missing")

    events = raw.get("events", [])
    captures = {event.get("data", {}).get("name"): event.get("data", {})
                for event in events if event.get("event") == "native_capture"}
    expected_names = {
        "NE79_enforcer_windup": "NE79_enforcer_windup.png",
        "NE79_enforcer_charge_skid": "NE79_enforcer_charge_skid.png",
        "NE79_enforcer_rear_hit": "NE79_enforcer_rear_hit.png",
    }
    for capture_name, filename in expected_names.items():
        capture = captures.get(capture_name)
        if capture is None:
            errors.append(f"native manifest is missing capture {capture_name}")
            continue
        if Path(capture.get("path", "")).name != filename:
            errors.append(f"native capture {capture_name} maps to a different image filename")
        if capture.get("size") != [1280, 720]:
            errors.append(f"native capture {capture_name} dimensions differ")
        if not capture.get("simulation_frozen") or capture.get("simulation_before") != capture.get("simulation_after"):
            errors.append(f"native capture {capture_name} did not preserve the recorded simulation state")
        image_record = index.get("images", {}).get(filename, {})
        if capture.get("size") != image_record.get("size"):
            errors.append(f"native capture {capture_name} dimensions do not match the indexed PNG")
        try:
            data = (IMAGE_DIR / filename).read_bytes()
        except OSError as exc:
            errors.append(f"{filename}: {exc}")
            continue
        errors.extend(check_png(filename, data, EXPECTED[filename]))
        if image_record.get("sha256") != sha256(data) or image_record.get("bytes") != len(data):
            errors.append(f"{filename}: bytes/hash do not match evidence index")

    by_event = {event.get("event"): event.get("data", {}) for event in events}
    blocked = by_event.get("front_projectile_result", {})
    if not (blocked.get("result") == "blocked" and blocked.get("enemy_health_before") == 8
            and blocked.get("enemy_health_after") == 8 and blocked.get("ammo_before") == 12
            and blocked.get("ammo_after") == 11):
        errors.append("front-side shield-block event does not match the recorded HP/ammo result")
    charge = by_event.get("attack_end", {})
    if not (charge.get("enemy_fsm") == "skid" and charge.get("player_health_before") == 12
            and charge.get("player_health_after") == 6):
        errors.append("natural charge/contact event does not match the recorded Player health result")
    rear = by_event.get("rear_projectile_result", {})
    if not (rear.get("result") == "damaged" and rear.get("enemy_health_before") == 8
            and rear.get("enemy_health_after") == 7):
        errors.append("rear-side projectile event does not match the recorded enemy health result")
    return errors, index


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--self-test", action="store_true", help="also verify a one-byte corruption is rejected")
    args = parser.parse_args()
    errors, index = validate()
    if args.self_test and not errors:
        filename = "NE79_enforcer_windup.png"
        original = (IMAGE_DIR / filename).read_bytes()
        corrupted = bytearray(original)
        corrupted[-1] ^= 1
        negative_errors = check_png(filename, bytes(corrupted), EXPECTED[filename])
        if not negative_errors:
            errors.append("negative control failed: one-byte PNG corruption was accepted")
        else:
            print("NEGATIVE_CONTROL one-byte PNG corruption rejected")
    if errors:
        for error in errors:
            print("FAIL:", error, file=sys.stderr)
        return 1
    print(f"PASS: NE-79 evidence package; {index['checks']} native checks, 0 failures, 3 frozen 1280x720 PNGs")
    print("CPU and native results are separate; this verifier checks archived evidence only.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
