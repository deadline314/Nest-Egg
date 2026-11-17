"""Read every archived byte, then check the camera acceptance evidence offline."""
from pathlib import Path, PurePosixPath
import hashlib
import json
import re
import tarfile


def main():
    root = Path(__file__).resolve().parent
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf8"))
    remaining = dict(manifest["members"])
    records = {}
    count = 0
    for archive, expected in manifest["archives"].items():
        assert Path(archive).name == archive and archive.endswith(".tar.gz")
        path = root / archive
        assert path.stat().st_size == expected["bytes"]
        with path.open("rb") as stream:
            assert hashlib.file_digest(stream, "sha256").hexdigest() == expected["sha256"]
        with tarfile.open(path, "r:gz") as bundle:
            for entry in bundle:
                name = PurePosixPath(entry.name)
                assert entry.isfile() and not name.is_absolute() and ".." not in name.parts
                expected_file = remaining.pop(entry.name)
                assert expected_file["archive"] == archive and entry.size == expected_file["bytes"]
                with bundle.extractfile(entry) as stream:
                    digest = hashlib.sha256()
                    retained = bytearray()
                    keep = entry.name.endswith((".json", "native.log", "console.log", "exit.txt", "shard_0.log", "shard_1.log"))
                    while chunk := stream.read(1024 * 1024):
                        digest.update(chunk)
                        if keep:
                            assert len(retained) + len(chunk) < 16 * 1024 * 1024
                            retained.extend(chunk)
                assert digest.hexdigest() == expected_file["sha256"], entry.name
                if keep:
                    records[entry.name] = bytes(retained).decode("utf8")
                count += 1
    assert not remaining

    def record(run, leaf):
        return records[f"raw/{run}/{leaf}"]

    def valid(run):
        result = json.loads(record(run, "result.json"))
        assert result["natural_exit"] == 0 and result["source_unchanged"], run
        assert json.loads(record(run, "source-before.json")) == json.loads(record(run, "source-after.json")), run
        log = record(run, "native.log")
        assert not any(marker in log for marker in ("SCRIPT ERROR", "ERROR:", "leaked", "still in use", "FAIL ")), run
        return log

    for resolution in ("1280x720", "1920x1080"):
        log = valid("candidate-framing-six-" + resolution)
        samples = re.findall(r"^ch1_\w+/\d+\s+1\.92\s+(\d+)\s+([\d.]+)%\s+(\d+)\s+(\d+)\s+OK[ \t\r]*$", log, re.M)
        assert len(samples) == 6
        assert all(31 <= float(ratio) <= 35 and int(front) >= 300 for height, ratio, front, back in samples)
    log = valid("candidate-motion-six-1280x720")
    samples = re.findall(r"離邊最近：左 (\d+) 右 (\d+) 上 (\d+) 下 (\d+)\s+鏡頭橫移最快 (\d+)", log)
    assert len(samples) == 6
    assert all(min(map(int, sample[:4])) >= 24 and int(sample[4]) <= 620 for sample in samples)
    assert "PROLOGUE_PLAY_PROBE failures=0" in valid("route-prologue_play-current")
    assert "CH1_FLOW_PROBE route=stay failures=0" in valid("route-current-data-ch1_flow-current")
    for run in ("camera-walk-final-audio-settle-current", "camera-walk-private-audio-settle-current", "camera-walk-private-audio-settle-level_wide"):
        assert valid(run).count("CAMERA_WALK ch1_") == 10
    assert "checks: 48991, new failures: 0, known failures" in record("official-d851", "console.log")
    assert record("official-d851", "exit.txt").strip() == "0"
    assert all("SCRIPT ERROR" not in record("official-d851", f"shard_{i}.log") for i in (0, 1))
    keys = ("actual_scene_id", "stage_camera_position", "stage_camera_zoom", "stage_holder_transform", "stage_layer", "stage_follows_level_viewport", "actors")
    for scene in ("ch1_t_egret_1", "ch1_c09_wake", "ch1_c14_home"):
        states = []
        for profile in ("current", "level_wide"):
            run = f"composition-v2-{scene}-{profile}"
            valid(run)
            state = json.loads(record(run, "composition-state.json"))
            assert state["valid_active_stage"] and state["actual_scene_id"] == scene
            assert state["stage_layer"] == 58 and not state["stage_follows_level_viewport"]
            states.append(state)
        assert all(states[0][key] == states[1][key] for key in keys)
        assert states[0]["underlying_level_zoom"] != states[1]["underlying_level_zoom"]
    for run in ("framing-motion-six-current-1280x720", "motion-real-native-ch1_stall", "motion-real-native-ch1_warehouse", "motion-control-stall-invulnerable", "route-ch1_flow-current", "composition-v2-ch1_p_k_wait-current"):
        result = json.loads(record(run, "result.json"))
        assert result["natural_exit"] == 1 and result["source_unchanged"], run
    assert "resources still in use" in record("camera-walk-candidate-current", "native.log")
    print(f"NE256_PACKET {count} archived members / 0 failures; natural whole-chapter combat remains unverified")


if __name__ == "__main__":
    main()
