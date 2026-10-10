"""Offline check: python tools/comfyui/test_mask_delivery.py (no model or GPU)."""
import json
import tempfile
import subprocess
import sys
import io
from pathlib import Path
from unittest.mock import Mock, patch
from contextlib import nullcontext

import comfy_api
import comfy_guard
import sam_masks
import build_character
import cut_layers
import make_parts
import refine_parts
import numpy as np
from PIL import Image
from check_spec import check
from make_parts import near_leg_key


def main():
    with tempfile.TemporaryDirectory() as directory:
        work = Path(directory)
        (work / "sam").mkdir()
        base = np.full((8, 8, 4), 255, np.uint8)
        Image.fromarray(base).save(work / "base_rgba.png")
        for name, left in [("arm", True), ("head", False)]:
            mask = np.zeros((8, 8), np.uint8)
            mask[:, :4] = 255 if left else 0
            mask[:, 4:] = 0 if left else 255
            Image.fromarray(mask).save(work / "sam" / f"{name}.png")
        spec_file = work / "spec.json"
        spec_file.write_text(json.dumps({"groups": {"arm": {"sam": ["arm"]}, "head": {"sam": ["head"]}},
            "parts": {"arm": {"group": "arm"}, "head": {"group": "head"},
                "connector": {"group": "head", "not_within": "arm"}},
            "joints": {"shoulder": [4, 4]}, "seam": 0}))
        make_parts.write_grey_composite(base, work / "base_grey.png")
        (work / "sam/.text_mask_cache.json").write_text(json.dumps({
            name: make_parts._text_mask_cache_entry(
                make_parts.text_mask_key(work / "base_grey.png", "base", name), work / "sam" / f"{name}.png")
            for name in ("arm", "head")
        }))
        argv = ["parts", "--spec", str(spec_file), "--work", str(work)]
        with patch.object(sys, "argv", argv), patch.object(make_parts, "segment", side_effect=AssertionError("offline fixture must not generate")):
            make_parts.main()
        sentinel = base.copy()
        sentinel[:, :, 0] = 17
        for name in ["head", "connector"]:
            Image.fromarray(sentinel).save(work / "06_parts" / f"{name}.png")
        saved = (work / "06_parts/head.png").read_bytes()
        with patch.object(sys, "argv", argv + ["--only", " arm "]):
            make_parts.main()
        assert (work / "06_parts/head.png").read_bytes() == saved
        assert (work / "06_parts/connector.png").read_bytes() != saved  # Indirect dependencies update even when their own group is unchanged.
        with patch.object(sys, "argv", argv):
            refine_parts.main()
        Image.fromarray(sentinel).save(work / "07_refined/head.png")
        saved = (work / "07_refined/head.png").read_bytes()
        with patch.object(sys, "argv", argv + ["--only", "arm"]):
            refine_parts.main()
        assert (work / "07_refined/head.png").read_bytes() == saved
        for module in [make_parts, refine_parts]:
            snapshot = {p: p.read_bytes() for p in work.rglob("*.png")}
            for selection in ["", "unknown", "arm,,head"]:
                with patch.object(sys, "argv", argv + ["--only", selection]), patch.object(sys, "stderr", io.StringIO()):
                    try:
                        module.main()
                    except SystemExit as error:
                        assert error.code == 2
                    else:
                        raise AssertionError("invalid selective step must fail")
                assert snapshot == {p: p.read_bytes() for p in work.rglob("*.png")}

    # Text-mask cache regression: the same-sized source can change, and both
    # base_grey and per-stage grey inputs must be regenerated from current RGBA.
    with tempfile.TemporaryDirectory() as directory:
        work = Path(directory)
        (work / "sam").mkdir()
        (work / "04_stages/sam_P").mkdir(parents=True)
        (work / "05_groups").mkdir()
        rgba = np.zeros((8, 8, 4), np.uint8)
        rgba[1:7, 1:7] = (80, 20, 10, 255)
        Image.fromarray(rgba).save(work / "base_rgba.png")
        # Stale same-size gray reference and masks simulate a source edit that
        # the old file-exists-only logic silently accepted.
        Image.new("RGB", (8, 8), (10, 10, 10)).save(work / "base_grey.png")
        Image.new("L", (8, 8), 255).save(work / "sam/body.png")
        stage = rgba.copy()
        stage[2:6, 2:6] = (20, 40, 90, 255)
        Image.fromarray(stage).save(work / "04_stages/P.png")
        Image.new("L", (8, 8), 255).save(work / "04_stages/sam_P/body.png")
        spec_file = work / "cache_spec.json"
        spec_file.write_text(json.dumps({
            "id": "cache",
            "groups": {"body": {"sam": ["body"], "complete": {"stage": "P", "occluders": [], "trim": 0, "edge_trim": 0}}},
            "stages": [{"name": "P", "prompt": "peeled body"}],
            "parts": {"body": {"group": "body"}},
            "joints": {"hip": [4, 4]},
            "seam": 0,
        }))
        calls = []

        def record_segment(image_path, prompts, out_dir, threshold=0.4, refine=2):
            calls.append((Path(image_path).read_bytes(), tuple(prompts), threshold, refine))
            Path(out_dir).mkdir(parents=True, exist_ok=True)
            for prompt in prompts:
                Image.new("L", (8, 8), 255).save(Path(out_dir) / f"{make_parts.slug(prompt)}.png")
            return {prompt: Path(out_dir) / f"{make_parts.slug(prompt)}.png" for prompt in prompts}

        argv = ["parts", "--spec", str(spec_file), "--work", str(work), "--no-complete"]
        with patch.object(sys, "argv", argv), patch.object(make_parts, "segment", side_effect=record_segment):
            make_parts.main()
            assert len(calls) == 2  # base and stage masks have no valid source-keyed cache yet
            assert Image.open(work / "base_grey.png").convert("RGB").tobytes() != Image.new("RGB", (8, 8), (10, 10, 10)).tobytes()
            calls.clear()
            make_parts.main()
            assert calls == []  # unchanged source reuses a valid mask cache

            changed_base = rgba.copy()
            changed_base[0, 0] = (255, 0, 0, 255)  # same dimensions, one changed pixel
            Image.fromarray(changed_base).save(work / "base_rgba.png")
            changed_stage = stage.copy()
            changed_stage[0, 1] = (0, 255, 0, 255)
            Image.fromarray(changed_stage).save(work / "04_stages/P.png")
            make_parts.main()
            assert {call[1] for call in calls} == {("body",)}
            assert len(calls) == 2  # changed base and changed stage each invalidate their own masks

    # A peeled stage must remain registered to the base canvas; fail before exporting any part PNG.
    with tempfile.TemporaryDirectory() as directory:
        work = Path(directory)
        (work / "sam").mkdir()
        (work / "04_stages").mkdir()
        Image.new("RGBA", (8, 8), (50, 20, 10, 255)).save(work / "base_rgba.png")
        stage_path = work / "04_stages/P.png"
        Image.new("RGBA", (6, 6), (30, 70, 100, 255)).save(stage_path)
        spec_path = work / "size_spec.json"
        spec_path.write_text(json.dumps({
            "id": "stage-size",
            "groups": {"body": {"sam": ["body"], "complete": {"stage": "P", "occluders": [], "trim": 0, "edge_trim": 0}}},
            "stages": [{"name": "P", "prompt": "peeled body"}],
            "parts": {"body": {"group": "body"}},
            "joints": {"hip": [4, 4]},
            "seam": 0,
        }))
        argv = ["parts", "--spec", str(spec_path), "--work", str(work), "--no-complete"]

        def size_mask(image_path, prompts, out_dir, threshold=0.4, refine=2):
            size = Image.open(image_path).size
            target = Path(out_dir)
            target.mkdir(parents=True, exist_ok=True)
            paths = {}
            for prompt in prompts:
                path = target / f"{make_parts.slug(prompt)}.png"
                Image.new("L", size, 255).save(path)
                paths[prompt] = path
            return paths

        with patch.object(sys, "argv", argv), patch.object(make_parts, "segment", side_effect=size_mask):
            try:
                make_parts.main()
            except ValueError as error:
                message = str(error)
                assert str(stage_path) in message
                assert "expected (8, 8)" in message and "got (6, 6)" in message
            else:
                raise AssertionError("wrong-size peeled stage must fail before part export")
        assert not list((work / "06_parts").glob("*.png"))

    # Corrupt cache metadata and failed resegmentation must both fail closed.
    with tempfile.TemporaryDirectory() as directory:
        out = Path(directory) / "sam"
        out.mkdir()
        source = Path(directory) / "source.png"
        source_pixels = np.zeros((4, 4, 4), np.uint8)
        source_pixels[1:3, 1:3] = (90, 50, 20, 255)
        Image.fromarray(source_pixels).save(source)
        calls = []

        def record_mask(image_path, prompts, out_dir, threshold=0.4, refine=2):
            calls.append((tuple(prompts), threshold, refine))
            paths = {}
            for prompt in prompts:
                path = Path(out_dir) / f"{make_parts.slug(prompt)}.png"
                Image.new("L", (4, 4), 255).save(path)
                paths[prompt] = path
            return paths

        with patch.object(make_parts, "segment", side_effect=record_mask):
            make_parts.ensure_text_masks(source, ["cloth"], out, "stage:P")
            make_parts.ensure_text_masks(source, ["cloth"], out, "stage:P")
            assert len(calls) == 1
            make_parts.ensure_text_masks(source, ["cloth", "coat"], out, "stage:P")
            assert calls[-1][0] == ("coat",)  # a newly requested prompt has no cache entry
            make_parts.ensure_text_masks(source, ["cloth"], out, "stage:P", threshold=0.5)
            assert len(calls) == 3  # threshold/refine/model are part of the cache key
            # Replacing a same-size mask must invalidate the mask-SHA binding.
            mask_path = out / "cloth.png"
            Image.new("L", (4, 4), 0).save(mask_path)
            make_parts.ensure_text_masks(source, ["cloth"], out, "stage:P", threshold=0.5)
            assert len(calls) == 4
            (out / make_parts.TEXT_MASK_CACHE_NAME).write_text("not json")
            make_parts.ensure_text_masks(source, ["cloth"], out, "stage:P")
            assert len(calls) == 5  # malformed metadata is a cache miss, never trusted

            source_pixels[0, 0] = (1, 2, 3, 255)
            Image.fromarray(source_pixels).save(source)
            cache_path = out / make_parts.TEXT_MASK_CACHE_NAME
            old_mask = mask_path.read_bytes()
            try:
                with patch.object(make_parts, "segment", side_effect=RuntimeError("mock SAM failure")):
                    make_parts.ensure_text_masks(source, ["cloth"], out, "stage:P")
            except RuntimeError as error:
                assert "mock SAM failure" in str(error)
            else:
                raise AssertionError("failed SAM call must surface")
            assert mask_path.read_bytes() == old_mask  # failed regeneration preserves the prior source mask
            cache = json.loads(cache_path.read_text())
            assert "cloth" not in cache  # failed rerun cannot leave the old source key valid
            make_parts.ensure_text_masks(source, ["cloth"], out, "stage:P")
            assert mask_path.is_file() and "key" in json.loads(cache_path.read_text())["cloth"]
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
        (out / "06_parts").mkdir()
        (out / "overrides/refined").mkdir(parents=True)
        Image.new("RGBA", (8, 8), (0, 0, 0, 255)).save(out / "base_rgba.png")
        Image.new("RGBA", (8, 8), (0, 255, 0, 255)).save(out / "06_parts/panel.png")
        override = out / "overrides/refined/panel.png"
        Image.new("RGBA", (8, 8), (222, 0, 0, 255)).save(override)
        source_spec = dict(debris_spec, parts={"panel": {"from": "hip", "to": "hip", "mode": "upright", "uses": []}})
        spec_file.write_text(json.dumps(source_spec))
        argv = ["cut_layers", "--spec", str(spec_file), "--work", str(out), "--char", str(out / "skin"), "--rig", str(out / "rig.json")]
        with patch.object(sys, "argv", argv):
            cut_layers.main()
        texture = np.array(Image.open(out / "skin/parts/panel.png"))
        assert (texture[:, :, 0][texture[:, :, 3] >= 128] == 222).all()
        delivery = {p: p.read_bytes() for p in (out / "skin").rglob("*") if p.is_file() and "parts.tmp" not in p.parts}
        saved_rig = (out / "rig.json").read_bytes()
        for mode, size in [("RGB", (8, 8)), ("RGBA", (7, 8))]:
            Image.new(mode, size).save(override)
            with patch.object(sys, "argv", argv):
                try:
                    cut_layers.main()
                except ValueError as error:
                    assert str(override) in str(error)
                else:
                    raise AssertionError("invalid source override must fail before changing delivered textures")
            assert delivery == {p: p.read_bytes() for p in (out / "skin").rglob("*") if p.is_file() and "parts.tmp" not in p.parts}
            assert (out / "rig.json").read_bytes() == saved_rig
        override.unlink()
        Image.new("RGBA", (8, 8), (222, 0, 0, 255)).save(override)
        for mode, size, name in [("RGBA", (1, 1), "panel"), ("RGBA", (8, 8), "missing"), ("RGB", (13, 13), "panel")]:
            final_override = out / "overrides" / f"{name}.png"
            Image.new(mode, size).save(final_override)
            with patch.object(sys, "argv", argv):
                try:
                    cut_layers.main()
                except ValueError as error:
                    assert str(final_override) in str(error)
                else:
                    raise AssertionError("invalid final override must not replace existing delivery")
            assert delivery == {p: p.read_bytes() for p in (out / "skin").rglob("*") if p.is_file() and "parts.tmp" not in p.parts}
            assert (out / "rig.json").read_bytes() == saved_rig
            final_override.unlink()
        override.unlink()
        manifest = out / "manifest.json"
        manifest.write_text('[{"step":"design","seed":33}]')
        build_recipe = dict(recipe, work=directory)
        recipe_file = out / "recipe.json"
        recipe_file.write_text(json.dumps(build_recipe))
        build = build_character.Build(recipe_file, False, None)
        (out / "06_parts").mkdir(exist_ok=True)
        (out / "overrides").mkdir(exist_ok=True)
        build.char_dir = out / "skin"
        (build.char_dir / "parts").mkdir(exist_ok=True)
        for mode, size, name in [("RGBA", (7, 8), "head"), ("RGBA", (8, 8), "missing"), ("RGB", (8, 8), "head")]:
            override = out / "overrides" / f"{name}.png"
            Image.new(mode, size).save(override)
            Image.new("RGBA", (8, 8)).save(build.char_dir / "parts/head.png")
            with patch.object(build, "check"), patch.object(build_character, "run", return_value="fixture"), patch.object(build_character, "log"):
                try:
                    build.step_textures()
                except SystemExit as error:
                    assert "override" in str(error) and str(override) in str(error)
                else:
                    raise AssertionError("wrong-size or unknown override must stop texture delivery")
            override.unlink()
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
    print("mask delivery: lock, source cache, batch mapping, spec validation, Godot failure detection, selective output and atomic override rejection passed")


if __name__ == "__main__":
    main()
