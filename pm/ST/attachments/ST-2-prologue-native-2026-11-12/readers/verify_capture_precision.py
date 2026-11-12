"""Verify raw.zip members and native PNGs against the original float pixels."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image


def verify(path: Path) -> dict:
    checked = 0
    images = []
    with zipfile.ZipFile(path) as archive:
        for name in archive.namelist():
            if not name.endswith("manifest.json"):
                continue
            root = name.removesuffix("manifest.json")
            manifest = json.loads(archive.read(name))
            for member, receipt in manifest.get("files", {}).items():
                data = archive.read(root + member)
                assert len(data) == receipt["bytes"], (name, member, "byte count")
                assert hashlib.sha256(data).hexdigest() == receipt["sha256"], (name, member, "SHA-256")
                checked += 1
            for source, digest in manifest.get("sources", {}).items():
                member = source.removeprefix("res://").replace("/", "_") + ".txt"
                assert hashlib.sha256(archive.read(root + member)).hexdigest() == digest, (name, source, "source SHA-256")
                checked += 1
            for capture in manifest.get("captures", []):
                width, height = capture["size"]
                assert capture["size"] == manifest["resolution"], (name, capture["page"], "requested/native size mismatch")
                dtype, channels = {14: ("<f2", 3), 15: ("<f2", 4), 10: ("<f4", 3), 11: ("<f4", 4)}[capture["format"]]
                linear = np.frombuffer(archive.read(root + capture["linear_raw"]), dtype=dtype).reshape(height, width, channels).astype(np.float64)
                shown = np.asarray(Image.open(io.BytesIO(archive.read(root + capture["encoded_png"]))).convert("RGBA"), dtype=np.float64) / 255.0
                rgb = linear[..., :3]
                reference = np.where(rgb <= 0.0031308, rgb * 12.92, 1.055 * np.maximum(rgb, 0) ** (1 / 2.4) - 0.055)
                error = float(np.max(np.abs(shown[..., :3] - np.clip(reference, 0, 1))))
                alpha = np.clip(linear[..., 3], 0, 1) if channels == 4 else 1.0
                alpha_error = float(np.max(np.abs(shown[..., 3] - alpha)))
                assert error <= 1 / 255 + 0.00001, (name, capture["page"], "sRGB", error)
                assert alpha_error <= 1 / 255 + 0.00001, (name, capture["page"], "alpha", alpha_error)
                images.append({"page": capture["page"], "size": [width, height], "pixels": width * height, "max_srgb_error": error, "max_alpha_error": alpha_error})
    assert checked > 0, "No manifest member was verified"
    return {"archive": str(path), "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "members_verified": checked, "native_images": images}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    args = parser.parse_args()
    print(json.dumps(verify(args.archive), ensure_ascii=False, indent=2))
