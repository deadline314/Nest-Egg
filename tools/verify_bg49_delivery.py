"""Verify archived original bytes and independently recompute BG49's six final runs."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import tempfile
import zipfile

import verify_bg49_held as pixels

FINAL = {
    f"native-bg49-{kind}-complete-{quality}-{version}": kind
    for kind, version in [("world", "v5"), ("held", "v6"), ("pool", "v5")]
    for quality in ["high", "low"]
}


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def verify(base):
    official = base / "official-changed-raw.zip"
    assert digest(official.read_bytes()) == "9be3ebe76c89abc4ba28dc0690c7dd18ed5189c101927de66464b7f4106db2fc"
    with zipfile.ZipFile(official) as z:
        manifest = json.loads(z.read("manifest.json"))
        assert set(z.namelist()) == set(manifest) | {"manifest.json"}
        for name, expected in manifest.items():
            raw = z.read(name)
            assert len(raw) == expected["bytes"] and digest(raw) == expected["sha256"]
        assert json.loads(z.read("exit.json"))["exit"] == 0
        assert b"158" in z.read("full.log")
        assert b"ERROR" not in z.read("full.log") and b"SCRIPT ERROR" not in z.read("logs/shard_0.log")
    archives = json.loads((base / "archives.json").read_bytes())
    cases = {case["case"]: case for case in archives}
    assert len(cases) == len(archives) and FINAL.keys() <= cases.keys()
    members = 0
    results = {}
    runtime = None
    for case in archives:
        manifested = {}
        complete = None
        with tempfile.TemporaryDirectory(prefix="bg49-archive-") as temporary:
            folder = Path(temporary).resolve()
            for chunk in case["chunks"]:
                archive = base / chunk["file"]
                raw = archive.read_bytes()
                assert len(raw) == chunk["bytes"] and digest(raw) == chunk["sha256"]
                with zipfile.ZipFile(archive) as z:
                    part = json.loads(z.read("manifest-part.json"))
                    full = json.loads(z.read("manifest-case.json"))
                    assert complete is None or complete == full
                    complete = full
                    assert len(part) == chunk["members"]
                    assert set(z.namelist()) == set(part) | {"manifest-part.json", "manifest-case.json"}
                    for name, expected in part.items():
                        path = PurePosixPath(name)
                        assert not path.is_absolute() and ".." not in path.parts and "\\" not in name
                        assert name not in manifested
                        value = z.read(name)
                        assert len(value) == expected["bytes"] and digest(value) == expected["sha256"]
                        manifested[name] = expected
                        if case["case"] in FINAL:
                            destination = folder.joinpath(*path.parts)
                            assert destination.resolve().is_relative_to(folder)
                            destination.parent.mkdir(parents=True, exist_ok=True)
                            destination.write_bytes(value)
            assert manifested == complete and len(manifested) == case["original_files"]
            members += len(manifested)
            if case["case"] not in FINAL:
                continue
            before = json.loads((folder / "source-before.json").read_bytes())
            receipt = json.loads((folder / "exit.json").read_bytes())
            assert receipt["exit"] == 0 and receipt["strict_clean"] and receipt["sources_unchanged"]
            assert before == receipt["source_after"]
            for name, sha in before.items():
                assert digest((folder / "source" / name).read_bytes()) == sha
            # Product and shared drawing sources must agree across all six
            # runs. Role-specific leaves are audited against their own receipt;
            # a world run's unused held leaf need not match the later v6 leaf.
            shared = {name: sha for name, sha in before.items()
                      if not name.startswith("tools/bg49_")}
            assert runtime is None or runtime == shared
            runtime = shared
            kind = FINAL[case["case"]]
            result = {"world": pixels.verify_world, "held": pixels.verify_held,
                      "pool": pixels.verify_pool}[kind](folder)
            if kind != "pool":
                source = (folder / "source/tools/ch1_readability_check.gd").read_text(encoding="utf8")
                import ast
                import re
                points = ast.literal_eval(re.search(r"const PROBES := (\{.*?\n\})", source, re.S).group(1))
                expected = {str(point[0]) for spots in points.values() for point in spots}
                assert len(expected) == result["points"] == 18
                assert {row["spot"] for row in result["observations"]} == expected
            if kind == "held":
                for report in folder.glob("*/bg49-held.json"):
                    for point in json.loads(report.read_bytes())["results"]:
                        if point["bg49"]["spot"] == "碼頭入口":
                            for record in point["bg55"]["records"]:
                                assert record["exposure"]
                                assert all(e["bound_valid"] and e["enemy_white_ratio_upper_bound"] <= .02
                                           for e in record["exposure"])
            results[case["case"]] = result
    assert results.keys() == FINAL.keys()
    return dict(cases=len(cases), original_members=members, final_runs=results,
                shared_source_files=len(runtime), all_original_bytes_verified=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("base", type=Path)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    result = verify(args.base)
    if args.out:
        args.out.write_bytes((json.dumps(result, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps({k: v for k, v in result.items() if k != "final_runs"}, indent=2))
