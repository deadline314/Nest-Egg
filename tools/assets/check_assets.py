"""Check the free-asset pipeline (NE-57): size budget and licence coverage.

Usage: python tools/assets/check_assets.py

Fails (exit 1) when
  - art/environment grows past TOTAL_LIMIT_MB or a single file passes FILE_LIMIT_MB,
  - a pipeline entry uses a source asset that has no licence record (or a non-CC0 one) in assets_src/LICENSES.json.
Prints the largest files so the next thing to shrink is obvious.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "art" / "environment"
PIPELINE = ROOT / "assets_src" / "pipeline"
LICENSES = ROOT / "assets_src" / "LICENSES.json"
TOTAL_LIMIT_MB = 60.0       # the shared library (everything except the scene packs)
SCENE_LIMIT_MB = 160.0     # per-scene packs: art/environment/scene_props and art/environment/scenes (BG-11)
FILE_LIMIT_MB = 1.5
ALLOWED = {"CC0-1.0"}


def pipeline_sources() -> list[tuple[str, str]]:
    found = []
    for path in sorted(PIPELINE.glob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        for key, entries in data.items():
            if not isinstance(entries, list):
                continue
            for e in entries:
                for field in ("source", "model"):
                    if field in e:
                        found.append((f"{path.name}:{e.get('id', '?')}", e[field]))
    return found


def main() -> int:
    problems = []
    files = [(p, p.stat().st_size) for p in ART.rglob("*") if p.is_file() and p.suffix in (".png", ".webp", ".jpg")]
    is_scene = lambda p: p.relative_to(ART).parts[0] in ("scene_props", "scenes")  # noqa: E731
    shared = [(p, s) for p, s in files if not is_scene(p)]
    scene = [(p, s) for p, s in files if is_scene(p)]
    total = sum(s for _, s in shared) / 1048576
    scene_total = sum(s for _, s in scene) / 1048576
    print(f"art/environment (shared): {len(shared)} images, {total:.1f} MB (limit {TOTAL_LIMIT_MB} MB)")
    print(f"art/environment (scene packs): {len(scene)} images, {scene_total:.1f} MB (limit {SCENE_LIMIT_MB} MB)")
    if total > TOTAL_LIMIT_MB:
        problems.append(f"shared total {total:.1f} MB exceeds {TOTAL_LIMIT_MB} MB")
    if scene_total > SCENE_LIMIT_MB:
        problems.append(f"scene packs total {scene_total:.1f} MB exceeds {SCENE_LIMIT_MB} MB")
    for p, s in sorted(files, key=lambda t: -t[1])[:8]:
        print(f"  {s / 1048576:5.2f} MB  {p.relative_to(ROOT).as_posix()}")
    for p, s in files:
        if s / 1048576 > FILE_LIMIT_MB:
            problems.append(f"{p.relative_to(ROOT).as_posix()} is {s / 1048576:.2f} MB (limit {FILE_LIMIT_MB} MB)")
    licenses = json.loads(LICENSES.read_text(encoding="utf-8")) if LICENSES.exists() else {}
    for where, source in pipeline_sources():
        record = licenses.get(source)
        if record is None:
            problems.append(f"{where}: source '{source}' has no licence record (run fetch_assets.py)")
        elif record.get("license") not in ALLOWED:
            problems.append(f"{where}: source '{source}' is {record.get('license')}, only {sorted(ALLOWED)} allowed")
    for p in problems:
        print("FAIL ", p, file=sys.stderr)
    print("OK" if not problems else f"{len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
