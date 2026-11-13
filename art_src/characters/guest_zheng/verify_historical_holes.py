"""The new context classifier must still reject every preserved original enclosed wrist hole."""
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools"))
from npc_joint_scope import classify


def main():
    folder = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs/joints-diagnostic-v2"
    report = json.loads((folder / "report.json").read_text(encoding="utf8"))
    groups = json.loads((folder / "frames.json").read_text(encoding="utf8"))
    assert report["failed_samples"] == 6
    results = []
    for failure in report["failures"]:
        group = next(g for g in groups if g["pose"] == failure["pose"] and g["zoom"] == failure["zoom"])
        cell = next(c for c in group["cells"] if c["joint"] == failure["joint"] and c["facing"] == failure["facing"] and c["char"] == failure["char"])
        path = folder / failure["file"]
        image = np.array(Image.open(path).convert("RGBA"))
        x, y, width, height = cell["rect"]
        radius = cell["radius"]
        alpha = image[y + height // 2 - radius:y + height // 2 + radius,
                      x + width // 2 - radius:x + width // 2 + radius, 3]
        # A genuinely enclosed defect is rejected before any ROI assignment and
        # therefore cannot be excused by a missing/nearby anatomical anchor.
        result = classify(alpha, cell["joint"], {}, set())
        assert result["rejected"] and result["raw"]["enclosed_pixels"] >= 1
        results.append(dict(file=path.name, original_png_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
                            facing=cell["facing"], pose=group["pose"], raw=result["raw"], rejected=True))
    out = folder.parent / "material-historical-six-holes.json"
    out.write_text(json.dumps(dict(classification="preserved original native defects; all still rejected by unchanged pixel precision/context classifier",
                                  samples=6, rejected=6, cases=results), indent=2) + "\n", encoding="utf8", newline="\n")
    print("Preserved original enclosed holes: 6/6 rejected")


if __name__ == "__main__":
    main()
