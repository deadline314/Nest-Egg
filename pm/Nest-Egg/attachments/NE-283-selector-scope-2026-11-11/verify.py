"""Check preserved bytes, old-selector counterexamples and the frozen full run."""
import hashlib
import json
from pathlib import Path
import re
import zipfile


def verify():
    folder = Path(__file__).resolve().parent
    receipt = json.loads((folder / "receipt.json").read_bytes())
    assert hashlib.sha256((folder / "raw.zip").read_bytes()).hexdigest() == receipt["archive_sha256"]
    checks = 1
    with zipfile.ZipFile(folder / "raw.zip") as archive:
        names = archive.namelist()
        manifest = json.loads(archive.read("manifest.json"))
        assert len(names) == len(set(names)) == receipt["members"]
        assert set(names) == set(manifest) | {"manifest.json"}
        for name, expected in manifest.items():
            data = archive.read(name)
            assert len(data) == expected["bytes"], name
            assert hashlib.sha256(data).hexdigest() == expected["sha256"], name
            checks += 1
        controls = json.loads(archive.read("controls/before/results.json"))
        assert len(controls) == 5 and all(case["exit"] == 1 for case in controls)
        for case in controls:
            log = archive.read("controls/before/" + case["case"] + ".log").decode("utf8")
            assert "FAIL: " + case["case"] in log
            assert "FAILED (failures=1)" in log
            checks += 2
        green = archive.read("controls/after/19-tests.log").decode("utf8")
        assert "Ran 19 tests" in green and re.search(r"^OK\r?$", green, re.MULTILINE)
        assert "FAILED (" not in green
        audit = json.loads(archive.read("audit/workspace-before-after.json"))
        old = set(audit["current"]["selected"])
        new = set(audit["engine_visible"]["selected"])
        assert len(old) == 21 and len(new) == 35 and old <= new
        assert sorted(new - old) == audit["newly_selected"] and len(new - old) == 14
        candidate = json.loads(archive.read("formal/candidate.json"))
        finished = json.loads(archive.read("formal/exit.json"))
        assert finished["exit"] == 0 and finished["sources_unchanged"]
        assert finished["source_after"] == candidate["source_sha256"]
        assert len(candidate["source_sha256"]) == 15
        assert candidate["staged_bytes_match_test_sources"]
        for name, digest in candidate["source_sha256"].items():
            data = archive.read("formal/source/" + name)
            assert hashlib.sha256(data).hexdigest() == digest and b"\r\n" not in data
            checks += 1
        for name in ["select_tests.py", "test_select_tests.py"]:
            assert archive.read("source/current/" + name) == archive.read("formal/source/tools/" + name)
        total = 0
        for index in range(4):
            log = archive.read(f"formal/shard_{index}.log").decode("utf8")
            result = re.findall(r"^checks: (\d+), failures: (\d+)\r?$", log, re.MULTILINE)
            assert len(result) == 1 and int(result[0][1]) == 0
            assert "SCRIPT ERROR" not in log and "Parse Error" not in log
            total += int(result[0][0])
            checks += 3
        assert total == 98446
        summary = archive.read("formal/full.log").decode("utf8")
        assert "Running 88 groups in 4 processes" in summary
        assert "checks: 98446, new failures: 0, known failures (tests/known_failures.txt): 0" in summary
        assert "改到整個專案或測試流程本身，跑全部測試" in summary
        assert "SCRIPT ERROR" not in archive.read("formal/cold-import.log").decode("utf8")
        checks += 15
    print(f"NE-283 evidence: {checks} checks, 0 failures")


if __name__ == "__main__":
    verify()
