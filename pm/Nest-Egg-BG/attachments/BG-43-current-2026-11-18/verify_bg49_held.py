"""Independently recompute held BG-49 observations from original floating bytes."""
from __future__ import annotations

import argparse
import ast
import hashlib
import json
from pathlib import Path
import re

import numpy as np
from PIL import Image

FORMATS = {14: ("<f2", 3), 15: ("<f2", 4), 10: ("<f4", 3), 11: ("<f4", 4)}


def transform_values(value):
    return value if isinstance(value, list) else [float(v) for v in re.findall(r"[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?", value)]


def affine(value):
    v = transform_values(value)
    return np.array([[v[0], v[2], v[4]], [v[1], v[3], v[5]], [0, 0, 1]])


def verify_owners(owners, canvas=None, combined=None):
    assert owners["valid"] and owners["physics_bodies"]
    assert all(body["space_valid"] for body in owners["physics_bodies"])
    selected = [light for light in owners["scene_lights"] if light["budget_visible"] and light["enabled"]]
    assert len(selected) == owners["active_lights"]
    assert sum(light["shadow"] for light in selected) == owners["active_shadow_lights"]
    actual_visible = [light for light in selected if light["visible"]]
    assert len(actual_visible) <= len(selected)
    projected = affine(combined) if combined is not None else affine(owners["viewport_final_transform_values"]) @ affine(canvas)
    for wall in owners["wall_shadows"]:
        assert wall["camera_synchronized"]
        if wall["enabled"] and not wall["suspended"]:
            expected = np.diag([.5, .5, 1]) @ projected
            assert np.max(np.abs(affine(wall["caster_transform_values"]) - expected)) < .0001


def raster(world, record):
    x, y, w, h = world
    values = transform_values(record["canvas_transform_values"] if "canvas_transform_values" in record else record["canvas_transform"])
    xx, xy, yx, yy, ox, oy = values
    points = np.array([[x, y], [x + w, y], [x, y + h], [x + w, y + h]])
    screen = (points @ [[xx, xy], [yx, yy]] + [ox, oy]) * record["density"]
    start = np.maximum(np.floor(screen.min(axis=0)), [0, 0]).astype(int)
    end = np.minimum(np.ceil(screen.max(axis=0)), [record["width"], record["height"]]).astype(int)
    return [*start.tolist(), *(np.maximum(0, end - start)).tolist()]


def section(pixels, rect):
    x, y, w, h = rect
    return pixels[y:y + h, x:x + w]


def contrast(rgb, body, outer):
    luma = rgb @ [0.2126, 0.7152, 0.0722]
    values = section(luma, body).reshape(-1)
    x, y, w, h = body
    ox, oy, ow, oh = outer
    yy, xx = np.mgrid[oy:oy + oh, ox:ox + ow]
    mask = ~((xx >= x) & (xx < x + w) & (yy >= y) & (yy < y + h))
    ring = section(luma, outer)[mask]
    assert values.size and ring.size, (body, outer)
    outside = float(ring.mean())
    inner = float(np.quantile(values, .9, method="lower"))
    dark = float(np.quantile(values, .25 if outside >= .12 else .5, method="lower"))
    return dict(inner=inner, body=dark, outer=outside, bright=(inner - outside) / (outside + .02), dark=(outside - dark) / (outside + .02))


def load_pixels(folder, record):
    raw = (folder / record["files"]["raw"]).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == record["raw_sha256"]
    dtype, channels = FORMATS[record["format"]]
    rgb = np.frombuffer(raw, dtype=dtype).reshape(int(record["height"]), int(record["width"]), channels)[..., :3].astype(np.float64)
    assert np.isfinite(rgb).all()
    image = np.asarray(Image.open(folder / record["files"]["png"]).convert("RGB"), dtype=np.float64) / 255
    expected = np.where(rgb <= .0031308, rgb * 12.92, 1.055 * np.maximum(rgb, 0) ** (1 / 2.4) - .055)
    assert np.max(np.abs(image - np.clip(expected, 0, 1))) <= 1 / 255 + .00001
    return rgb


