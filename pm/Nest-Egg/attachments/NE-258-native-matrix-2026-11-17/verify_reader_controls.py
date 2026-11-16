"""Keep reported PASS flags while corrupting one real timing invariant at a time."""
import copy
import importlib.util
import json
from pathlib import Path
import sys
import tempfile

module = importlib.util.spec_from_file_location("matrix_reader", Path(__file__).with_name("verify_matrix.py"))
reader = importlib.util.module_from_spec(module)
module.loader.exec_module(reader)
original = Path(sys.argv[1])
data = json.loads((original / "matrix-index.json").read_text())
receipt = json.loads((original / "process-receipt.json").read_text())
assert reader.verify(original)["performance_pairs"] == 60

def slower_on(d, _receipt):
    record = d["performance"]["cases"]["whole_feature"]
    for pair in record["pairs"]:
        pair["on"]["raw_frame_ms"] = [value * 2 for value in pair["on"]["raw_frame_ms"]]
        pair["on"]["median_ms"] = reader.upper_median(pair["on"]["raw_frame_ms"])
        pair["ratio"] = pair["on"]["median_ms"] / pair["off"]["median_ms"]
    record["paired_median_ratio"] = reader.upper_median([pair["ratio"] for pair in record["pairs"]])

cases = {
    "engine_exit": lambda d, r: r.update(exit_code=1),
    "engine_error": lambda d, r: r.update(diagnostics=["SCRIPT ERROR: negative control"]),
    "source_drift": lambda d, r: r.update(source_unchanged=False),
    "reported_failure": lambda d, r: d.update(failures=1),
    "vsync_enabled": lambda d, r: d["performance"].update(vsync=1),
    "missing_pair": lambda d, r: d["performance"]["cases"]["whole_feature"]["pairs"].pop(),
    "empty_frame_window": lambda d, r: d["performance"]["cases"]["whole_feature"]["pairs"][0]["on"].update(raw_frame_ms=[]),
    "nonfinite_frame": lambda d, r: d["performance"]["cases"]["whole_feature"]["pairs"][0]["on"]["raw_frame_ms"].__setitem__(0, float("nan")),
    "zero_frame": lambda d, r: d["performance"]["cases"]["whole_feature"]["pairs"][0]["on"]["raw_frame_ms"].__setitem__(0, 0),
    "forged_median": lambda d, r: d["performance"]["cases"]["whole_feature"]["pairs"][0]["on"].update(median_ms=999),
    "missing_projectile": lambda d, r: d["performance"]["cases"]["whole_feature"]["pairs"][0]["on"].update(projectiles_spawned=999),
    "wrong_body_glow": lambda d, r: d["performance"]["cases"]["whole_feature"]["pairs"][0]["on"].update(body_glow_radius_min=150),
    "disabled_on_light": lambda d, r: d["performance"]["cases"]["whole_feature"]["pairs"][0]["on"].update(gun_enabled=False),
    "forged_ratio": lambda d, r: d["performance"]["cases"]["whole_feature"].update(paired_median_ratio=0),
    "consistent_raw_timing_exceeds_105_percent": slower_on,
}
rejected = []
with tempfile.TemporaryDirectory(prefix="ne258-reader-controls-") as temporary:
    folder = Path(temporary)
    for name, corrupt in cases.items():
        candidate, process = copy.deepcopy(data), copy.deepcopy(receipt)
        corrupt(candidate, process)
        (folder / "matrix-index.json").write_text(json.dumps(candidate))
        (folder / "process-receipt.json").write_text(json.dumps(process))
        try:
            reader.verify(folder)
        except AssertionError:
            rejected.append(name)
        else:
            raise AssertionError("reader accepted corrupted evidence: " + name)
assert len(rejected) == len(cases)
print(json.dumps({"valid_baseline_pairs": 60, "negative_controls_rejected": rejected, "failures": 0}, indent=2))
