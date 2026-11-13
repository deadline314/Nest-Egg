"""Compare the original production source after removing explicit presentation verbs only."""
import dataclasses
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT / "tools/story"))
import ch2_source

PRESENTATION = {"actor", "scene", "stage", "camera", "pose", "move", "wait", "reach", "prop", "prop_move",
                "prop_hold", "prop_release", "prop_visible", "gesture"}


def project(data):
    data = json.loads(json.dumps(data, ensure_ascii=False))
    for segment in data["segments"].values():
        segment["steps"] = [step for step in segment["steps"] if step.get("do") not in PRESENTATION]
    return data


def digest(data):
    return hashlib.sha256(json.dumps(data, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def main():
    folder = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs"
    baseline = folder / "story-before-presentation-projection.json"
    before = project(json.loads(baseline.read_text(encoding="utf8")))
    after = project(dataclasses.asdict(ch2_source.build_source()))
    result = dict(equal=before == after, before_sha256=digest(before), after_sha256=digest(after),
                  excluded_verbs=sorted(PRESENTATION),
                  scope="all original identity/speakers/lines/options/when/completion/on_cancel/flags/quests/documents/transactions retained",
                  note="v2 also excludes scene camera/initial prop presentation. The earlier projection kept scene, so its historical hash is not reused.")
    (folder / "story-outcomes-v2.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf8")
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["equal"] else 1)


if __name__ == "__main__":
    main()