def verify_held(folder):
    totals = dict(points=0, images=0, actor_observations=0)
    observations = []
    for path in sorted(folder.glob("*/bg49-held.json")):
        data = json.loads(path.read_bytes())
        assert data["hdr"] and data["renderer"] == "forward_plus"
        for result in data["results"]:
            assert result["sampling_valid"]
            group = result["bg55"]
            assert group["controls_valid"]
            records = group["records"]
            assert [r["label"] for r in records] == ["A0", "A1", "product", "restore-product", "authored-final"]
            first = records[0]
            final = records[-1]
            spot = result["bg49"]["spot"]
            for record in records:
                rgb = load_pixels(path.parent, record)
                totals["images"] += 1
                assert record["held"] == first["held"]
                verify_owners(record["held"]["lighting_owners"], canvas=record.get("canvas_transform_values", record["canvas_transform"]))
                standing = record["standing"]
                assert standing["valid"] and standing["player_on_floor"] and abs(standing["player_gap"]) <= .1
                assert standing["enemy_on_floor"] is None or (standing["enemy_on_floor"] and abs(standing["enemy_gap"]) <= .1)
                support = record["held"]["player_support"]
                assert support["valid"] and support["found"] and support["on_floor"]
                assert abs(support["floor"][1] - support["feet"][1]) <= .1
                assert abs(support["gap"] - (support["floor"][1] - support["feet"][1])) < .00001
                assert support["normal"][1] < -.99
                assert record["visible_world_prompts"] == []
                assert record["world_environment"]["active"] and record["world_environment"]["glow_enabled"]
                assert record["player_visible"]
                assert record["weapon_light"]["origin_error"] <= .00001
                assert record["weapon_light"]["fade_level"] >= .999
                if record["label"] in ["A1", "restore-product"] or spot != "碼頭入口":
                    assert record["raw_sha256"] == first["raw_sha256"]
                if record["label"] == "product":
                    assert record["raw_sha256"] == final["raw_sha256"]
                actors = [(record["player"], True)] + [(enemy, False) for enemy in record["enemies"]]
                for actor, player in actors:
                    fx, fy = actor["feet"]
                    body = raster([fx - 9, fy - (58 if player else 44), 18, 54 if player else 40], record)
                    outer = raster([fx - 29, fy - (78 if player else 64), 58, 94 if player else 80], record)
                    assert body == actor["screen_rect"] and outer == actor["outer_screen_rect"]
                    values = contrast(rgb, body, outer)
                    for name, number in values.items():
                        assert abs(number - actor["parts"][name]) < .000002, (spot, name, number, actor["parts"][name])
                    assert abs(max(values["bright"], values["dark"]) - actor["contrast"]) < .000002
                    totals["actor_observations"] += 1
                player = record["player"]
                fx, fy = player["feet"]
                edge = raster([fx - 24, fy, 48, 3], record)
                below = raster([fx - 24, fy + 8, 48, 6], record)
                assert edge == player["edge_screen_rect"] and below == player["below_screen_rect"]
                luma = rgb @ [0.2126, 0.7152, 0.0722]
                edge_contrast = (section(luma, edge).mean() - section(luma, below).mean()) / (section(luma, below).mean() + .02)
                assert abs(edge_contrast - player["edge_contrast"]) < .000002
                for exposure in record["exposure"]:
                    world = exposure["world_bounds"]
                    grown = [world[0] - 1, world[1] - 1, world[2] + 2, world[3] + 2]
                    assert raster(grown, record) == exposure["screen_rect"]
                    area = section(rgb, exposure["screen_rect"])
                    white = int(np.all(area > .92, axis=-1).sum())
                    assert area.size > 0 and white == exposure["white_pixels_including_background"]
                    assert abs(float(area.max()) - exposure["peak"]) < .000002
                    assert exposure["enemy_white_ratio"] == (0.0 if white == 0 else None)
                    if "head_mask" in exposure:
                        mask = exposure["head_mask"]
                        assert mask["source_held"] and mask["body_shader_sway_disabled"]
                        assert not mask["blank_negative_control"]
                        assert mask["format"] in [15, 11] and mask["alpha_threshold"] == .999
                        assert mask["width"] == record["width"] and mask["height"] == record["height"]
                        expected_matrix = affine(record["held"]["lighting_owners"]["viewport_final_transform_values"]) @ affine(record["canvas_transform_values"])
                        assert np.max(np.abs(affine(mask["viewport_transform"]) - expected_matrix)) < .00001
                        mask_raw = (path.parent / mask["files"]["raw"]).read_bytes()
                        assert hashlib.sha256(mask_raw).hexdigest() == mask["raw_sha256"]
                        dtype, channels = FORMATS[mask["format"]]
                        pixels = np.frombuffer(mask_raw, dtype=dtype).reshape(int(mask["height"]), int(mask["width"]), channels).astype(np.float64)
                        assert channels == 4 and np.isfinite(pixels).all()
                        opaque = pixels[..., 3] >= .999
                        count = int(section(opaque, exposure["screen_rect"]).sum())
                        assert count == mask["opaque_head_pixels"] > 0
                        assert int(opaque.sum()) - count == mask["outside_rectangle"] == 0
                        shown = np.asarray(Image.open(path.parent / mask["files"]["png"]).convert("RGBA"), dtype=np.float64) / 255
                        assert np.max(np.abs(shown[..., 3] - pixels[..., 3])) <= 1 / 255 + .00001
                        upper = white / count
                        assert exposure["bound_valid"] and exposure["enemy_only_ratio"] is None
                        assert abs(upper - exposure["enemy_white_ratio_upper_bound"]) < 1e-14
            assert final["player"]["contrast"] >= .6 and final["player"]["edge_contrast"] >= 1.0
            assert all(enemy["contrast"] >= .45 for enemy in final["enemies"])
            if spot == "碼頭入口":
                assert final["exposure"] and all(e["bound_valid"] and e["enemy_white_ratio_upper_bound"] <= .02 for e in final["exposure"])
            totals["points"] += 1
            observations.append(dict(spot=spot, player=final["player"]["contrast"], edge=final["player"]["edge_contrast"],
                                     enemies=[e["contrast"] for e in final["enemies"]], controls_valid=True))
            observations[-1]["exposure_upper_bounds"] = [e.get("enemy_white_ratio_upper_bound", e["enemy_white_ratio"]) for e in final["exposure"]]
    assert totals["points"] > 0
    return dict(**totals, observations=observations)


