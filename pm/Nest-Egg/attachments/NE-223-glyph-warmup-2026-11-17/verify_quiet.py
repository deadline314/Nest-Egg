"""Recompute the original 33 ms budget separately from the probe's functional exit code."""
import hashlib
import json
import math
from pathlib import Path
import sys
from PIL import Image

base = Path(sys.argv[1])
budget = 33.0
failed = []
results = {}
for width, height in [(1280, 720), (1920, 1080)]:
    folder = base / ("native-" + str(width))
    report = json.loads((folder / ("quest-map-perf-" + str(width) + ".json")).read_text(encoding="utf8"))
    receipt = json.loads((folder / "process-receipt.json").read_text(encoding="utf8"))
    assert receipt["exit_code"] == 0 and receipt["source_unchanged"] and receipt["source_before"] == receipt["source_after"]
    for name, digest in receipt["source_before"].items():
        assert hashlib.sha256((base / "source" / name).read_bytes()).hexdigest() == digest
    console = (folder / "console.log").read_text(encoding="utf8")
    assert not any(marker in console for marker in ["SCRIPT ERROR", "ERROR:", "leaked", "Leaked", "orphan"])
    assert report["rounds"] == 16 and report["renderer"] == "forward_plus" and report["adapter"] == "AMD Radeon RX 9070 XT"
    assert report["resolution"] == [width, height] and not report["vsync"] and not report["shared_workload"]
    assert not report["issues"] and len(report["freeze_samples"]) == 16
    for row in report["freeze_samples"]:
        assert row["unchanged"] and row["before"] == row["after"]
        assert row["before"]["process_mode"] == 1
        assert not any(row["before"][name] for name in ["level_can_process", "player_can_process", "camera_can_process"])
    actions = ["idle", "pause", "journal", "region", "world", "back-region"]
    assert len(report["samples"]) == 16 * 7
    for action in actions:
        rows = [row for row in report["samples"] if row["action"] == action]
        assert [row["round"] for row in rows] == list(range(16))
        for row in rows:
            assert row["first_open"] == (row["round"] == 0)
            assert math.isfinite(row["frame_ms"]) and row["frame_ms"] > 0 and 0 <= row["input_ms"] <= row["frame_ms"]
            if action != "idle" and row["frame_ms"] > budget:
                failed.append({"width": width, **row})
        warm = sorted(row["frame_ms"] for row in rows[1:])
        expected = {"first_ms": rows[0]["frame_ms"], "warm_median_ms": warm[len(warm)//2],
                    "warm_p95_ms": warm[min(len(warm)-1, int(len(warm)*.95))], "warm_max_ms": warm[-1]}
        assert expected == report["summary"][action]
    retained = [row for row in report["samples"] if row["action"] == "retained"]
    assert [row["round"] for row in retained] == list(range(16))
    assert len({row["nodes"] for row in retained}) == 1 and {row["cache_entries"] for row in retained} == {1}
    for image in folder.glob("*.png"):
        with Image.open(image) as native:
            assert native.size == (width, height)
    results[str(width)] = {"summary": report["summary"], "stable_nodes": retained[0]["nodes"],
        "cache_entries": 1, "static_delta_bytes": retained[-1]["static_bytes"]-retained[0]["static_bytes"], "functional_checks_passed": True}
print(json.dumps({"budget_ms": budget, "results": results, "failed_raw_samples": failed,
    "performance_gate_passed": not failed, "scope": "33 ms input-to-post_draw gate; not physical display latency or controller verification"}, indent=2))
sys.exit(1 if failed else 0)
