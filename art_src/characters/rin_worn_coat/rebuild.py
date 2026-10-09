"""Rebuild the registered coat source overrides; then run the existing textures/normals/import steps."""
import hashlib
import io
import json
from pathlib import Path

import numpy as np
import cv2
from PIL import Image


work = Path(__file__).resolve().parent
root = work.parents[2]
record = json.loads((work / "manifest.json").read_text(encoding="utf8"))
for path, digest in record["sources"].items():
    assert hashlib.sha256((work / path).read_bytes()).hexdigest() == digest, f"source changed: {path}"
assert hashlib.sha256((root / record["approved_source"]).read_bytes()).hexdigest() == record["approved_sha256"]

body = np.array(Image.open(work / "source/07_refined/jacket.png"))
collar = np.array(Image.open(work / "source/07_refined/jacket_collar.png"))
selected = collar[:, :, 3] > body[:, :, 3]
body[selected] = collar[selected]
hem = body.copy()
body[355:, :, 3] = 0
hem[:340, :, 3] = 0
body[body[:, :, 3] == 0, :3] = 0
hem[hem[:, :, 3] == 0, :3] = 0
upper = np.array(Image.open(work / "source/07_refined/jacket_sleeve_upper.png"))
# SAM excluded navy ink at the sleeve silhouette; recover only actual source pixels in its one-pixel boundary.
source = np.array(Image.open(work / "source/04_stages/J.png"))
rgb = source[:, :, :3].astype(np.int16)
boundary = cv2.dilate((upper[:, :, 3] >= 128).astype(np.uint8), np.ones((3, 3), np.uint8)) > 0
ink = boundary & (upper[:, :, 3] < 253) & (source[:, :, 3] >= 253) & (rgb[:, :, 2] > rgb[:, :, 0] * 1.8) & (rgb[:, :, 1] >= rgb[:, :, 0])
upper[ink] = source[ink]
lower = upper.copy()
upper[420:] = 0
lower[:385] = 0
layers = {"armor_jacket": Image.fromarray(body), "jacket_hem": Image.fromarray(hem), "jacket_sleeve_upper": Image.fromarray(upper), "jacket_sleeve_lower": Image.fromarray(lower)}
for name, image in layers.items():
    assert image.mode == "RGBA" and image.size == (832, 1216), f"invalid registered layer: {name}"
    # Validate all derived bytes before replacing any source override.
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    assert hashlib.sha256(buffer.getvalue()).hexdigest() == record["outputs"][name], f"output changed: {name}"
for name, digest in record.get("retired_outputs", {}).items():
    for folder in ("06_parts", "07_refined", "overrides/refined"):
        target = root / "art_src/characters/rin2" / folder / f"{name}.png"
        assert not target.exists() or hashlib.sha256(target.read_bytes()).hexdigest() == digest, f"unexpected retired source override: {target}"
for name, image in layers.items():
    for folder in ("06_parts", "07_refined", "overrides/refined"):
        target = root / "art_src/characters/rin2" / folder / f"{name}.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        image.save(target)
for name in record.get("retired_outputs", {}):
    for folder in ("06_parts", "07_refined", "overrides/refined"):
        (root / "art_src/characters/rin2" / folder / f"{name}.png").unlink(missing_ok=True)
print("coat source checks: approved s33 unchanged; 4 registered layers reproduced with a shared elbow overlap")