def verify_pool(folder):
    observations = []
    for path in sorted(folder.glob("*-index.json")):
        index = json.loads(path.read_bytes())
        assert index["invalid_focus_samples"] == 0
        for level in index["levels"].values():
            assert level["hdr"]
            for lamp in level["observations"]:
                assert lamp["controls_valid"] and lamp["no_drop"]
                records = lamp["records"]
                assert len(records) == 5
                for record in records:
                    assert record["bloom_active"] and record["brightness"] == .5
                    assert record["state"] == records[0]["state"]
                    verify_owners(record["state"]["drawing_owners"], combined=record.get("world_to_screen_values", record["world_to_screen"]))
                    assert abs(record["target_x"] - record["lamp_x"]) < .001
                    synthetic = dict(record, files={"raw": record["raw"], "png": record["png"]})
                    load_pixels(folder, synthetic)
                    shown = np.asarray(Image.open(folder / record["png"]).convert("RGB"), dtype=np.float64) / 255
                    linear = np.where(shown <= .04045, shown / 12.92, ((shown + .055) / 1.055) ** 2.4)
                    luma = linear @ [.2126, .7152, .0722]
                    xx, xy, yx, yy, ox, oy = transform_values(record.get("world_to_screen_values", record["world_to_screen"]))
                    assert abs(xy) < .00001 and abs(yx) < .00001 and xx > 0 and abs(xx - yy) < .00001
                    scale = xx
                    formula = record["formula"]
                    assert formula == dict(height=14.0, half_width=26.0, far_from=1.1, far_to=1.6, far_min=.004)
                    eligible = [band for band in record["bands"] if band["pool_wall_eligible"]]
                    assert eligible
                    band = eligible[0]
                    lx, ly = record["lamp_position"]
                    center_x, center_y = lx * xx + ox, (ly + band["drop"]) * yy + oy
                    rows = max(1, int(14 * scale))
                    top = int(center_y) - rows // 2

                    def sample(start, end):
                        left, right = max(0, int(start)), min(record["width"], int(end))
                        upper, lower = max(0, top), min(record["height"], top + rows)
                        assert left < right and upper < lower
                        return luma[upper:lower, left:right].mean(axis=0)

                    pool = sample(center_x - 26 * scale, center_x + 26 * scale)
                    far = []
                    for side, covered in zip([-1, 1], band["far_wall_eligible"]):
                        if covered:
                            start = center_x + side * record["lamp_radius"] * 1.1 * scale
                            end = center_x + side * record["lamp_radius"] * 1.6 * scale
                            far.extend(sample(min(start, end), max(start, end)))
                    assert far
                    pool_value = float(np.quantile(pool, .5, method="lower"))
                    far_value = float(np.quantile(far, .5, method="lower"))
                    ratio = pool_value / max(far_value, .004)
                    for name, value in [("pool", pool_value), ("far", far_value), ("ratio", ratio)]:
                        assert abs(value - record[name]) < .00002, (name, value, record[name])
                assert records[0]["raw_sha256"] == records[1]["raw_sha256"] == records[3]["raw_sha256"]
                assert records[2]["raw_sha256"] == records[4]["raw_sha256"]
                assert records[2]["ratio"] >= records[0]["ratio"] > 0
                observations.append(dict(lamp=lamp["lamp_tile"], before=records[0]["ratio"], after=records[2]["ratio"], controls_valid=True))
    assert observations
    return dict(lamps=len(observations), observations=observations)


