"""Verify remote alpha/failed-RGBA volumes; optionally extract lossless alpha for the original checker."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import zipfile

from PIL import Image


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--extract", type=Path, help="new directory; never overwrite an existing export")
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text(encoding="utf8"))
    expected = {r["member"]: r for r in manifest["members"]}
    alpha_seen, failed_seen = set(), set()
    if args.extract:
        args.extract.mkdir(parents=True, exist_ok=False)
    for kind in ("alpha_volumes", "failed_rgba_volumes"):
        for volume in manifest[kind]:
            path = args.manifest.parent / volume["file"]
            assert sha(path.read_bytes()) == volume["sha256"], path
            with zipfile.ZipFile(path) as archive:
                for name in archive.namelist():
                    member = Path(name)
                    if member.is_absolute() or ".." in member.parts or len(member.parts) != 1:
                        raise ValueError("Unexpected evidence member path: " + name)
                    data = archive.read(name)
                    if name == "frames.json":
                        if args.extract and kind == "alpha_volumes":
                            (args.extract / name).write_bytes(data)
                        continue
                    record = expected[name]
                    if kind == "alpha_volumes":
                        assert name not in alpha_seen
                        assert sha(data) == record["derived_la_sha256"]
                        pixels = Image.open(io.BytesIO(data)).convert("RGBA")
                        assert list(pixels.size) == record["size"]
                        assert sha(pixels.getchannel("A").tobytes()) == record["alpha_sha256"]
                        alpha_seen.add(name)
                        if args.extract:
                            (args.extract / name).write_bytes(data)
                    else:
                        assert name not in failed_seen and record["included_failed_rgba"]
                        assert sha(data) == record["original_rgba_sha256"]
                        failed_seen.add(name)
    assert alpha_seen == set(expected)
    assert failed_seen == {name for name, row in expected.items() if row["included_failed_rgba"]}
    assert len(failed_seen) == manifest["failed_unique_frames"]
    print(len(alpha_seen), "lossless alpha frames;", len(failed_seen), "original failed RGBA frames verified")
    if args.extract:
        print("Run unchanged checker on", args.extract.resolve())


if __name__ == "__main__":
    main()
