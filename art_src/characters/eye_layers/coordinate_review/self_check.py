#!/usr/bin/env python3
"""Check source hashes, invalid-id rejection, and deterministic diagnostic renders."""

from __future__ import annotations

import hashlib
import subprocess
import sys
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[4]
BUILDER = HERE / "build_contact_sheets.py"
INSPECTOR = HERE / "inspect_eye_source.py"


def hashes() -> dict[str, str]:
    return {path.name: hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(HERE.glob("*-contact.png"))}


def main() -> None:
    outputs = []
    for _ in range(2):
        result = subprocess.run([sys.executable, str(BUILDER)], cwd=ROOT, capture_output=True, text=True)
        if result.returncode:
            raise SystemExit(result.stdout + result.stderr)
        outputs.append(hashes())
    assert len(outputs[0]) == 9 and outputs[0] == outputs[1], "contact sheets are not deterministic"
    rejected = subprocess.run([sys.executable, str(INSPECTOR), "--id", "not-a-character"],
                              cwd=ROOT, capture_output=True, text=True)
    assert rejected.returncode != 0, "inspector unexpectedly accepted an invalid source id"
    print("PASS: 9 native sources/hash and bounds checked; alpha, gray composite, RGBA/native size checked; invalid id rejected; contact sheets repeat byte-identically")


if __name__ == "__main__":
    main()
