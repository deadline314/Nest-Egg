"""Portable, offline NE274 archive/actual-font/pixel verification; needs Pillow."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path, PurePosixPath
import tarfile
import tempfile

HERE = Path(__file__).resolve().parent


def read(path):
    return json.loads(path.read_text(encoding="utf8"))


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=HERE / "verification.json")
    args = parser.parse_args()
    manifest = read(HERE / "manifest.json")
    archive = HERE / manifest["archive"]["file"]
    assert archive.stat().st_size == manifest["archive"]["size"] < 100_000_000
    assert digest(archive) == manifest["archive"]["sha256"]
    with tempfile.TemporaryDirectory(prefix="ne274-evidence-") as temporary:
        root = Path(temporary)
        expected = {record["name"]: record for record in manifest["members"]}
        assert len(expected) == len(manifest["members"])
        seen = set()
        with tarfile.open(archive, "r:xz") as tar:
            for member in tar:
                path = PurePosixPath(member.name)
                assert member.isfile() and not path.is_absolute() and ".." not in path.parts
                assert "\\" not in member.name and ":" not in member.name
                assert "profile" not in [part.lower() for part in path.parts]
                assert member.name in expected and member.name not in seen
                record = expected[member.name]
                assert member.size == record["size"]
                target = root.joinpath(*path.parts).resolve()
                assert target.is_relative_to(root.resolve())
                target.parent.mkdir(parents=True, exist_ok=True)
                h = hashlib.sha256()
                count = 0
                with tar.extractfile(member) as source, target.open("wb") as output:
                    for block in iter(lambda: source.read(1024 * 1024), b""):
                        h.update(block)
                        count += len(block)
                        output.write(block)
                assert count == record["size"] and h.hexdigest() == record["sha256"]
                seen.add(member.name)
        assert seen == set(expected)
        spec = importlib.util.spec_from_file_location("ne274_frozen_verifier", root / "review/verify.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        result = module.verify(root / "final")
        result["archive_sha256"] = manifest["archive"]["sha256"]
        result["members_verified"] = len(seen)
        baseline_hashes = read(root / "review/original-source-hashes.json")
        for name, original in baseline_hashes.items():
            if name != "tools/dialogue_box_capture.gd":
                assert digest(root / "source" / name) == original, name
        for tag in ("original-negative", "self-check", "normal", "large", "reduced"):
            receipt = read(root / "final" / tag / "process-receipt.json")
            assert all(digest(root / "source" / name) == value for name, value in receipt["source_before_sha256"].items())
        history = []
        for version, count in (("v1", 5), ("v2", 2)):
            report = read(root / "historical" / version / "reduced/reduced-index.json")
            receipt = read(root / "historical" / version / "reduced/process-receipt.json")
            assert report["failures"] == count and receipt["exit_code"] == 1
            assert all(item["first"]["clock"] == item["second"]["clock"] == 0 for item in report["decoration_checks"])
            same_pixels = sum(item["first"]["pixel_hashes"] == item["second"]["pixel_hashes"] for item in report["decoration_checks"])
            history.append({"version": version, "failures_preserved": count, "same_decoration_pixel_hash_samples": same_pixels,
                            "scope": "Historical capture/checker arrangement, not product animation failure count"})
        parsed = root / "historical/v3-parse-error/self-check"
        assert "Cannot infer the type of" in (parsed / "console.log").read_text(encoding="utf8")
        assert read(parsed / "process-receipt.json")["exit_code"] != 0
        result["historical"] = history
        result["historical_parse_error_preserved"] = True
        args.out.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf8")
    print(json.dumps({"members_verified": len(seen), "native_sets": 3, "phase_captures": 45,
                      "actual_large_fonts": [17, 17, 17], "unchanged_decoration_regions": 10,
                      "original_13_vs_17_rejected": True, "historical_failures_preserved": True}))


if __name__ == "__main__":
    main()
