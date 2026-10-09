"""Rebuild the registered coat source overrides; then run the existing textures/normals/import steps."""
import hashlib
import io
import json
from pathlib import Path

import numpy as np
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
layers = {"armor_jacket": Image.fromarray(body), "jacket_hem": Image.fromarray(hem), "jacket_sleeve": Image.open(work / "source/07_refined/jacket_sleeve_upper.png")}
for name, image in layers.items():
    assert image.mode == "RGBA" and image.size == (832, 1216), f"invalid registered layer: {name}"
    # Validate all derived bytes before replacing any source override.
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    assert hashlib.sha256(buffer.getvalue()).hexdigest() == record["outputs"][name], f"output changed: {name}"
for name, image in layers.items():
    for folder in ("06_parts", "07_refined", "overrides/refined"):
        target = root / "art_src/characters/rin2" / folder / f"{name}.png"
        target.parent.mkdir(parents=True, exist_ok=True)
        image.save(target)
print("coat source checks: approved s33 unchanged; 3 registered layers reproduced exactly")
