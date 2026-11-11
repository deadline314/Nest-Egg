"""Verify original native RGBH bytes and independently reproduce PNG encoding.

Run from any directory with Python, NumPy and Pillow. Uses raw.zip when loose
*.raw files are absent. --seal creates the lossless byte archive once.
"""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path

import numpy as np
from PIL import Image


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seal", action="store_true")
    args = parser.parse_args()
    folder = Path(__file__).resolve().parent
    captures = json.loads((folder / "native.json").read_text(encoding="utf8"))["captures"]
    archive = folder / "raw.zip"
    if args.seal:
        assert not archive.exists(), "Preserve the original archive; do not overwrite"
        with zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as output:
            for capture in captures:
                output.write(folder / capture["raw"]["file"], capture["raw"]["file"])
    records = []
    with zipfile.ZipFile(archive) as packed:
        for capture in captures:
            raw = capture["raw"]
            data = packed.read(raw["file"])
            assert hashlib.sha256(data).hexdigest() == raw["sha256"]
            width, height = raw["size"]
            assert raw["format"] == 14 and raw["hdr"] and len(data) == width * height * 6
            linear = np.frombuffer(data, dtype="<f2").reshape(height, width, 3).astype(np.float64)
            encoded = np.where(linear <= .0031308, linear * 12.92,
                               1.055 * np.maximum(linear, 0) ** (1 / 2.4) - .055)
            encoded = np.rint(np.clip(encoded, 0, 1) * 255).astype(np.uint8)
            png = np.array(Image.open(folder / capture["file"]).convert("RGBA"))
            error = np.abs(encoded.astype(np.int16) - png[:, :, :3].astype(np.int16))
            assert error.max() <= 1 and np.all(png[:, :, 3] == 255)
            records.append(dict(file=raw["file"], bytes=len(data), sha256=raw["sha256"],
                                png=capture["file"], maximum_srgb_rounding_error=int(error.max())))
    report = dict(classification="Original unmodified native RGBH bytes; independent float-before-quantization reader",
                  frames=records, archive=dict(file=archive.name, bytes=archive.stat().st_size,
                  sha256=hashlib.sha256(archive.read_bytes()).hexdigest()))
    assert report["archive"]["bytes"] < 45 * 1024 * 1024
    if args.seal:
        (folder / "raw-manifest-v1.json").write_text(json.dumps(report, indent=2) + "\n", encoding="utf8", newline="\n")
        (folder / ".gitignore").write_text("# Original bytes remain here and in hash-verified raw.zip.\n*.raw\n", encoding="utf8", newline="\n")
    else:
        assert report == json.loads((folder / "raw-manifest-v1.json").read_text(encoding="utf8"))
    print(len(records), "native frames verified", report["archive"]["bytes"], "archive bytes")


if __name__ == "__main__":
    main()
