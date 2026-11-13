"""Rebuild reviewed bounded walk material as registered full-canvas overrides.

This preserves the original refined layers and their previous registered repair
chain. A changed input or unreviewed override fails before writing any material.
"""
import hashlib
import json
from pathlib import Path
import shutil

WORK = Path(__file__).resolve().parent
ROOT = WORK.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    folder = WORK / "repair_candidates/walk-contours-v2"
    records = [record for record in json.loads((folder / "candidates.json").read_text(encoding="utf8"))["candidates"]
               if record["radius_source_pixels"] == 2]
    if {record["part"] for record in records} != {"pelvis", "foot", "arm_lower"} or len(records) != 3:
        raise ValueError("Expected exactly the three reviewed radius2 source derivatives")
    output = WORK / "overrides/refined"
    for record in records:
        name = record["part"]
        source = WORK / "07_refined" / (name + ".png")
        candidate = folder / "radius-2" / (name + "-source.png")
        if sha(source) != record["input_sha256"] or sha(candidate) != record["source_sha256"]:
            raise ValueError(name + ": registered walk derivative or original refined source changed; review again")
        target = output / (name + ".png")
        if target.exists() and sha(target) != record["source_sha256"]:
            raise ValueError(name + ": another full-canvas override already owns this material")
    registrations = json.loads((WORK / "cut_registration.json").read_text(encoding="utf8"))
    output.mkdir(parents=True, exist_ok=True)
    for record in records:
        name = record["part"]
        candidate = folder / "radius-2" / (name + "-source.png")
        target = output / (name + ".png")
        shutil.copyfile(candidate, target)
        registrations[name]["source_path"] = target.relative_to(ROOT).as_posix()
        registrations[name]["source_mode"] = "registered full-canvas bounded walk derivative"
        registrations[name]["refined_source_sha256"] = record["source_sha256"]
    (WORK / "cut_registration.json").write_text(json.dumps(registrations, indent=2) + "\n", encoding="utf8", newline="\n")
    print("registered bounded walk underlap: pelvis/foot/arm_lower; original opaque, crop, pivot and source layers retained")


if __name__ == "__main__":
    main()
