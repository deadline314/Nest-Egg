#!/usr/bin/env python3
"""Actual first-death cup/cloth contacts, mid-hold cancellation and durable retry."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import time
from runtime_probe import run_case, write_json

PROJECT = Path(__file__).resolve().parents[1]
SOURCES = [
    "tests/probes/clinic_actions.gd", "tests/probes/clinic_actions.tscn",
    "tests/probes/clinic_completion.gd", "tests/probes/clinic_original.gd",
    "tools/run_save_probe.gd", "tools/runtime_probe.py", "tools/run_clinic_actions.py",
    "tools/story/clinic_staging.py", "tools/story/build_ch1_story.py",
    "tools/story/ch1_runtime_backend.py", "data/story/ch1_kasa.json",
    "data/cutscene/stages/ch1_revival_room.json", "data/cutscene/stage_proportions.json",
    "game/story_result_clinic.gd", "game/story_result_completion.gd",
    "game/cutscene/cutscene_player.gd", "game/cutscene/cutscene_actor.gd",
    "game/cutscene/stage_prop_hold.gd", "game/cutscene/stage_prop_binding.gd",
    "game/cutscene/stage_layers.gd", "game/cutscene/stage_library.gd",
    "game/cutscene/stage_sprite_geometry.gd",
    "assets_src/pipeline/clinic_contacts_generation.json",
    "assets_src/pipeline/story_staging_art.json", "tools/assets/story_staging_art.py",
    "art/environment/scene_props/revival_room_contacts/clinic_atlas.png",
    "art/environment/scene_props/revival_room_contacts/clinic_atlas_n.png",
]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, default=os.environ.get("GODOT"))
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.godot is None or not args.godot.is_file():
        parser.error("provide an existing engine with --godot or GODOT")
    output = args.output.resolve()
    output.mkdir(exist_ok=False)
    engine = args.godot.resolve()
    sources = {}
    for name in SOURCES:
        source = PROJECT / name
        dest = output / "source" / name
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, dest)
        sources[name] = hashlib.sha256(dest.read_bytes()).hexdigest()
    with engine.open("rb") as stream:
        engine_sha = hashlib.file_digest(stream, "sha256").hexdigest()
    receipt = {"engine_sha256": engine_sha, "source_sha256": sources, "cases": []}
    start = time.monotonic()
    for mode in ["normal_take", "retry_take", "write_take", "read_take"]:
        slot = output / (mode + "-slot")
        slot.mkdir()
        if mode == "read_take":
            source = output / "write_take-slot/pending-primary.json"
            payload = source.read_bytes()
            shutil.copyfile(source, slot / "slot.json")
            if (slot / "slot.json").read_bytes() != payload:
                raise ValueError("cold reader must use the original pending bytes")
            receipt["pending_sha256"] = hashlib.sha256(payload).hexdigest()
        case = run_case(mode, engine, output, 240, project=PROJECT,
                        scene="res://tests/probes/clinic_actions.tscn", slot=slot)
        receipt["cases"].append(case)
        receipt["wall_seconds"] = round(time.monotonic() - start, 3)
        write_json(output / "receipt.json", receipt)
        print(mode, "checks", case.get("result", {}).get("checks"),
              "passed", case["passed"], flush=True)
        if not case["passed"]:
            return 1
    print("first-clinic actual actions:", output / "receipt.json", flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
