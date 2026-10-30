#!/usr/bin/env python3
"""Check controller flow against an existing ordinary save in an owned profile."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
from runtime_probe import run_case, write_json

PROJECT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=os.environ.get("GODOT"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.godot is None or not args.godot.is_file():
        parser.error("provide an existing Godot engine")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    (output / ".gitignore").write_text("*\n")
    (output / ".gdignore").touch()
    sources = {}
    for name in ["tools/controller_flow_probe.gd", "tools/run_controller_storage.py",
                 "tools/runtime_probe.py", "game/main.gd", "core/run_save_store.gd",
                 "tests/probes/controller_storage.gd", "tests/probes/controller_storage.tscn"]:
        target = output / "source" / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(PROJECT / name, target)
        sources[name] = hashlib.sha256(target.read_bytes()).hexdigest()
    slot = output / "slot"
    slot.mkdir()
    case = run_case("existing", args.godot.resolve(), output, 180, project=PROJECT,
                    scene="res://tests/probes/controller_storage.tscn", slot=slot)
    write_json(output / "receipt.json", {"case": case, "source_sha256": sources})
    print(json.dumps(case, indent=2))
    return 0 if case["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
