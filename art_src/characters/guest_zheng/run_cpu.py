"""Serial CPU contracts for the retained-source Zheng delivery unit."""
import hashlib
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[3]
CASES = [
    "tools/comfyui/test_character_source.py",
    "tools/comfyui/test_stage_resolution.py",
    "tools/comfyui/test_source_alpha.py",
    "tools/comfyui/test_point_mask_cache.py",
    "tools/comfyui/test_underlap_material.py",
    "tools/comfyui/test_guest_contact_source.py",
    "tools/comfyui/test_crop_phase.py",
    "tools/comfyui/test_guest_material_registration.py",
    "tools/test_npc_joint_scope.py",
    "tools/story/test_ch2_guest_cast.py",
    "art_src/characters/guest_zheng/audit_sources.py",
    "art_src/characters/guest_zheng/verify_story_outcomes.py",
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    if Path(args.tag).name != args.tag or "/" in args.tag or "\\" in args.tag:
        raise ValueError("tag must be one new evidence directory name")
    OUT = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs" / args.tag
    OUT.mkdir(exist_ok=False)
    receipts = []
    for source in CASES:
        path = ROOT / source
        before = hashlib.sha256(path.read_bytes()).hexdigest()
        command = [sys.executable, "-X", "utf8", source]
        result = subprocess.run(command, cwd=ROOT, capture_output=True,
                                env={**os.environ, "PYTHONUTF8": "1"})
        log = path.stem + ".log"
        (OUT / log).write_bytes(result.stdout + result.stderr)
        count = re.search(rb"Ran (\d+) tests?", result.stderr)
        receipt = dict(source=source, command=command, exit_code=result.returncode,
                       tests=int(count[1]) if count else None, source_sha256=before,
                       source_unchanged=before == hashlib.sha256(path.read_bytes()).hexdigest(),
                       log=log, log_sha256=hashlib.sha256((OUT / log).read_bytes()).hexdigest())
        receipts.append(receipt)
        print(path.stem, receipt["tests"], result.returncode, flush=True)
    (OUT / "receipt.json").write_text(json.dumps(receipts, indent=2) + "\n", encoding="utf8")
    return int(any(r["exit_code"] or not r["source_unchanged"] for r in receipts))


if __name__ == "__main__":
    raise SystemExit(main())
