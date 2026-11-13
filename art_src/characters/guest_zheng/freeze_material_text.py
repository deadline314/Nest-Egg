"""Freeze owned executable/delivery text to Git's LF before final native sources.

Provider records, original model outputs and old evidence are never normalized.
Original bytes of changed delivery text are preserved in a separate raw archive.
"""
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[3]
WORK = Path(__file__).resolve().parent
OUT = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs"


def main():
    target = OUT / "material-lf-freeze-v1-original-text.zip"
    if target.exists():
        raise ValueError("Keep previous byte receipt; choose a new freeze version")
    names = ["tools/comfyui/cut_layers.py", "tools/comfyui/crop_phase.py", "tools/comfyui/check_spec.py",
             "tools/comfyui/test_crop_phase.py", "tools/comfyui/test_guest_material_registration.py",
             "tools/comfyui/specs/guest_zheng_side.json", "tools/comfyui/recipes/guest_zheng.json",
             "art/characters/guest_zheng/character.json", "art/rigs/guest_zheng.json",
             "art/motion/guest_zheng.json", "data/story/ch2_heron.json",
             "art_src/characters/guest_zheng/hand_contact.json", "art_src/characters/guest_zheng/cut_registration.json"]
    files = [ROOT / name for name in names] + list(WORK.glob("*.py"))
    records = []
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in dict.fromkeys(files):
            before = path.read_bytes()
            after = before.replace(b"\r\n", b"\n")
            if before != after:
                archive.writestr(path.relative_to(ROOT).as_posix(), before)
                path.write_bytes(after)
            records.append(dict(path=path.relative_to(ROOT).as_posix(), changed=before != after,
                                before_sha256=hashlib.sha256(before).hexdigest(),
                                after_sha256=hashlib.sha256(after).hexdigest()))
    receipt = dict(classification="owned delivery text LF; provider/job/raw evidence excluded",
                   preserved_original_archive=target.name, archive_sha256=hashlib.sha256(target.read_bytes()).hexdigest(),
                   files=records)
    (OUT / "material-lf-freeze-v1.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf8", newline="\n")
    print(len(records), "files;", sum(record["changed"] for record in records), "LF conversions")


if __name__ == "__main__":
    main()
