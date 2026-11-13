"""Publish reviewed bounded source patches idempotently, before native cutting.

Each full-canvas derivative has its original source hash, bounded region and
opaque/outside preservation proof. A different source must be reviewed anew.
"""
import hashlib
import json
from pathlib import Path
import shutil

WORK = Path(__file__).resolve().parent


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    folder = WORK / "repair_candidates/joint-contours-v1"
    records = json.loads((folder / "candidates.json").read_text(encoding="utf8"))["candidates"]
    torso = json.loads((WORK / "torso_underlayer/material-review.json").read_text(encoding="utf8"))
    patches = [(record["part"], folder / (record["part"] + ".png"),
                record["input_sha256"], record["output_sha256"]) for record in records]
    patches.append(("torso", WORK / "torso_underlayer/candidate_torso.png",
                    torso["before_sha256"], torso["proposed_sha256"]))
    # Validate every input before publishing any of them.
    for name, candidate, original_hash, candidate_hash in patches:
        source = WORK / "07_refined" / (name + ".png")
        if sha(candidate) != candidate_hash:
            raise ValueError(f"{name}: registered bounded material derivative changed")
        if sha(source) not in (original_hash, candidate_hash):
            raise ValueError(f"{name}: source differs from the reviewed original and derivative; review the bounded repair again")
    for name, candidate, _, _ in patches:
        shutil.copyfile(candidate, WORK / "07_refined" / (name + ".png"))
    print("registered bounded material: torso RGB only; pelvis/lower-leg measured contour repair")


if __name__ == "__main__":
    main()
