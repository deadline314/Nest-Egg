#!/usr/bin/env python3
"""Rebuild the public source-to-native-pose fixture and assert byte stability."""
from __future__ import annotations

import hashlib
import json
import subprocess
import sys
from pathlib import Path

BUNDLE = Path(__file__).resolve().parent
PROJECT = BUNDLE.parents[3]
STAGES = [
    BUNDLE / "build_source_owners.py",
    BUNDLE / "build_registration.py",
    BUNDLE / "generated/shared_mesh/build_shared_grid.py",
    BUNDLE / "prepare_formal_fixture.py",
]
VOLATILE = {"generated/ownership/reproducibility.json"}


def hashes() -> dict[str, str]:
    result: dict[str, str] = {}
    for path in sorted((BUNDLE / "generated").rglob("*")):
        if not path.is_file() or "__pycache__" in path.parts or path.suffix in (".pyc", ".import", ".uid"):
            continue
        rel = path.relative_to(BUNDLE).as_posix()
        if rel in VOLATILE:
            continue
        result[rel] = hashlib.sha256(path.read_bytes()).hexdigest()
    fixture = BUNDLE / "formal_pose_data.json"
    result[fixture.relative_to(BUNDLE).as_posix()] = hashlib.sha256(fixture.read_bytes()).hexdigest()
    return result


def run_stages() -> None:
    for script in STAGES:
        subprocess.run([sys.executable, str(script)], cwd=PROJECT, check=True)


def main() -> None:
    run_stages()
    first = hashes()
    run_stages()
    second = hashes()
    if first != second:
        changed = sorted(set(first) | set(second))
        changed = [name for name in changed if first.get(name) != second.get(name)]
        raise SystemExit("generated outputs changed on deterministic rerun: " + ", ".join(changed))
    record = {
        "status": "CPU_REBUILD_DETERMINISTIC_NOT_RENDER_ACCEPTANCE",
        "source_sha256": "74044963a9ff8d2bc47b5bceed04d8763b856b252069c4817c7f0685b1bd33ed",
        "generated_file_count": len(second),
        "generated_hashes": second,
        "volatile_exclusions": sorted(VOLATILE),
        "two_full_runs_byte_identical": True,
        "viewport_used": False,
        "acceptance": False,
    }
    output = BUNDLE / "evidence/rebuild-determinism.json"
    output.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"status": record["status"], "generated_file_count": len(second),
                      "two_full_runs_byte_identical": True, "acceptance": False}, indent=2))


if __name__ == "__main__":
    main()
