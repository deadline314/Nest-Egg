"""Verify unmodified external source/raw ZIPs using the committed index files."""
import argparse
import hashlib
import json
import zipfile
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--raw-root", type=Path, default=Path("D:/NestEggDeliveries/NE290-20261112"))
args = parser.parse_args()
folder = Path(__file__).resolve().parent
sources = json.loads((folder / "external-source-index-v1.json").read_text(encoding="utf8"))
raw = json.loads((folder / "guest-scene-clock-v1/external-raw-index-v1.json").read_text(encoding="utf8"))
records = list(sources["archives"]) + [dict(item, file="guest-scene-clock-v1/" + item["file"]) for item in raw["archives"]]
for item in records:
    path = args.raw_root / item["file"]
    assert path.stat().st_size == item["bytes"]
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    assert digest.hexdigest() == item["sha256"], item["file"]
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None
print(len(records), "unaltered external archives verified by bytes, SHA256 and member CRC")
