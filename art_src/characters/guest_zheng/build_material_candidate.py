"""Rebuild bounded candidates on CPU; native acceptance is a separate step."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
WORK = Path(__file__).resolve().parent
OUT = WORK / "repair_candidates/adoption-v1"


def main():
    OUT.mkdir(parents=True, exist_ok=False)
    before = {}
    for name in ("hand", "torso", "pelvis", "leg_lower"):
        for suffix in ("", "_normal"):
            path = ROOT / "art/characters/guest_zheng/parts" / (name + suffix + ".png")
            if path.exists():
                shutil.copyfile(path, OUT / path.name)
                before[path.relative_to(ROOT).as_posix()] = hashlib.sha256(path.read_bytes()).hexdigest()
    for name in ("hand", "torso", "pelvis", "leg_lower"):
        shutil.copyfile(WORK / "07_refined" / (name + ".png"), OUT / (name + "-source.png"))
    shutil.copyfile(WORK / "cut_registration.json", OUT / "old-cut-registration.json")
    shutil.copyfile(ROOT / "art/characters/guest_zheng/character.json", OUT / "old-character.json")
    shutil.copyfile(ROOT / "tools/comfyui/specs/guest_zheng_side.json", OUT / "old-spec.json")
    commands = [
        [sys.executable, "-X", "utf8", str(WORK / "configure_spec.py")],
        [sys.executable, "-X", "utf8", "tools/comfyui/check_spec.py", "--recipe", "tools/comfyui/recipes/guest_zheng.json", "--joints"],
        [sys.executable, "-X", "utf8", "tools/comfyui/refine_parts.py", "--spec", "tools/comfyui/specs/guest_zheng_side.json", "--work", str(WORK)],
        [sys.executable, "-X", "utf8", "tools/comfyui/build_character.py", "--recipe", "tools/comfyui/recipes/guest_zheng.json", "--from", "textures", "--to", "textures"],
        [sys.executable, "-X", "utf8", "tools/story/build_ch2_story.py"],
    ]
    receipt = dict(classification="CPU rebuild of material candidates; native pending", before=before, commands=[])
    for index, command in enumerate(commands):
        result = subprocess.run(command, cwd=ROOT, capture_output=True)
        log = OUT / (str(index) + ".log")
        log.write_bytes(result.stdout + result.stderr)
        receipt["commands"].append(dict(command=command, exit_code=result.returncode,
                                         log_sha256=hashlib.sha256(log.read_bytes()).hexdigest()))
        print(index, result.returncode, flush=True)
        if result.returncode:
            break
    (OUT / "rebuild.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf8")
    return int(any(case["exit_code"] for case in receipt["commands"]))


if __name__ == "__main__":
    raise SystemExit(main())
