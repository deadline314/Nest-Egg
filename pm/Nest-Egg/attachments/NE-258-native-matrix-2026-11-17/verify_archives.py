"""Safely unpack original bytes, verify all SHA/size values, and recompute the final native gates."""
import argparse
import difflib
import hashlib
import importlib.util
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tarfile
import tempfile

HERE = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--temp-base", type=Path)
args = parser.parse_args()
coverage = json.loads((HERE / "coverage.json").read_text(encoding="utf8"))
accepted = coverage["accepted_runs"]
records = [json.loads(path.read_text(encoding="utf8")) for path in sorted(HERE.glob("*.tar.xz.json"))]
assert {record["file"] for record in records} == set(coverage["archives"])
required_space = sum(record["uncompressed_bytes"] for record in records if record["file"].startswith("native-")) + 1_000_000_000
temp_base = args.temp_base or Path(tempfile.gettempdir())
assert temp_base.is_dir() and shutil.disk_usage(temp_base).free > required_space, "choose --temp-base with at least 3.5 GB free"

def digest_file(path):
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()

module = importlib.util.spec_from_file_location("matrix_reader", HERE / "verify_matrix.py")
reader = importlib.util.module_from_spec(module)
module.loader.exec_module(reader)
all_names = set()
archive_results = []
with tempfile.TemporaryDirectory(prefix="ne258-offline-", dir=temp_base) as temporary:
    root = Path(temporary)
    for record in records:
        path = HERE / record["file"]
        assert path.stat().st_size == record["size"] < 50_000_000 and digest_file(path) == record["sha256"]
        names = set()
        with tarfile.open(path, "r|xz") as archive:
            for member in archive:
                name = PurePosixPath(member.name)
                assert member.isfile() and not name.is_absolute() and ".." not in name.parts
                assert not any(":" in part or "\\" in part or part in ["profile", ".", ""] for part in name.parts)
                assert member.name not in names and member.name not in all_names
                names.add(member.name)
                all_names.add(member.name)
                expected = record["members"][member.name]
                assert member.size == expected["size"]
                run = name.parts[1] if name.parts[0] == "runs" else ""
                selected = run in accepted + [coverage["blank_negative"], "ne258-matrix-default-quality-v1"]
                selected = selected or name.parts[0] != "runs" or name.name in ["matrix-index.json", "process-receipt.json", "console.log"]
                target = root.joinpath(*name.parts)
                sink = None
                if selected:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    sink = target.open("wb")
                digest = hashlib.sha256()
                total = 0
                with archive.extractfile(member) as source:
                    while chunk := source.read(1024 * 1024):
                        digest.update(chunk)
                        total += len(chunk)
                        if sink:
                            sink.write(chunk)
                if sink:
                    sink.close()
                assert total == member.size and digest.hexdigest() == expected["sha256"]
        assert names == set(record["members"])
        archive_results.append({"file": record["file"], "sha256": record["sha256"], "members_verified": len(names)})
    results = {run: reader.verify(root / "runs" / run, expect_full=not run.startswith("perf-")) for run in accepted}
    assert sum(row["frames"] for row in results.values()) == 273
    assert sum(row["metric_frames"] for row in results.values()) == 198
    assert sum(row["head_frames"] for row in results.values()) == 54
    assert sum(row["performance_pairs"] for row in results.values()) == 180
    maps = json.loads((root / "source/maps.json").read_text())
    assert set(maps) == set(accepted)
    for run, source_map in maps.items():
        receipt = json.loads((root / "runs" / run / "process-receipt.json").read_text())
        assert source_map == receipt["source_before_sha256"] == receipt["source_after_sha256"]
        for digest in source_map.values():
            assert digest_file(root / "source/blobs" / digest) == digest
    blank_folder = root / "runs" / coverage["blank_negative"]
    blank = json.loads((blank_folder / "matrix-index.json").read_text())
    process = json.loads((blank_folder / "process-receipt.json").read_text())
    assert process["exit_code"] == 1 and process["source_unchanged"] and not process["diagnostics"]
    idle = blank["exposure"]["states"]["idle"]
    mask, _ = reader.pixels(blank_folder, idle["files"]["mask_raw"], idle["width"], idle["height"], idle["mask_format"])
    assert (mask[..., 3] >= .999).sum() == idle["opaque_head_pixels"] == 0
    assert idle["white_ratio_upper_bound"] is None and not idle["bound_valid"] and blank["failures"] == 1
    legacy = json.loads((root / "runs/exposure-high-all7-v1/matrix-index.json").read_text())
    assert legacy["failures"] == 2
    assert legacy["exposure"]["states"]["fire-spread"]["muzzle_energy_at_raw_capture"] == 0
    assert all(legacy["exposure"]["states"]["fire-false-" + str(frame)]["muzzle_energy_at_raw_capture"] == 0 for frame in [1, 4, 8])
    assert reader.verify(root / "runs/ne258-matrix-default-quality-v1")["quality"] == "high"
    default_receipt = json.loads((root / "runs/ne258-matrix-default-quality-v1/process-receipt.json").read_text())
    assert not any(argument.startswith("--quality=") for argument in default_receipt["command"])
    argument_negative = json.loads((HERE / "argument-negative/receipt.json").read_text())
    argument_console = (HERE / "argument-negative/console.log").read_text(encoding="utf8")
    assert argument_negative["exit_code"] == 2 and argument_negative["source_unchanged"]
    assert "unknown --quality=unknown" in argument_console and "SCRIPT ERROR" not in argument_console
    assert "WEAPON_LIGHT_SELF_CHECK checks=8 failures=0" in (root / "checks/tool-v8-selfcheck.log").read_text(encoding="utf8")
    for row in json.loads((HERE / "summary-images.json").read_text()).values():
        source_path = PurePosixPath(row["source"].replace("\\", "/"))
        assert digest_file(root / "runs" / source_path.parts[-2] / source_path.name) == row["sha256"]
    old_low = json.loads((root / "runs/visual-low-v1/process-receipt.json").read_text())
    assert not old_low["source_unchanged"]
    changed = [name for name, digest in old_low["source_before_sha256"].items() if digest != old_low["source_after_sha256"].get(name)]
    assert changed == ["core/light_kit.gd"]
    before = (HERE / "parent-comment/light_kit-tested.gd.txt").read_bytes()
    after = (HERE / "parent-comment/light_kit-comment.gd.txt").read_bytes()
    assert hashlib.sha256(before).hexdigest() == old_low["source_before_sha256"][changed[0]]
    assert hashlib.sha256(after).hexdigest() == old_low["source_after_sha256"][changed[0]]
    a, b = before.splitlines(keepends=True), after.splitlines(keepends=True)
    change = [row for row in difflib.SequenceMatcher(a=a, b=b).get_opcodes() if row[0] != "equal"]
    assert len(change) == 1
    tag, i, j, k, l = change[0]
    assert tag == "insert" and l-k == 1 and b[k].lstrip().startswith(b"#") and b[:k]+b[l:] == a
    official = json.loads((root / "official-tools/receipt.json").read_text())
    assert official["natural_exit"] == 0 and official["selected_suites"] == 0 and official["sources_match_frozen_v8_before_and_after"]
    for name, row in official["only_two_final_tool_sources"].items():
        # Portable verification trusts the archived exact source bytes; checking a local checkout is optional.
        assert (root / "source/blobs" / row["sha256"]).stat().st_size == row["bytes"]
    control = subprocess.run([sys.executable, "-B", str(HERE / "verify_reader_controls.py"), str(root / "runs/perf-high-whole-v1")], capture_output=True, text=True)
    assert control.returncode == 0, (control.stdout, control.stderr)
    controls = json.loads(control.stdout)
    assert len(controls["negative_controls_rejected"]) == 15
    print(json.dumps({"archives": archive_results, "native_frames": 273, "metric_frames": 198, "head_frames": 54,
        "performance_pairs": 180, "source_blobs": coverage["guarded_source_blobs"], "blank_head_rejected": True,
        "reader_negative_controls": controls, "legacy_low_guard": "raw false retained; exact one-comment insertion verified",
        "official_selected_suites": 0, "failures": 0}, indent=2))
