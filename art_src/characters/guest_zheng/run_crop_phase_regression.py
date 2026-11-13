"""Preserve frozen-old red and optional-grid green without touching live artwork."""
import hashlib
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[3]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    if not args.tag or Path(args.tag).name != args.tag or "/" in args.tag or "\\" in args.tag:
        raise ValueError("tag must be one evidence folder name")
    OUT = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs" / args.tag
    OUT.mkdir(exist_ok=False)
    old = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs/cut_layers-before-crop-phase.py.txt"
    sources = [ROOT / "tools/comfyui" / name for name in ("cut_layers.py", "crop_phase.py", "check_spec.py", "test_crop_phase.py")]
    sources += [Path(__file__), old]
    with zipfile.ZipFile(OUT / "sourcebytes.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sources:
            archive.writestr(path.relative_to(ROOT).as_posix(), path.read_bytes())
    receipt = dict(classification="CPU crop sampling regression; not Godot normal or native acceptance", cases=[])
    for label, extra in (("frozen-before", {"CUT_UNDER_TEST": str(old)}), ("current", {})):
        result = subprocess.run([sys.executable, "-X", "utf8", "tools/comfyui/test_crop_phase.py"], cwd=ROOT,
                                env={**os.environ, **extra}, capture_output=True)
        log = OUT / (label + ".log")
        log.write_bytes(result.stdout + result.stderr)
        receipt["cases"].append(dict(case=label, exit_code=result.returncode,
                                     log_sha256=hashlib.sha256(log.read_bytes()).hexdigest()))
    receipt["sources"] = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    receipt["sourcebytes_zip_sha256"] = hashlib.sha256((OUT / "sourcebytes.zip").read_bytes()).hexdigest()
    receipt["passed"] = receipt["cases"][0]["exit_code"] != 0 and receipt["cases"][1]["exit_code"] == 0
    (OUT / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf8")
    print(json.dumps(receipt, indent=2))
    return int(not receipt["passed"])


if __name__ == "__main__":
    raise SystemExit(main())
