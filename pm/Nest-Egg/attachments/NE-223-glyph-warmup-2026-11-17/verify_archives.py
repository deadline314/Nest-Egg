"""Portable raw-byte and identical before/after 33 ms gate verification. No engine required."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import subprocess
import sys
import tarfile
import tempfile

HERE = Path(__file__).resolve().parent
record = json.loads((HERE / "archive.json").read_text(encoding="utf8"))
manifest = json.loads((HERE / "members.json").read_text(encoding="utf8"))
archive = HERE / record["file"]
assert archive.stat().st_size == record["size"] < 50_000_000
assert hashlib.sha256(archive.read_bytes()).hexdigest() == record["sha256"]
with tempfile.TemporaryDirectory(prefix="ne223-glyph-") as temporary:
    root = Path(temporary)
    names = set()
    with tarfile.open(archive, "r:xz") as bundle:
        for member in bundle:
            name = PurePosixPath(member.name)
            assert member.isfile() and not name.is_absolute() and ".." not in name.parts
            assert not any(":" in part or "\\" in part or part == "profile" for part in name.parts)
            assert member.name not in names
            names.add(member.name)
            raw = bundle.extractfile(member).read()
            expected = manifest[member.name]
            assert len(raw) == member.size == expected["size"] and hashlib.sha256(raw).hexdigest() == expected["sha256"]
            target = root.joinpath(*name.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)
    assert names == set(manifest) and len(names) == record["members"]
    images = json.loads((HERE / "images.json").read_text())
    for row in images.values():
        relative = row["source"].replace("\\", "/").split("evidence-20261117/", 1)[1]
        original = root / "runs" / relative
        assert original.stat().st_size == row["size"] and hashlib.sha256(original.read_bytes()).hexdigest() == row["sha256"]
    results = {}
    for run, expected in [("ne223-quiet-native", 1), ("ne223-quiet-native-after", 0)]:
        command = [sys.executable, "-B", str(HERE / "verify_quiet.py"), str(root / "runs" / run)]
        result = subprocess.run(command, capture_output=True, text=True)
        assert result.returncode == expected, (run, result.stdout, result.stderr)
        data = json.loads(result.stdout)
        assert data["budget_ms"] == 33 and data["performance_gate_passed"] == (expected == 0)
        if expected:
            assert len(data["failed_raw_samples"]) == 1 and data["failed_raw_samples"][0]["frame_ms"] == 41.839
        results[run] = {"gate_exit_code": result.returncode, "failed_raw_samples": data["failed_raw_samples"]}
    for variant, failures in [("original", 1), ("candidate", 0)]:
        folder = root / "work/ui-comparison" / variant
        receipt = json.loads((folder / "receipt.json").read_text())
        log = (folder / "console.log").read_text(encoding="utf8")
        assert receipt["exit_code"] == failures and receipt["disk_source_unchanged"] and not receipt["script_error"]
        assert re.search(r"checks: 424, failures: " + str(failures), log)
        if failures:
            original = (root / "work/before-product/pause_menu.gd").read_bytes()
            assert "NE223_RUNTIME_OLD_SOURCE " + hashlib.sha256(original).hexdigest() in log
            assert "FAIL: loading primes real viewport-sized glyphs" in log
    frozen = json.loads((root / "work/freeze-product-v1.json").read_text())
    after = root / "runs/ne223-quiet-native-after/source"
    for name, digest in frozen.items():
        source = after / name if (after / name).is_file() else root / "work/freeze-product-v1" / Path(name).name
        assert hashlib.sha256(source.read_bytes()).hexdigest() == digest
    def cache_count(run, action, point, size):
        rows = json.loads((root / "runs" / run / "native-1920/font-cache-observations.json").read_text())
        row, = [row for row in rows if row["action"] == action and row["point"] == point]
        cache, = [cache for cache in row["caches"][0]["sizes"] if cache["size_px"] == f"({size}, 0)"]
        return cache["glyphs"]
    observed = "ne223-quiet-native-font-diagnostic"
    assert [cache_count(observed, "journal", point, 33) for point in ["before", "after"]] == [127, 200]
    assert [cache_count(observed, "journal", point, 27) for point in ["before", "after"]] == [9, 77]
    controls = []
    for variant, first_ms in [("control", 39.265), ("prime", 20.725)]:
        folder = root / "runs" / ("ne223-quiet-native-glyph-" + variant) / "native-1920"
        receipt = json.loads((folder / "process-receipt.json").read_text())
        report = json.loads((folder / "quest-map-perf-1920.json").read_text())
        assert receipt["exit_code"] == 0 and receipt["source_unchanged"]
        assert receipt["source_before"] == receipt["source_after"] and report["shared_workload"]
        assert report["summary"]["journal"]["first_ms"] == first_ms
        controls.append(receipt["source_before"])
    assert controls[0] == controls[1]
    prime = "ne223-quiet-native-glyph-prime"
    assert [cache_count(prime, "journal", point, 33) for point in ["before", "after"]] == [199, 199]
    official = json.loads((HERE / "official.json").read_text())
    archive = HERE / official["file"]
    assert archive.stat().st_size == official["size"] < 50_000_000
    assert hashlib.sha256(archive.read_bytes()).hexdigest() == official["sha256"]
    names_official = set()
    with tarfile.open(archive, "r:xz") as bundle:
        for member in bundle:
            name = PurePosixPath(member.name)
            assert member.isfile() and not name.is_absolute() and ".." not in name.parts
            assert not any(":" in part or "\\" in part or part.startswith("data_") for part in name.parts)
            assert member.name not in names_official
            names_official.add(member.name)
            raw = bundle.extractfile(member).read()
            expected = official["members"][member.name]
            assert len(raw) == member.size == expected["size"] and hashlib.sha256(raw).hexdigest() == expected["sha256"]
            target = root / "affected" / member.name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(raw)
    assert names_official == set(official["members"])
    affected = root / "affected/official"
    receipt = json.loads((affected / "process-receipt.json").read_text())
    assert receipt["exit_code"] == 0 and receipt["source_unchanged"] and receipt["shards"] == 2
    assert receipt["base"] == "56bb233db929973adf380a4631066a4c8b79dc58"
    source_before = json.loads((affected / "source-before.json").read_text())
    assert source_before == json.loads((affected / "source-after.json").read_text())
    for name, digest in frozen.items():
        assert source_before[name]["sha256"] == digest
        assert hashlib.sha256((root / "affected/source" / name).read_bytes()).hexdigest() == digest
    runner = (affected / "runner.log").read_text(encoding="utf8")
    selected = re.search(r"受影響的測試：([^\n]+)", runner).group(1).strip().split(",")
    assert len(selected) == len(set(selected)) == 15
    expected_checks = int(re.search(r"checks: (\d+), new failures: 0, known failures \(tests/known_failures.txt\): 0", runner).group(1))
    checks = 0
    actual = []
    for index in range(2):
        log = (affected / f"shards/shard_{index}.log").read_text(encoding="utf8")
        assert "SCRIPT ERROR" not in log and not re.search(r"^FAIL: ", log, re.M)
        checks += int(re.search(r"^checks: (\d+), failures: 0$", log, re.M).group(1))
        actual += re.findall(r"^SUITE_TIME (\S+) ", log, re.M)
    assert checks == expected_checks and sorted(actual) == sorted(selected)
    status = (affected / "status-after.txt").read_text()
    preparation = json.loads((affected / "preparation.json").read_text())
    assert "\n".join(line for line in status.splitlines() if line.startswith("??")) + "\n" == preparation["original_untracked_status"]
    assert {line[3:] for line in status.splitlines() if not line.startswith("??")} == set(frozen)
    print(json.dumps({"archive_sha256": record["sha256"], "members_verified": len(names), "recomputation": results,
        "permanent_regression": {"checks_each": 424, "old_failures": 1, "candidate_failures": 0},
        "glyph_diagnostic": {"unprimed_33px": [127, 200], "primed_33px": [199, 199],
            "control_prime_source_equal": True, "shared_timing_not_acceptance": True},
        "affected": {"groups": selected, "checks": checks, "members_verified": len(names_official),
            "source_files_held": len(source_before), "new_failures": 0, "known_failures": 0},
        "public_images_match_archived_originals": len(images),
        "world_frozen_rounds_each_resolution": 16, "issues": []}, indent=2))
