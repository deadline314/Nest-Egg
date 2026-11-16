"""Recompute native weapon observations with the existing BG49 reader's original HDR/contrast math."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import numpy as np
from PIL import Image
import difflib

ROOT = Path(__file__).resolve().parents[2]
bundled_math = Path(__file__).resolve().parent / "verify_bg49_held.py"
module = importlib.util.spec_from_file_location("bg49", bundled_math if bundled_math.exists() else ROOT / "tools/verify_bg49_held.py")
BG = importlib.util.module_from_spec(module)
module.loader.exec_module(BG)

def pixels(folder, filename, width, height, fmt):
    raw = (folder / filename).read_bytes()
    dtype, channels = BG.FORMATS[fmt]
    assert width > 0 and height > 0 and len(raw) == width * height * channels * np.dtype(dtype).itemsize
    image = np.frombuffer(raw, dtype=dtype).reshape(height, width, channels).astype(np.float64)
    assert np.isfinite(image).all()
    return image, hashlib.sha256(raw).hexdigest()

def upper_median(values):
    return sorted(values)[len(values)//2]

def verify(folder, comment_mapping=None, expect_full=False):
    data = json.loads((folder / "matrix-index.json").read_text(encoding="utf8"))
    receipt = json.loads((folder / "process-receipt.json").read_text(encoding="utf8"))
    assert receipt["exit_code"] == 0 and not receipt["diagnostics"]
    source_guard = "raw_sources_unchanged"
    if not receipt["source_unchanged"]:
        assert comment_mapping is not None
        mapping = json.loads(comment_mapping.read_text(encoding="utf8"))
        before = (comment_mapping.parent / "light_kit-tested.gd.txt").read_bytes()
        after = (comment_mapping.parent / "light_kit-comment.gd.txt").read_bytes()
        assert hashlib.sha256(before).hexdigest() == mapping["tested_sha256"]
        assert hashlib.sha256(after).hexdigest() == mapping["published_comment_sha256"]
        a, b = before.splitlines(keepends=True), after.splitlines(keepends=True)
        changes = [row for row in difflib.SequenceMatcher(a=a, b=b).get_opcodes() if row[0] != "equal"]
        assert len(changes) == 1
        tag, i, j, k, l = changes[0]
        assert tag == "insert" and l-k == 1 and b[k].lstrip().startswith(b"#") and b[:k]+b[l:] == a
        changed = [name for name, sha in receipt["source_after_sha256"].items() if sha != receipt["source_before_sha256"].get(name)]
        assert changed == ["core/light_kit.gd"]
        assert receipt["source_before_sha256"][changed[0]] == mapping["tested_sha256"]
        assert receipt["source_after_sha256"][changed[0]] == mapping["published_comment_sha256"]
        source_guard = "raw_drift_preserved_exact_one_parent_comment_insert_verified"
    assert data["renderer"]["method"] == "forward_plus" and data["renderer"]["hdr_2d"]
    assert data["failures"] == 0 and all(row["passed"] for row in data["checks"])
    result = {"phase": data["phase"], "quality": data["quality"], "source_guard": source_guard, "frames": 0, "metric_frames": 0, "head_frames": 0, "performance_pairs": 0, "raw_sha256": {}}
    quality = {"low": 0, "medium": 1, "high": 2}[data["quality"]]
    guns = {"pistol", "rifle", "smg", "spread", "launcher", "laser", "railgun"}
    if expect_full:
        assert data["fixture"]["hidden_world_prompts"] > 0
        if data["phase"] == "visual":
            assert set(data["weapons"]) == guns and len(data["frames"]) == 91
            directions = {"right": (1, 0), "up": (.7, -.7), "down_left": (-.8, .6)}
            gallery = {record["name"]: record for record in data["frames"] if not record["metric"]}
            for gun in guns:
                for direction, vector in directions.items():
                    row = gallery[data["tag"] + "-" + gun + "-" + direction]
                    assert row["actual_weapon"] == gun and row["light_enabled"]
                    aim = np.asarray(vector, dtype=float)
                    aim /= np.linalg.norm(aim)
                    assert np.allclose(aim, row["aim"], atol=1e-6)
                    assert abs(np.arctan2(np.sin(row["actual_light_rotation"] - np.arctan2(aim[1], aim[0])), np.cos(row["actual_light_rotation"] - np.arctan2(aim[1], aim[0])))) < .05
        elif data["phase"] == "exposure":
            states = data["exposure"]["states"]
            expected = {"idle", "hurt", "block", "dash", "reload"} | {"fire-" + gun for gun in guns}
            expected |= {"fire-" + flag + "-" + str(frame) for flag in ["false", "true"] for frame in [1, 4, 8]}
            assert set(states) == expected
            assert all(states[name]["requires_active_muzzle"] for name in expected if name.startswith("fire-"))
        else:
            raise AssertionError("full coverage expectation is only for visual/exposure matrices")
    for record in data.get("frames", []):
        assert record["actual_quality"] == quality
        name = record["name"]
        raw, sha = pixels(folder, name + ".hdr.bin", record["width"], record["height"], record["format"])
        rgb = raw[..., :3]
        png = np.asarray(Image.open(folder / (name + ".png")).convert("RGB"), dtype=np.float64) / 255
        expected = np.where(rgb <= .0031308, rgb * 12.92, 1.055 * np.maximum(rgb, 0) ** (1/2.4) - .055)
        assert np.max(np.abs(png - np.clip(expected, 0, 1))) <= 1/255 + .00001
        result["raw_sha256"][name] = sha
        result["frames"] += 1
        metric = record["metric"]
        if not metric:
            continue
        raster_record = {"canvas_transform_values": record["world_to_image"], "density": 1,
                         "width": record["width"], "height": record["height"]}
        x, y = metric["enemy_feet"]
        body = BG.raster([x-9,y-44,18,40], raster_record)
        outer = BG.raster([x-29,y-64,58,80], raster_record)
        parts = BG.contrast(rgb, body, outer)
        for key, value in parts.items():
            assert abs(value - metric["parts"][key]) < 2e-6, (name, key, value, metric["parts"][key])
        assert body[2] * body[3] == metric["sample_pixels"]
        edge = BG.section(rgb @ [.2126,.7152,.0722], BG.raster([x-24,y,48,3], raster_record))
        below = BG.section(rgb @ [.2126,.7152,.0722], BG.raster([x-24,y+8,48,6], raster_record))
        assert edge.size and below.size
        edge_contrast = (float(edge.mean()) - float(below.mean())) / (float(below.mean()) + .02)
        assert abs(edge_contrast - metric["edge_contrast"]) < 2e-6
        contrast = max(parts["bright"], parts["dark"])
        distance = np.linalg.norm(np.array(metric["enemy_feet"]) - metric["player_feet"])
        assert abs(distance - 128) <= .01 and metric["enemy_floor"] and metric["body_fully_in_bounds"]
        if "visible_prompt_count" in metric:
            assert metric["visible_prompt_count"] == 0
        if "-on-sample-" in name:
            assert contrast >= .45 and edge_contrast >= 1
        else:
            assert "-off-sample-" in name and contrast < .45
        assert metric["body_glow_radius"] == (150 if "fixed_body150" in name or "-off-sample-" in name else 84)
        result["metric_frames"] += 1
    for name, record in data.get("exposure", {}).get("states", {}).items():
        assert record["bound_valid"] and record["source_held"] and record["expanded_geometry_fully_in_bounds"]
        if record.get("requires_active_muzzle"):
            assert record["muzzle_energy_at_raw_capture"] > 0 and 1 <= record["waited_render_frames"] <= 120
        files = record["files"]
        world, world_sha = pixels(folder, files["world_raw"], record["width"], record["height"], record["world_format"])
        mask, mask_sha = pixels(folder, files["mask_raw"], record["width"], record["height"], record["mask_format"])
        assert mask.shape[2] == 4
        yy, xx = np.nonzero(mask[...,3] > 0)
        assert len(xx)
        rect = [int(xx.min()), int(yy.min()), int(xx.max()-xx.min()+1), int(yy.max()-yy.min()+1)]
        assert rect == record["sample_rect"]
        opaque = int((mask[...,3] >= .999).sum())
        patch = BG.section(world[..., :3], rect)
        white = int((patch > .92).all(axis=2).sum())
        assert opaque > 0 and opaque == record["opaque_head_pixels"] and white == record["white_rectangle_pixels"]
        assert abs(white/opaque - record["white_ratio_upper_bound"]) < 1e-12 and white/opaque <= .02
        result["raw_sha256"][name] = {"world": world_sha, "mask": mask_sha}
        result["head_frames"] += 1
    if data.get("exposure"):
        normal, reduced = data["exposure"]["reduce_flashes"]
        assert not normal["reduced"] and reduced["reduced"]
        assert normal["projectiles_spawned"] > 0 and reduced["projectiles_spawned"] > 0
        assert normal["peak_jitter_radians"] > .01
        assert reduced["peak_jitter_radians"] < normal["peak_jitter_radians"] * .75
        assert normal["peak_muzzle_energy"] > 0
        assert reduced["peak_muzzle_energy"] < normal["peak_muzzle_energy"] * .75
    for variant, record in data.get("performance", {}).get("cases", {}).items():
        assert len(record["pairs"]) == 60 and record["controls_valid"] and data["performance"]["vsync"] == 0
        ratios = []
        totals = {"on": 0, "off": 0}
        for pair in record["pairs"]:
            for condition in ["on", "off"]:
                window = pair[condition]
                times = window["raw_frame_ms"]
                assert len(times) == 45 and all(np.isfinite(v) and v > 0 for v in times)
                assert abs(upper_median(times) - window["median_ms"]) < 1e-9
                assert window["projectiles_spawned"] == window["accepted_shots"]
                expected = 150 if variant == "fixed_body150" or condition == "off" else 84
                assert window["body_glow_radius_min"] == expected == window["body_glow_radius_max"]
                assert window["gun_enabled"] == (condition == "on")
                assert window["physics_frames"] > 0 and 0 <= window["reload_render_frames"] <= 45
                assert window["gun_energy"] > 0 if condition == "on" else True
                totals[condition] += window["projectiles_spawned"]
            ratio = pair["on"]["median_ms"] / pair["off"]["median_ms"]
            assert abs(ratio - pair["ratio"]) < 1e-9
            ratios.append(ratio)
        assert all(value > 0 for value in totals.values()) and totals == record["total_projectiles"]
        assert abs(upper_median(ratios) - record["paired_median_ratio"]) < 1e-9 and upper_median(ratios) <= 1.05
        result["performance_pairs"] += len(ratios)
    if expect_full:
        assert result["metric_frames"] == 66 if data["phase"] == "visual" else result["head_frames"] == 18
        result["full_matrix_coverage"] = True
    return result

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path)
    parser.add_argument("--comment-mapping", type=Path)
    parser.add_argument("--expect-full", action="store_true")
    args = parser.parse_args()
    print(json.dumps(verify(args.folder, args.comment_mapping, args.expect_full), indent=2))
