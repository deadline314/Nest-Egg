"""Independently verify sealed original S18 RGBH captures and their PNGs."""
import hashlib
import argparse
import json
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image

folder = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--raw-root", type=Path, help="Directory containing unchanged raw-NN.zip archives (see external-raw-index-v1.json)")
args = parser.parse_args()
raw_root = args.raw_root or folder
manifest = json.loads((folder / "raw-manifest-v1.json").read_text(encoding="utf8"))
records = manifest["frames"]
for archive in manifest["archives"]:
    path = raw_root / archive["file"]
    assert path.stat().st_size == archive["bytes"]
    assert hashlib.sha256(path.read_bytes()).hexdigest() == archive["sha256"]
    with zipfile.ZipFile(path) as packed:
        for record in (record for record in records if record["archive"] == path.name):
            raw = packed.read(record["raw"])
            assert hashlib.sha256(raw).hexdigest() == record["sha256"]
            png = np.array(Image.open(folder / record["png"]).convert("RGBA"))
            height, width = png.shape[:2]
            assert len(raw) == height * width * 6
            linear = np.frombuffer(raw, dtype="<f2").reshape(height, width, 3).astype(np.float64)
            encoded = np.where(linear <= .0031308, linear * 12.92,
                               1.055 * np.maximum(linear, 0) ** (1 / 2.4) - .055)
            encoded = np.rint(np.clip(encoded, 0, 1) * 255).astype(np.uint8)
            error = np.abs(encoded.astype(np.int16) - png[:, :, :3].astype(np.int16))
            assert error.max() <= 1 and np.all(png[:, :, 3] == 255)
print(len(records), "unaltered RGBH frames verified from", len(manifest["archives"]), "archives")
