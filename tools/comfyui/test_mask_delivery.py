"""Offline check: python tools/comfyui/test_mask_delivery.py (no model or GPU)."""
import json
import tempfile
import subprocess
import sys
from pathlib import Path
from unittest.mock import Mock, patch
from contextlib import nullcontext

import comfy_api
import comfy_guard
import sam_masks
import build_character
import cut_layers
from check_spec import check
from make_parts import near_leg_key


def main():
    common = Path(subprocess.check_output(["git", "rev-parse", "--path-format=absolute", "--git-common-dir"], text=True).strip())
    assert comfy_guard.LOCK_PATH == common.parent / "assets_src/work/comfy.lock"
    for code, message in [(0, "ok"), (0, "SCRIPT ERROR: bad resource"), (1, "failed")]:
        with patch.object(comfy_guard, "server_lock", return_value=nullcontext()), patch.object(build_character.subprocess, "run", return_value=subprocess.CompletedProcess([], code, message, "")):
            try:
                output = build_character.godot("--headless")
                assert code == 0 and message == "ok" and output == "ok"
            except SystemExit:
                assert code != 0 or message.startswith("SCRIPT ERROR:")
    root = Path(__file__).resolve().parents[2]
    recipe = json.loads((root / "tools/comfyui/recipes/enforcer.json").read_text())
    spec = json.loads((root / recipe["spec"]).read_text())
    assert not check(recipe, spec, True)[0]
    for valid in [True, False]:
        assert not check(recipe, dict(spec, armor_debris=valid), True)[0]
    for invalid in ["false", 0, 1, None, [], {}]:
        assert any("spec.armor_debris" in error for error in check(recipe, dict(spec, armor_debris=invalid), True)[0])
    spec["near_leg"]["stage"] = "missing"
    spec["parts"]["pelvis"]["seam"] = -1
    spec["groups"]["body"]["complete"]["stage_silhouette"] = "yes"
    spec["near_leg"]["root_overlap"] = -1
    spec["groups"]["armor_knee"]["outline"] = [[float("nan"), 0], [0, 1], [2, 3]]
    errors = check(recipe, spec, True)[0]
    assert len(errors) == 5 and all(any(where in error for error in errors) for where in (
        "spec.near_leg.stage", "spec.parts.pelvis.seam", "spec.groups.body.complete.stage_silhouette",
        "spec.near_leg.root_overlap", "spec.groups.armor_knee.outline"))
    with tempfile.TemporaryDirectory() as directory:
        out = Path(directory)
        debris_spec = {"id": "debris", "display_name": "debris", "scale": 1,
            "tex_px_per_wp": 1, "illustration_px_per_wp": 1, "ground_y": 8,
            "joints": {"hip": [4, 4]}, "bones": [{"name": "hip", "parent": ""}],
            "parts": {}, "glow": {},
            "weapon_anchor": {"bone": "hip", "from": "hip", "to": "hip", "dx": 0, "dy": 0, "reach": 1}}
        for setting in [None, False, True]:
            if setting is not None: debris_spec["armor_debris"] = setting
            spec_file = out / "debris.json"
            spec_file.write_text(json.dumps(debris_spec))
            with patch.object(sys, "argv", ["cut_layers", "--spec", str(spec_file), "--work", str(out), "--char", str(out / "skin"), "--rig", str(out / "rig.json")]):
                cut_layers.main()
            delivered = json.loads((out / "skin/character.json").read_text())
            assert delivered.get("armor_debris", True) is (True if setting is None else setting)
        manifest = out / "manifest.json"
        manifest.write_text('[{"step":"design","seed":33}]')
        build_recipe = dict(recipe, work=directory)
        recipe_file = out / "recipe.json"
        recipe_file.write_text(json.dumps(build_recipe))
        build = build_character.Build(recipe_file, False, None)
        with patch.object(build, "step_refine", return_value=[]), patch.object(build_character, "log"):
            build.run(["refine"])
        assert [entry["step"] for entry in json.loads(manifest.read_text())] == ["design", "refine"]
        source = out / "source.png"
        source.write_bytes(b"first underlayer")
        cfg = {"pos": [[1, 2]]}
        key = near_leg_key(cfg, source)
        assert near_leg_key(cfg, source) == key
        source.write_bytes(b"corrected underlayer")
        assert near_leg_key(cfg, source) != key
        assert near_leg_key({"pos": [[3, 4]]}, source) != near_leg_key(cfg, source)
        history = {"p": {"outputs": {"s1": {"images": [{"filename": "second", "subfolder": "", "type": "output"}]},
                                     "s0": {"images": [{"filename": "first", "subfolder": "", "type": "output"}]}}}}

        def get(path, **kwargs):
            return json.dumps(history).encode() if path.startswith("/history") else path.encode()

        with patch.object(comfy_api, "OUT", out), patch.object(comfy_api, "_get", get), \
                patch.object(comfy_api, "_post", return_value={"prompt_id": "p"}), \
                patch.object(comfy_guard, "ensure_server"), patch.object(comfy_guard, "Watchdog", return_value=Mock()):
            paths = comfy_api._run_once({}, "batch")
            assert {p.name for p in paths} == {"batch_s0_0.png", "batch_s1_0.png"}
            assert len({p.read_bytes() for p in paths}) == 2  # no overwritten masks
            history["p"]["outputs"].pop("s1")
            assert comfy_api._run_once({}, "single")[0].name == "single_0.png"  # Qwen cache unchanged

        def run(graph, job):
            savers = [key for key in graph if key.startswith("s")]
            paths = []
            for key in reversed(savers):  # execution order need not equal prompt order
                p = out / (f"{job}_{key}_0.png" if len(savers) > 1 else f"{job}_0.png")
                p.write_bytes(key.encode())
                paths.append(p)
            return paths

        with patch.object(sam_masks, "run", run), patch.object(sam_masks, "upload", return_value="input"), \
                patch.object(comfy_guard, "ensure_server"):
            for prompts in [["head"], ["head", "legs"]]:
                masks = sam_masks.segment("input", prompts, directory)
                assert [p.read_bytes() for p in masks.values()] == [f"s{i}".encode() for i in range(len(prompts))]
                jobs = {key: {"pos": [(1, 2)]} for key in prompts}
                masks = sam_masks.segment_points("input", directory, jobs)
                assert [p.read_bytes() for p in masks.values()] == [f"s{i}".encode() for i in range(len(prompts))]
    print("mask delivery: lock, source cache, batch mapping, spec validation, Godot failure detection passed")


if __name__ == "__main__":
    main()
