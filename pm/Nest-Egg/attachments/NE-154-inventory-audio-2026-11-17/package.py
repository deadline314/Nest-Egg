"""Preserve explicitly selected NE-154 evidence bytes; never include profiles."""
import hashlib
import io
import json
from pathlib import Path
import platform
import sys
import tarfile

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[3]
REVIEW = ROOT / "work/ne154-audio-independent-review"
PROBE = ROOT / "work/ne154-inventory-audio-20261117"
PROVIDED = Path("C:/NE/evidence-20261117/ne154-inventory-audio")
NATIVE = Path("C:/NE/evidence-20261117/ne154-audio-independent-review")


def sha(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def main():
    archive = OUT / "raw.tar.xz"
    if archive.exists():
        raise FileExistsError("Refuse to overwrite the preserved archive")
    members = {}
    categories = {}
    for name, folder in [("headless-original-v3", PROVIDED / "original-v3"),
                         ("headless-candidate-v3", PROVIDED / "candidate-v3"),
                         ("native-original", NATIVE / "native-original"),
                         ("native-candidate", NATIVE / "native-candidate")]:
        selected = [folder / "report.json", folder / "console.log"]
        selected += [folder / f"bus-{bus}.{ext}" for bus in ("Master", "SFX", "Music", "Ambience") for ext in ("f32", "wav")]
        selected += [folder / "melee-master.wav", folder / "melee-sfx.wav"]
        if name.startswith("native-"):
            selected += [folder / "inventory-context.png", folder / "process-receipt.json"]
        for path in selected:
            assert path.is_file(), path
            members[f"valid/{name}/{path.name}"] = path
        categories[name] = {"kind": "valid-9-case", "original_directory": str(folder)}
    members["historical/initial-stop-error/console.log"] = PROVIDED / "original/console.log"
    members["historical/initial-stop-error/probe.gd.txt"] = PROBE / "probe-initial-stop-error.gd.txt"
    members["historical/incorrect-pawn-fixture/probe.gd.txt"] = PROBE / "probe-initial-pawn-fixture.gd.txt"
    for name in ("original-final", "candidate-final"):
        for filename in ("report.json", "console.log"):
            members[f"historical/incorrect-pawn-fixture/{name}/{filename}"] = PROVIDED / name / filename
    for filename in ("REPORT.md", "verify.py", "verification.json", "run_native.py", "native-runs.json"):
        members[f"review/{filename}"] = REVIEW / filename
    review = json.loads((REVIEW / "verification.json").read_text(encoding="utf8"))
    sources = set(review["review_time_source_sha256"])
    sources.update(["tools/scenarios/scenario_base.gd", "autoload/progression.gd",
                    "ui/inventory/inventory_context.gd", "game/player/loadout.gd",
                    "game/player/player.gd", "core/audio/sound_bank.gd", "tools/comfyui/gpu_lock.py"])
    for name in sources:
        members[f"source/{name}"] = ROOT / name
    records = []
    with tarfile.open(archive, "w:xz", preset=6) as tar:
        for name, path in sorted(members.items()):
            assert "profile" not in Path(name).parts and path.is_file()
            data = path.read_bytes()
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mtime = 0
            info.mode = 0o644
            tar.addfile(info, io.BytesIO(data))
            records.append({"name": name, "size": len(data), "sha256": hashlib.sha256(data).hexdigest(), "original_source": str(path)})
    assert archive.stat().st_size < 100_000_000, "Archive exceeds requested 100 MB limit"
    godot = Path("C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe")
    runtime = {"godot_binary": str(godot), "godot_binary_sha256": sha(godot),
               "python_binary": sys.executable, "python_binary_sha256": sha(Path(sys.executable)),
               "python_version": sys.version, "platform": platform.platform(),
               "hash_time_scope": "Packaging-time binary hashes; native driver/adapter/process evidence is in preserved process receipts"}
    manifest = {"schema": "ne154-inventory-audio-archive-v1", "archive": {"file": archive.name, "size": archive.stat().st_size, "sha256": sha(archive)},
                "members": records, "valid_groups": categories, "runtime": runtime,
                "historical_scope": "Initial Ambience.stop SCRIPT ERROR produced no report; incorrect pawn fixture reports 9 rows/9 failures and 9 rows/1 failure are historical, not valid nine-case comparisons",
                "excluded": "All profile directories, APPDATA/LOCALAPPDATA user saves, shader/import caches; only explicitly allowlisted recording and source files are archived"}
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf8")
    print(json.dumps({"archive_bytes": archive.stat().st_size, "members": len(records), "archive_sha256": manifest["archive"]["sha256"]}))


if __name__ == "__main__":
    main()
