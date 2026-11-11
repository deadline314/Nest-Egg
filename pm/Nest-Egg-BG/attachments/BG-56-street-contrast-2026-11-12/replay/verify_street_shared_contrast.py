"""Independent pixel reconstruction for the street's explicit factor controls."""
from pathlib import Path
import argparse
import hashlib
import json

import numpy as np

from verify_bg55_readability import verify as verify_held_controls
from verify_bg49_held import affine, contrast, load_pixels, raster, section


def clip_projected(world, matrix, record, padding=0):
    x, y, w, h = world
    corners = np.array([[x, y, 1], [x + w, y, 1], [x, y + h, 1], [x + w, y + h, 1]])
    projected = (corners @ matrix.T)[:, :2]
    start = np.maximum(np.floor(projected.min(axis=0)).astype(int) - padding, [0, 0])
    end = np.minimum(np.ceil(projected.max(axis=0)).astype(int) + padding, [record["width"], record["height"]])
    if np.any(end <= start):
        return [0, 0, 0, 0]
    return [*start.tolist(), *(end - start).tolist()]


def intersects(a, b):
    return a[2] > 0 and a[3] > 0 and b[2] > 0 and b[3] > 0 and max(a[0], b[0]) < min(a[0] + a[2], b[0] + b[2]) and max(a[1], b[1]) < min(a[1] + a[3], b[1] + b[3])


