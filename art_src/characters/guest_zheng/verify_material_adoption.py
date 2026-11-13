"""Compare actual Godot normal files with the frozen native A/A source bytes."""
import hashlib
import io
import json
from pathlib import Path
import zipfile

import cv2
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]
WORK = Path(__file__).resolve().parent
OUT = WORK / "repair_candidates/adoption-v1"
ARCHIVE = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs/alpha-only-AA-v1-source.zip"


def main():
    records = []
    with zipfile.ZipFile(ARCHIVE) as archive:
        for source in sorted((ROOT / "art/characters/guest_zheng/parts").glob("*.png")):
            if source.stem.endswith("_n"):
                continue
            path = source.relative_to(ROOT).as_posix()
            before = np.array(Image.open(io.BytesIO(archive.read(path))))
            after = np.array(Image.open(source))
            old_normal = np.array(Image.open(io.BytesIO(archive.read(path[:-4] + "_n.png"))))
            new_normal = np.array(Image.open(source.with_name(source.stem + "_n.png")))
            aligned = np.zeros_like(after)
            normal_aligned = np.zeros_like(new_normal)
            dx = 9 if source.stem == "hand" else 0
            aligned[:before.shape[0], dx:dx + before.shape[1]] = before
            normal_aligned[:before.shape[0], dx:dx + before.shape[1]] = old_normal
            domain = np.zeros(after.shape[:2], bool)
            domain[:before.shape[0], dx:dx + before.shape[1]] = True
            changed = np.any(aligned != after, axis=2)
            affected = cv2.dilate(changed.astype("uint8"), np.ones((7, 7), "uint8")) > 0
            remote = domain & ~affected
            normal_changes = np.any(normal_aligned != new_normal, axis=2)
            record = dict(part=source.stem, changed_diffuse_pixels=int(changed.sum()),
                          changed_normal_pixels_outside_material_kernel=int((normal_changes & remote).sum()),
                          normal_source="actual Godot NormalMapMaker.make output, not CPU prototype",
                          actual_normal_sha256=hashlib.sha256(source.with_name(source.stem + "_n.png").read_bytes()).hexdigest())
            assert not np.any(normal_changes & remote), record
            if source.stem == "hand":
                record["finger_diffuse_changes"] = int(np.any(aligned[:, 69:] != after[:, 69:], axis=2).sum())
                record["finger_normal_changes"] = int(normal_changes[:, 69:].sum())
                assert record["finger_diffuse_changes"] == record["finger_normal_changes"] == 0, record
            elif source.stem not in ("pelvis", "leg_lower", "torso"):
                assert np.array_equal(before, after), record
                assert np.array_equal(old_normal, new_normal), record
            if source.stem == "torso":
                assert np.array_equal(before[:, :, 3], after[:, :, 3]), "RGB torso patch changed rendered alpha"
            records.append(record)
    result = dict(classification="actual Godot normal PNG comparison; full animated native acceptance separate",
                  frozen_archive_sha256=hashlib.sha256(ARCHIVE.read_bytes()).hexdigest(), parts=records, passed=True)
    (OUT / "actual-normal-comparison.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
