"""Preserve native HDR bytes and independently verify the displayed PNG encoding."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path)
    args = parser.parse_args()
    folder = args.folder.resolve()
    target = folder / "raw.zip"
    if target.exists():
        raise ValueError("Refuse to overwrite previous native raw archive")
    scenes = json.loads((folder / "scenes.json").read_text(encoding="utf8"))
    records = []
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for scene in scenes["scenes"]:
            for snapshot in scene["snapshots"]:
                path = folder / snapshot["raw"]["file"]
                data = path.read_bytes()
                assert hashlib.sha256(data).hexdigest() == snapshot["raw"]["sha256"]
                png = np.array(Image.open(folder / snapshot["png"]).convert("RGBA"))
                height, width = png.shape[:2]
                assert snapshot["raw"]["format"] == 14 and snapshot["raw"]["hdr"]
                assert len(data) == width * height * 6, "Native format14 is RGBH, not RGBAH"
                linear = np.frombuffer(data, dtype="<f2").reshape(height, width, 3).astype(np.float64)
                srgb = np.where(linear <= .0031308, linear * 12.92, 1.055 * np.power(np.maximum(linear, 0), 1 / 2.4) - .055)
                encoded = np.rint(np.clip(srgb, 0, 1) * 255).astype("uint8")
                error = np.abs(encoded.astype(int) - png[:, :, :3].astype(int))
                assert error.max() <= 1 and np.all(png[:, :, 3] == 255)
                archive.writestr(path.name, data)
                records.append(dict(png=snapshot["png"], raw_sha256=hashlib.sha256(data).hexdigest(),
                                    raw_bytes=len(data), raw_format="RGBH", quantized_max_error=int(error.max()),
                                    mean_error=float(error.mean())))
    with zipfile.ZipFile(target) as archive:
        for record in records:
            assert hashlib.sha256(archive.read(record["png"] + ".raw")).hexdigest() == record["raw_sha256"]
    receipt = dict(zip_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
                   method="Independent numpy float16 RGB decode and IEC sRGB transfer; max one code value is rounding agreement, not an art-quality threshold",
                   frames=records)
    (folder / "raw-manifest.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf8")
    (folder / ".gitignore").write_text("# Original bytes remain locally and in raw.zip.\n*.raw\n", encoding="utf8")
    print(len(records), "original HDR frames", target.stat().st_size, "bytes", receipt["zip_sha256"])


if __name__ == "__main__":
    main()
