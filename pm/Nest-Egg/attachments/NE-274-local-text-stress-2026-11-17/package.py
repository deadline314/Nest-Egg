"""Preserve native capture evidence and exact source; never archive profiles."""
import hashlib
import io
import json
from pathlib import Path
import sys
import tarfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
WORK = ROOT / "work/ne274-scale-verification-20261117"
BASE = Path("C:/NE/evidence-20261117")


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def main():
    archive = HERE / "raw.tar.xz"
    if archive.exists():
        raise FileExistsError("Do not overwrite preserved evidence")
    members = {}
    for prefix, folder in (("historical/v1", BASE / "ne274-scale-verification"),
                           ("historical/v2", BASE / "ne274-scale-verification-v2"),
                           ("historical/v3-parse-error", BASE / "ne274-scale-verification-v3"),
                           ("final", BASE / "ne274-scale-verification-v4")):
        groups = ("original-negative", "self-check") if "v3-parse-error" in prefix else ("original-negative", "self-check", "normal", "large", "reduced")
        for group in groups:
            source = folder / group
            assert (source / "process-receipt.json").is_file(), source
            for path in source.iterdir():
                if path.is_file():
                    assert path.suffix in (".json", ".png", ".log"), path
                    members[f"{prefix}/{group}/{path.name}"] = path
    for filename in ("original-source-hashes.json", "dialogue_box_capture.gd.original.txt", "dialogue_box_capture.tscn.original.txt",
                     "settings.gd.original.txt", "ui_kit.gd.original.txt", "radio_card.gd.original.txt", "dialogue_layer.gd.original.txt",
                     "dialogue_box_capture.v1.txt", "dialogue_box_capture.v2.txt", "dialogue_box_capture.v3-parse-error.txt", "original_scale_check.gd", "original_scale_check.tscn",
                     "run.py", "verify.py", "verification.json", "run-receipts.json",
                     "ne274-scale-verification-v2-receipts.json", "ne274-scale-verification-v3-receipts.json", "ne274-scale-verification-v4-receipts.json"):
        members[f"review/{filename}"] = WORK / filename
    for name in ("tools/dialogue_box_capture.gd", "tools/dialogue_box_capture.tscn", "autoload/settings.gd",
                 "ui/ui_kit.gd", "ui/kit/radio_card.gd", "ui/dialogue_layer.gd", "tools/viewport_capture.gd",
                 "design/10-presentation/DESIGN.md", "data/levels/ch1_street.tres", "tools/comfyui/gpu_lock.py"):
        members[f"source/{name}"] = ROOT / name
    members["historical/original-mislabeled-large-text.png"] = ROOT / "pm/Nest-Egg/images/NE-274-large-text.png"
    records = []
    with tarfile.open(archive, "w:xz", preset=6) as tar:
        for name, path in sorted(members.items()):
            assert "profile" not in Path(name).parts and path.is_file(), path
            data = path.read_bytes()
            info = tarfile.TarInfo(name)
            info.size = len(data)
            info.mode = 0o644
            info.mtime = 0
            tar.addfile(info, io.BytesIO(data))
            records.append({"name": name, "size": len(data), "sha256": hashlib.sha256(data).hexdigest(), "source": str(path)})
    assert archive.stat().st_size < 100_000_000
    godot = Path("C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe")
    manifest = {"schema": "ne274-local-font-stress-v1", "archive": {"file": archive.name, "size": archive.stat().st_size, "sha256": digest(archive)},
                "members": records, "runtime": {"godot": str(godot), "godot_sha256": digest(godot), "python": sys.version},
                "scope": "Final five speakers/three phases at actual labels 11 or 17; public limit remains 1.2. Historical v1/v2 failures retained.",
                "excluded": "All profile directories and user save/settings/shader cache contents"}
    (HERE / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding="utf8")
    print(json.dumps({"members": len(records), **manifest["archive"]}))


if __name__ == "__main__":
    main()
