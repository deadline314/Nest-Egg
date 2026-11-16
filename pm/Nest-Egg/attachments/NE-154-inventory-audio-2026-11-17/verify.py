"""Verify the portable raw archive, then use its unchanged frozen PCM reader.

Needs Python and numpy. No project checkout, Godot, device, network or work/ data
is needed for this offline verification. Only --out and --newline-map are written.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path, PurePosixPath
import sys
import tarfile
import tempfile

HERE = Path(__file__).resolve().parent


def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding="utf8"))


def extract_verified(archive, manifest, destination):
    expected = {record["name"]: record for record in manifest["members"]}
    assert len(expected) == len(manifest["members"]), "Duplicate manifest members"
    seen = set()
    with tarfile.open(archive, "r:xz") as tar:
        for member in tar:
            path = PurePosixPath(member.name)
            assert member.isfile() and not path.is_absolute()
            assert ".." not in path.parts and "\\" not in member.name and ":" not in member.name
            assert "profile" not in [part.lower() for part in path.parts]
            assert member.name in expected and member.name not in seen
            record = expected[member.name]
            assert member.size == record["size"]
            target = destination.joinpath(*path.parts).resolve()
            assert target.is_relative_to(destination.resolve())
            target.parent.mkdir(parents=True, exist_ok=True)
            h = hashlib.sha256()
            size = 0
            with tar.extractfile(member) as source, target.open("wb") as output:
                for block in iter(lambda: source.read(1024 * 1024), b""):
                    size += len(block)
                    h.update(block)
                    output.write(block)
            assert size == record["size"] and h.hexdigest() == record["sha256"], member.name
            seen.add(member.name)
    assert seen == set(expected), "Missing archive members"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=Path, default=HERE / "archive-verification.json")
    parser.add_argument("--newline-map", type=Path, default=HERE / "source-newline-map.json")
    args = parser.parse_args()
    manifest = read_json(HERE / "manifest.json")
    archive = HERE / manifest["archive"]["file"]
    assert archive.stat().st_size == manifest["archive"]["size"] < 100_000_000
    assert sha(archive) == manifest["archive"]["sha256"], "Archive SHA mismatch"
    result = {"schema": "ne154-portable-archive-verification-v1", "archive_sha256": sha(archive),
              "members_verified": len(manifest["members"]), "pairs": [],
              "scope": "Frozen actual-page/sample-clock verification; no human hearing/full chapter claim"}
    with tempfile.TemporaryDirectory(prefix="ne154-archive-") as temporary:
        payload = Path(temporary)
        extract_verified(archive, manifest, payload)
        source_root = payload / "source"
        sys.path.insert(0, str(source_root / "tools/audio"))
        spec = importlib.util.spec_from_file_location("ne154_frozen_review", payload / "review/verify.py")
        review = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(review)
        assert Path(review.melee_pcm_reader.__file__).resolve() == (source_root / "tools/audio/melee_pcm_reader.py").resolve()
        review.ROOT = source_root
        review.OUT = payload / "checks"
        # Only the reader path adapter changes: same frozen verifier functions,
        # same frozen reader, same actual samples, same 28 rejection controls.
        for pair_name, original_name, candidate_name in [
            ("headless-v3", "headless-original-v3", "headless-candidate-v3"),
            ("independent-native", "native-original", "native-candidate"),
        ]:
            records = []
            for group_name in (original_name, candidate_name):
                folder = payload / "valid" / group_name
                recording = review.verify_recording(folder)
                recording["folder"] = f"archive:valid/{group_name}"
                if group_name.startswith("native-"):
                    receipt = read_json(folder / "process-receipt.json")
                    expected_exit = 1 if group_name == "native-original" else 0
                    assert receipt["exit_code"] == receipt["expected_exit_code"] == expected_exit
                    assert not receipt["diagnostic_lines"] and receipt["source_unchanged"]
                    assert receipt["source_before_sha256"] == receipt["source_after_sha256"]
                    assert all(sha(source_root / name) == value for name, value in receipt["source_before_sha256"].items())
                    assert recording["display"] == "Windows" and recording["driver"] == "WASAPI"
                    assert recording["adapter"] == "AMD Radeon RX 9070 XT"
                    text = (folder / "console.log").read_text(encoding="utf8")
                    assert "Vulkan" in text and "Forward+" in text
                    assert (folder / "inventory-context.png").is_file()
                    recording["producer_exit_code"] = receipt["exit_code"]
                records.append(recording)
            comparisons = []
            for original, candidate in zip(records[0]["cases"], records[1]["cases"]):
                assert original["name"] == candidate["name"]
                equal = {name: original[name] == candidate[name] for name in ("return", "before", "after")}
                assert all(equal.values())
                comparisons.append({"name": original["name"], **equal})
            result["pairs"].append({"name": pair_name, "original": records[0], "candidate": records[1],
                                    "progression_comparisons": comparisons})
        history = payload / "historical"
        assert "SCRIPT ERROR: Invalid call. Nonexistent function 'stop'" in (history / "initial-stop-error/console.log").read_text(encoding="utf8")
        assert "Ambience.stop()" in (history / "initial-stop-error/probe.gd.txt").read_text(encoding="utf8")
        history_results = []
        for name, count in (("original-final", 9), ("candidate-final", 1)):
            report = read_json(history / "incorrect-pawn-fixture" / name / "report.json")
            assert len(report["cases"]) == 9 and len(report["problems"]) == count
            pawn = next(case for case in report["cases"] if case["name"] == "pawn-refused")
            assert pawn["events"] == [] and pawn["return"] is False
            assert pawn["before"]["credits"] == pawn["after"]["credits"] == 0
            history_results.append({"group": name, "rows": 9, "failed": count, "valid_nine_case_fixture": False})
        result["historical_checks"] = {"initial_script_error_preserved": True, "incorrect_pawn_reports": history_results}
        newline_map = []
        for record in manifest["members"]:
            if not record["name"].startswith("source/"):
                continue
            raw = (payload / record["name"]).read_bytes()
            if Path(record["name"]).suffix not in (".gd", ".tscn", ".txt", ".json", ".godot", ".py"):
                continue
            lf = raw.replace(b"\r\n", b"\n")
            newline_map.append({"member": record["name"], "raw_sha256": hashlib.sha256(raw).hexdigest(),
                                "crlf_pairs": raw.count(b"\r\n"), "lone_cr": raw.count(b"\r") - raw.count(b"\r\n"),
                                "crlf_to_lf_sha256": hashlib.sha256(lf).hexdigest()})
        audio_only = {}
        for name in ("weapons", "upgrades", "shop", "pawn", "cyber"):
            original = (source_root / f"work/ne154-inventory-audio-20261117/original-{name}.gd.txt").read_bytes().replace(b"\r\n", b"\n").decode("utf8")
            candidate = (source_root / f"ui/inventory/pages/{name}_page.gd").read_bytes().replace(b"\r\n", b"\n").decode("utf8")
            expected = original.replace('\tSfx.play(&"reload_done", -6.0)\n', '') if name == "weapons" else original.replace('&"empty"', '&"ui_error"').replace('&"reload_done"', '&"ui_confirm"')
            audio_only[name] = expected == candidate
            assert audio_only[name]
        result["expected_audio_only_source_transform_after_explicit_crlf_to_lf"] = audio_only
        result["negative_controls_rejected"] = sum(len(record["negative_controls"]) for pair in result["pairs"] for record in (pair["original"], pair["candidate"]))
        assert result["negative_controls_rejected"] == 28
        args.newline_map.write_text(json.dumps({"contract": "Raw archive bytes and SHA are retained; this mapping is analysis-only CRLF-to-LF normalization", "members": newline_map}, indent=2), encoding="utf8")
    args.out.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding="utf8")
    print(json.dumps({"archive_bytes": manifest["archive"]["size"], "members_verified": result["members_verified"],
                      "valid_recordings": 4, "case_windows": 36, "negative_controls_rejected": 28,
                      "result": "Both pairs: 9/9 Progression outcomes identical; audio semantic failures 9 -> 0"}))


if __name__ == "__main__":
    main()