def load_roi(folder, record):
    raw = (folder / record["raw"]).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == record["sha256"]
    dtype, channels = FORMATS[record["format"]]
    image = np.frombuffer(raw, dtype=dtype).reshape(int(record["height"]), int(record["width"]), channels)[..., :3].astype(np.float64)
    assert np.isfinite(image).all()
    assert record["source_rect"][2:] == [record["width"], record["height"]]
    return image


def local_rect(rect, origin):
    return [rect[0] - origin[0], rect[1] - origin[1], rect[2], rect[3]]


def verify_world(folder):
    data = json.loads((folder / "readability-report.json").read_bytes())
    assert data["samples_per_spot"] == 16 and data["sample_interval"] == .2
    assert data["thresholds"] == dict(player=.6, edge=1.0, enemy=.45)
    assert data["brightness"] == .5
    assert data["pure_world"]["bloom_active"] and data["pure_world"]["world_prompt_process_disabled"]
    spots = data["results"]
    native = json.loads((folder / data["native_float_rois"]["file"]).read_bytes())
    assert not data["native_float_rois"]["failed"] and data["native_float_rois"]["same_original_probe_input"]
    assert native["samples_per_spot"] == 16 and native["sample_interval"] == .2
    samples = native["records"]
    assert len(samples) == len(spots) * 16 == data["native_float_rois"]["samples"]
    np_observations = []
    for spot in spots:
        assert spot["sampling_valid"] and spot["passed"]
        assert spot["player_contrast"] >= .6 and spot["edge_contrast"] >= 1
        assert spot["enemy_contrast"] is None or spot["enemy_contrast"] >= .45
        with Image.open(folder / spot["screenshot"]) as image:
            image_size = image.size
        assert list(image_size) == spot["capture_size"]
        assert image_size[0] / data["viewport"][0] == image_size[1] / data["viewport"][1] > 0
        records = [record for record in samples if record["level"] == spot["level"] and record["column"] == spot["column"] and record["spot"] == spot["spot"]]
        assert [record["sample"] for record in records] == list(range(16))
        sums = dict(player=0.0, edge=0.0, enemy=0.0)
        for sample in records:
            assert sample["visible_world_prompts"] == []
            assert list(image_size) == sample["source_size"]
            assert np.max(np.abs(affine(sample["viewport_final_transform_values"]) - np.diag([sample["density"], sample["density"], 1]))) < .00001
            geometry = dict(width=sample["source_size"][0], height=sample["source_size"][1],
                            density=sample["density"], canvas_transform_values=sample["canvas_transform_values"])
            for key in ["player", "enemy"]:
                actor = sample[key]
                if actor is None:
                    assert key == "enemy" and spot["enemy_contrast"] is None
                    continue
                assert actor["on_floor"]
                assert actor["space_valid"] and actor["support"]["found"]
                assert abs(actor["support"]["gap"]) <= .1 and actor["support"]["normal"][1] < -.99
                px, py = actor["feet"]
                player = key == "player"
                if player:
                    assert actor["facing"] == 1 and np.max(np.abs(np.array(actor["aim"]) - [1, 0])) < .00001
                expected_body = raster([px - 9, py - (58 if player else 44), 18, 54 if player else 40], geometry)
                expected_outer = raster([px - 29, py - (78 if player else 64), 58, 94 if player else 80], geometry)
                assert actor["body"] == expected_body and actor["outer"] == expected_outer
                roi = actor["roi"]
                assert roi["source_rect"] == expected_outer
                pixels = load_roi(folder, roi)
                origin = roi["source_rect"]
                body = local_rect(expected_body, origin)
                outer = [0, 0, int(roi["width"]), int(roi["height"])]
                parts = contrast(pixels, body, outer)
                sums[key] += max(parts["bright"], parts["dark"]) / 16
                if player:
                    edge = raster([px - 24, py, 48, 3], geometry)
                    below = raster([px - 24, py + 8, 48, 6], geometry)
                    assert edge == actor["edge"] and below == actor["below"]
                    luma = pixels @ [.2126, .7152, .0722]
                    ground = section(luma, local_rect(below, origin))
                    edge_pixels = section(luma, local_rect(edge, origin))
                    assert ground.size and edge_pixels.size
                    sums["edge"] += float((edge_pixels.mean() - ground.mean()) / (ground.mean() + .02)) / 16
            for key, value in sums.items():
                assert abs(value - sample["cumulative_original"][key]) < .000002, (spot["spot"], sample["sample"], key)
        assert abs(sums["player"] - spot["player_contrast"]) < .000002
        assert abs(sums["edge"] - spot["edge_contrast"]) < .000002
        assert spot["enemy_contrast"] is None or abs(sums["enemy"] - spot["enemy_contrast"]) < .000002
        np_observations.append(dict(spot=spot["spot"], **sums))
    assert spots
    assert len({(spot["level"], spot["column"]) for spot in spots}) == len(spots)
    return dict(points=len(spots), native_float_samples=len(samples),
                scope="independent reconstruction from exact player/enemy outer ROI floats, including original body/ring/ground strips; not full-frame HDR", observations=np_observations)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path)
    parser.add_argument("--kind", choices=["held", "pool", "world"], default="held")
    parser.add_argument("--expect-points", type=int)
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    result = {"held": verify_held, "pool": verify_pool, "world": verify_world}[args.kind](args.folder)
    if args.expect_points is not None:
        assert result["points"] == args.expect_points
        source = (args.folder / "source/tools/ch1_readability_check.gd").read_text(encoding="utf-8")
        points = ast.literal_eval(re.search(r"const PROBES := (\{.*?\n\})", source, re.S).group(1))
        expected = {str(spot[0]) for level in points.values() for spot in level}
        assert {r["spot"] for r in result["observations"]} == expected
    if args.out:
        args.out.write_bytes((json.dumps(result, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
