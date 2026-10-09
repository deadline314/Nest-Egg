#!/usr/bin/env python3
"""Run corrected eye candidate source, isolation, and deterministic-render checks."""

import hashlib
import json
from pathlib import Path

from PIL import Image
from build_candidates import HERE, self_test


if __name__ == "__main__":
    self_test()
    baselines = [
        ("v1", HERE / "v1_rejected/unchanged_other_7.json"),
        ("v4", HERE / "v4_unchanged_other_8.json"),
    ]
    for label, path in baselines:
        baseline = json.loads(path.read_text(encoding="utf-8"))
        for character, files in baseline.items():
            for relative, expected in files.items():
                if character == "repairer" and Path(relative).name in {"half.png", "repairer-contact.png"}:
                    continue  # repairer half is the one intentional v5 change; the v4 copy is preserved below.
                actual = hashlib.sha256((HERE / relative).read_bytes()).hexdigest()
                if actual != expected:
                    raise AssertionError(f"{label} unchanged-character output changed: {character}/{relative}")
    prior_repairer = json.loads((HERE / "v4_unchanged_other_8.json").read_text(encoding="utf-8"))["repairer"]
    for relative in ("characters/repairer/open.png", "characters/repairer/closed.png", "characters/repairer/eye_mask.png"):
        actual = hashlib.sha256((HERE / relative).read_bytes()).hexdigest()
        if actual != prior_repairer[relative]:
            raise AssertionError(f"repairer {Path(relative).name} changed during half-only update")
    history = HERE / "rejected_history/repairer-half-v1"
    history_manifest = json.loads((history / "manifest.json").read_text(encoding="utf-8"))
    old_half_hash = hashlib.sha256((history / "half.png").read_bytes()).hexdigest()
    if old_half_hash != history_manifest["original_candidate_half_sha256"]:
        raise AssertionError("prior rejected repairer half was not preserved")
    plan = json.loads((HERE / "candidate_plan.json").read_text(encoding="utf-8"))
    repairer_plan = next(item for item in plan["characters"] if item["id"] == "repairer")
    if max(point[1] for point in repairer_plan["half_lid"]) - min(point[1] for point in repairer_plan["half_lid"]) < 1:
        raise AssertionError("repairer half lid must use a curved contour")
    source = Image.open(HERE.parents[3] / "art_src/characters/repairman_chen/07_refined/head.png").convert("RGBA")
    half = Image.open(HERE / "characters/repairer/half.png").convert("RGBA")
    if half.getpixel((454, 95)) != source.getpixel((454, 95)) or half.getpixel((461, 95)) != source.getpixel((461, 95)):
        raise AssertionError("repairer half must retain lower sclera and pupil pixels from the open source")
    print("PASS: saved unchanged-character output hashes match v1 and v4 baselines")
    print("PASS: repairer open/closed/mask preserved; rejected half archived; curved half retains lower sclera and pupil")
