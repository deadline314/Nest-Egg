"""Verify the recorded failed audit; a valid evidence packet is not an art pass."""
import gzip
import hashlib
import json
import sys
from collections import Counter
from pathlib import Path

import numpy as np
from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / "tools"))
from check_joint_frames import inspect, self_check


def main():
    manifest = json.loads((HERE / "manifest.json").read_text(encoding="utf8"))
    frames = json.loads((HERE / "frames.json").read_text(encoding="utf8"))
    report = json.loads(gzip.decompress((HERE / "report.json.gz").read_bytes()))
    samples = sum(len(group["cells"]) * len(group["samples"]) for group in frames)
    assert samples == report["samples"] == manifest["samples"] == 161280
    assert len(report["failures"]) == report["failed_samples"] == manifest["failed_samples"] == 19803
    assert dict(Counter(f["char"] for f in report["failures"])) == manifest["failures_by_character"]
    assert dict(Counter(f["char"] + "/" + f["joint"] for f in report["failures"])) == manifest["failures_by_character_joint"]
    assert len(manifest["all_native_files"]) == 1920
    records = {item["file"]: item for item in manifest["all_native_files"]}
    assert len(records) == 1920
    recorded = {(f["file"], f["char"], f["joint"], f["facing"]): f for f in report["failures"]}
    images = ROOT / "pm/Nest-Egg/images/NE-90-all-joint-audit"
    checked = 0
    for group in frames:
        for sample in group["samples"]:
            if sample["file"] not in manifest["selected_native_files"]:
                continue
            path = images / sample["file"]
            assert hashlib.sha256(path.read_bytes()).hexdigest() == records[path.name]["sha256"], path
            with Image.open(path) as image:
                assert image.mode == "RGBA" and image.size == (3584, 384), path
                alpha = np.asarray(image)[:, :, 3]
            for cell in group["cells"]:
                x, y, w, h = cell["rect"]
                radius = cell["radius"]
                assert 0 < radius < min(w, h) // 2
                cx, cy = x + w // 2, y + h // 2
                metrics = inspect(alpha[cy-radius:cy+radius, cx-radius:cx+radius])
                key = (path.name, cell["char"], cell["joint"], cell["facing"])
                failed = metrics["components"] != 1 or metrics["hole_pixels"] > 0 or metrics["center_alpha"] < 128
                assert failed == (key in recorded), key
                if failed:
                    assert all(metrics[k] == recorded[key][k] for k in metrics), key
                checked += 1
    assert checked == len(manifest["selected_native_files"]) * 84 == 504
    self_check()
    print(f"Evidence valid: {checked} selected native cells reproduce; art audit FAIL {len(recorded)}/{samples}.")


if __name__ == "__main__":
    main()