def verify(folder, expect_cells=None, require_enemies=False):
    original = verify_held_controls(folder, require_owners=True, require_contact=True)
    assert original["control_failures"] == 0
    results = []
    cache = {}
    inventories = {}
    covered = set()
    for path in sorted(folder.glob("*/*-index.json")):
        document = json.loads(path.read_bytes())
        assert document["probe"]["fixed_gamepad_aim"]
        for shot in document["shots"]:
            assert shot["facing"] == 1
            assert abs(shot["aim_dir"][0] - 1) < .00001 and abs(shot["aim_dir"][1]) < .00001
            group = shot["bg55"]
            trial = shot["street_shared"]
            records = group["records"]
            assert [r["label"] for r in records] == ["A0", "A1", "product", "restore-product", "authored-final"]
            assert trial["diagnostic_only"] == group["diagnostic_only"]
            observations = []
            for record in records:
                environment = record["world_environment"]
                assert environment["active"] and environment["glow_enabled"]
                altered = record["label"] in ["product", "authored-final"]
                wanted_fill = trial["candidate_fill_scale"] if altered else trial["baseline_fill_scale"]
                wanted_color = trial["candidate_edge_color"] if altered else trial["baseline_edge_color"]
                assert abs(record["enemy_fill_scale"] - wanted_fill) < .000001
                assert record["street_edge_color"] == wanted_color
                assert record.get("fixture_overlay_clear") is True, "capture predates the caption/ROI guard or has contaminated pixels"
                final_matrix = affine(record["held"]["lighting_owners"]["viewport_final_transform_values"])
                world_matrix = final_matrix @ affine(record["canvas_transform_values"])
                labels = record["fixture_labels"]
                assert len(labels) == 1
                caption = labels[0]
                assert caption["visible"] and caption["text"] == "BG56 / DIAG"
                padding = int(np.ceil(6 * max(np.linalg.norm(final_matrix[:2, 0]), np.linalg.norm(final_matrix[:2, 1]))))
                assert caption["padding_pixels"] == padding
                rectangle = clip_projected(caption["logical_rect"], final_matrix, record, padding)
                # A conservative native padding box may extend beyond the
                # captured PNG. Only its intersection with actual raw pixels
                # is relevant; never use a later texture descriptor as size.
                reported = clip_projected(caption["pixel_rect_with_padding"], np.eye(3), record)
                assert rectangle == reported
                inventory = record["enemy_inventory"]
                observed = {int(enemy["instance"]): enemy for enemy in record["enemies"]}
                assert len(observed) == len(record["enemies"])
                assert len({int(actor["instance"]) for actor in inventory}) == len(inventory)
                assert observed.keys() <= {int(actor["instance"]) for actor in inventory}
                for actor in inventory:
                    instance = int(actor["instance"])
                    actor_key = (path.parent.name, instance)
                    stable = {key: actor[key] for key in ["id", "skin", "feet", "hp", "alive", "tree_visible"]}
                    assert actor_key not in inventories or inventories[actor_key] == stable
                    inventories[actor_key] = stable
                    assert actor["observed"] == (instance in observed)
                    body_clip = raster(actor["body_world"], record)
                    if not body_clip[2] or not body_clip[3]:
                        body_clip = [0, 0, 0, 0]
                    assert body_clip == actor["body_screen_rect"]
                    x, y, w, h = actor["body_world"]
                    corners = np.array([[x, y, 1], [x + w, y, 1], [x, y + h, 1], [x + w, y + h, 1]])
                    projected = (corners @ affine(record["canvas_transform_values"]).T)[:, :2] * record["density"]
                    full_body = bool(np.all(projected >= -.00001) and np.all(projected <= [record["width"] + .00001, record["height"] + .00001]))
                    assert actor["full_body_in_view"] == full_body
                    drawables = actor.get("visible_drawables")
                    if drawables:
                        corners = []
                        for drawable in drawables:
                            if 'vertices' in drawable:
                                vertices = np.c_[np.asarray(drawable['vertices']), np.ones(len(drawable['vertices']))]
                            else:
                                x, y, w, h = drawable["local_rect"]
                                vertices = np.array([[x, y, 1], [x + w, y, 1],
                                                     [x, y + h, 1], [x + w, y + h, 1]])
                            corners.extend((vertices @ affine(drawable["global_transform"]).T)[:, :2])
                        corners = np.asarray(corners)
                        low, high = corners.min(axis=0), corners.max(axis=0)
                        assert np.max(np.abs(np.r_[low, high - low] - actor["visual_world"])) < .001
                    if actor["tree_visible"]:
                        x, y, w, h = actor["body_world"]
                        outer = clip_projected([x - 20, y - 20, w + 40, h + 40], world_matrix, record)
                        visual = clip_projected(actor["visual_world"], world_matrix, record)
                        assert not intersects(rectangle, outer) and not intersects(rectangle, visual)
                    if instance in observed:
                        enemy = observed[instance]
                        assert enemy["id"] == actor["id"] and enemy["feet"] == actor["feet"]
                        # A complete exposure/appearance observation also
                        # keeps actual sprite/weapon/wing bounds on screen.
                        if altered and full_body and actor["full_visual_in_view"]:
                            covered.add(actor_key)
                key = (path.parent, record["raw_sha256"])
                if key not in cache:
                    cache[key] = load_pixels(path.parent, record)
                rgb = cache[key]
                player = record["player"]
                player_values = None
                if record["player_visible"]:
                    assert player is not None
                    x, y = player["feet"]
                    assert [x, y] == shot["player_world"]
                    body = raster([x - 9, y - 58, 18, 54], record)
                    outer = raster([x - 29, y - 78, 58, 94], record)
                    edge = raster([x - 24, y, 48, 3], record)
                    below = raster([x - 24, y + 8, 48, 6], record)
                    assert body == player["screen_rect"] and outer == player["outer_screen_rect"]
                    assert edge == player["edge_screen_rect"] and below == player["below_screen_rect"]
                    assert not intersects(rectangle, outer)
                    parts = contrast(rgb, body, outer)
                    for name, value in parts.items():
                        assert abs(value - player["parts"][name]) < .000002
                    value = max(parts["bright"], parts["dark"])
                    assert abs(value - player["contrast"]) < .000002
                    luma = rgb @ [.2126, .7152, .0722]
                    edge_mean = float(section(luma, edge).mean())
                    below_mean = float(section(luma, below).mean())
                    edge_value = (edge_mean - below_mean) / (below_mean + .02)
                    assert abs(edge_mean - player["edge_mean"]) < .000002
                    assert abs(below_mean - player["below_mean"]) < .000002
                    assert abs(edge_value - player["edge_contrast"]) < .000002
                    player_values = dict(contrast=value, edge=edge_value, passed=value >= .6 and edge_value >= 1)
                else:
                    assert player is None
                observations.append(dict(label=record["label"], player=player_values,
                                         enemies=[dict(id=e["id"], feet=e["feet"], contrast=e["contrast"], passed=e["passed"])
                                                  for e in record["enemies"]]))
            if trial["factor"] == "identity":
                assert all(r["raw_sha256"] == records[0]["raw_sha256"] for r in records)
            final = observations[-1]
            passed = (final["player"] is None or final["player"]["passed"]) and all(e["passed"] for e in final["enemies"])
            assert shot["passed"] == passed
            results.append(dict(column=shot["column"], row=shot["row"], factor=trial["factor"],
                                candidate_thresholds_passed=passed, observations=observations))
    assert results
    if expect_cells is not None:
        assert len(results) == expect_cells
    expected = {key for key, actor in inventories.items() if actor["alive"] and actor["tree_visible"]}
    def ledger_row(key):
        return dict(level=key[0], instance=key[1], **inventories[key])
    missing = sorted(expected - covered)
    if require_enemies:
        assert not missing, [ledger_row(key) for key in missing]
    return dict(cells=len(results), controls_valid=True,
                candidate_thresholds_passed=all(r["candidate_thresholds_passed"] for r in results),
                enemy_coverage=dict(actual_instances=len(inventories), alive_tree_visible=len(expected),
                                    observed_with_full_body=len(expected & covered),
                                    missing=[ledger_row(key) for key in missing],
                                    observed=[ledger_row(key) for key in sorted(expected & covered)],
                                    excluded_not_alive_or_tree_visible=[ledger_row(key) for key in sorted(inventories.keys() - expected)],
                                    scope="instance IDs belong to this run/Level, not persistent IDs across independent processes"),
                verifier_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                scope="independent diagnostic factors; candidate threshold pass is not product or historical acceptance",
                results=results)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("folder", type=Path)
    parser.add_argument("--expect-cells", type=int)
    parser.add_argument("--require-thresholds", action="store_true")
    parser.add_argument("--require-complete-enemies", action="store_true")
    parser.add_argument("--out", type=Path)
    args = parser.parse_args()
    result = verify(args.folder, args.expect_cells, args.require_complete_enemies)
    if args.out:
        args.out.write_bytes((json.dumps(result, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps({k: v for k, v in result.items() if k != "results"}, indent=2))
    raise SystemExit(1 if args.require_thresholds and not result["candidate_thresholds_passed"] else 0)
