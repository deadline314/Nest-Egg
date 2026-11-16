"""Validate every original byte, then run the same wall gate against preserved before/after raw frames."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import subprocess
import sys
import tarfile
import tempfile
import re

HERE = Path(__file__).resolve().parent
receipt = json.loads((HERE / "archive.json").read_text(encoding="utf8"))
manifest = json.loads((HERE / "members.json").read_text(encoding="utf8"))
archive_path = HERE / receipt["archive"]
assert archive_path.stat().st_size == receipt["size"]
assert hashlib.sha256(archive_path.read_bytes()).hexdigest() == receipt["sha256"]
with tarfile.open(archive_path, "r:xz") as archive, tempfile.TemporaryDirectory(prefix="ne258-offline-") as temporary:
    root = Path(temporary)
    names = set()
    for member in archive.getmembers():
        name = PurePosixPath(member.name)
        assert member.isfile() and not name.is_absolute() and ".." not in name.parts and "profile" not in name.parts
        assert member.name not in names
        names.add(member.name)
        data = archive.extractfile(member).read()
        expected = manifest[member.name]
        assert len(data) == member.size == expected["size"] and hashlib.sha256(data).hexdigest() == expected["sha256"]
        selected = member.name == "source/verify_wall.py" or any(member.name.startswith("runs/" + run + "/") for run in
                   ["ne258-wall-candidate-v2-native", "ne258-wall-candidate-v4-native"])
        if selected:
            target = root.joinpath(*name.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
    assert names == set(manifest) and len(names) == receipt["members"]
    results = {}
    for run, expected_exit in [("ne258-wall-candidate-v2-native", 1), ("ne258-wall-candidate-v4-native", 0)]:
        command = [sys.executable, "-B", str(root / "source/verify_wall.py"), str(root / "runs" / run), "--gate"]
        result = subprocess.run(command, capture_output=True, text=True)
        assert result.returncode == expected_exit, (run, result.stdout, result.stderr)
        results[run] = {"exit_code": result.returncode, "expected_exit_code": expected_exit,
                        "wall_gate": "rejected original contradiction" if expected_exit else "passed corrected raw evidence"}
    official = json.loads((HERE / "official-AAE.json").read_text(encoding="utf8"))
    official_path = HERE / official["file"]
    assert official_path.stat().st_size == official["size"] and hashlib.sha256(official_path.read_bytes()).hexdigest() == official["sha256"]
    official_bytes = {}
    with tarfile.open(official_path, "r:xz") as official_archive:
        for member in official_archive.getmembers():
            path = PurePosixPath(member.name)
            assert member.isfile() and not path.is_absolute() and ".." not in path.parts and "profile" not in path.parts
            data = official_archive.extractfile(member).read()
            expected = official["members"][member.name]
            assert len(data) == expected["size"] and hashlib.sha256(data).hexdigest() == expected["sha256"]
            official_bytes[member.name] = data
    assert set(official_bytes) == set(official["members"])
    assert json.loads(official_bytes["source-before.json"]) == json.loads(official_bytes["source-after.json"])
    process = json.loads(official_bytes["process-receipt.json"])
    assert process["exit_code"] == 0 and process["source_unchanged"] and process["shards"] == 3
    counts = [re.search(rb"^checks: (\d+), failures: (\d+)", official_bytes[f"shards/shard_{i}.log"], re.M).groups() for i in range(3)]
    assert sum(int(row[0]) for row in counts) == 96249 and all(int(row[1]) == 0 for row in counts)
    print(json.dumps({"archive_sha256": receipt["sha256"], "members_verified": len(names), "recomputation": results,
        "official": {"sha256": official["sha256"], "members_verified": len(official_bytes), "checks": 96249,
        "source_files_unchanged": len(json.loads(official_bytes["source-before.json"])),
        "raw_exit_diagnostics": "retained; original repository compatibility policy, not silently removed"}}, indent=2))
