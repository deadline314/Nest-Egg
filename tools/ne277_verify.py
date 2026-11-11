"""Independent fail-closed verification of NE-277 observations, never a visual verdict."""
from __future__ import annotations
import math
from pathlib import Path
import struct

LIMITS = {"bone_stretch": 0.3, "elbow_hyper": 0.6, "knee_hyper": 0.1, "trunk_lean": 1.15, "head_turn": 1.0, "mesh_fold": 0.4, "limb_pinch": 0.75, "angle_pop": 0.9}
METRICS = set(LIMITS)


def rope_inside_crop(frame: dict) -> bool:
    points, rect = frame.get("rope_screen_points"), frame.get("crop")
    if not isinstance(points, list) or len(points) != 20 or not isinstance(rect, list) or len(rect) != 4 or not all(type(v) in (int, float) and math.isfinite(v) for v in rect):
        return False
    x, y, width, height = rect
    return all(isinstance(p, list) and len(p) == 2 and all(type(v) in (int, float) and math.isfinite(v) for v in p) and x + 2 <= p[0] <= x + width - 2 and y + 2 <= p[1] <= y + height - 2 for p in points)


def verify_gait(data: dict) -> list[str]:
    errors = []
    rows = data.get("rows", [])
    expected = {f"{kind}/{side}/negative-{str(broken).lower()}" for kind in ["idle", "lunge"] for side in [-1, 1] for broken in [False, True]}
    if data.get("failures") != [] or not isinstance(rows, list) or len(rows) != 8 or {r.get("name") for r in rows} != expected:
        return ["exact eight passing gait/control observations required"]
    for row in rows:
        name = row["name"]
        try:
            previous = row["initial_angles"]
            frames = row["frames"]
            if len(previous) != 6 or len(frames) != 90:
                raise ValueError("missing steps or initial legs")
            pop, penetration = 0.0, 0.0
            for index, frame in enumerate(frames):
                angles, floor = frame["angles"], frame["floor_errors"]
                if frame["frame"] != index or len(angles) != 6 or len(floor) != 2 or not all(type(v) in (int, float) and math.isfinite(v) for v in previous + angles + floor):
                    raise ValueError("incomplete/nonfinite actual observations")
                pop = max(pop, *(abs((b - a + math.pi) % (2 * math.pi) - math.pi) for a, b in zip(previous, angles)))
                penetration = max(penetration, *floor)
                previous = angles
            accepted = pop <= 0.5 and penetration <= 0.5
            negative = name.endswith("negative-true")
            numbers = [row["leg_pop"], row["penetration"]]
            if not all(type(v) in (int, float) and math.isfinite(v) for v in numbers) or abs(pop - numbers[0]) > 1e-5 or abs(penetration - numbers[1]) > 1e-5 or type(row["accepted"]) is not bool or row["accepted"] != accepted or accepted == negative:
                errors.append(name + ": independently calculated contact/jump verdict")
        except (KeyError, TypeError, ValueError):
            errors.append(name + ": malformed gait observations")
    return errors


def verify_motion(data: dict, expected: set[str], directory: Path, native=False) -> list[str]:
    errors = []
    def require(ok, message):
        if not ok:
            errors.append(message)
    require(type(data.get("checks")) is int and data["checks"] > 0, "positive check count")
    require(data.get("failures") == [], "probe failures must be empty")
    rows = data.get("rows", [])
    require(isinstance(rows, list) and len(rows) > 0, "nonempty motion rows")
    if not isinstance(rows, list):
        return errors
    names = [r.get("name") for r in rows if isinstance(r, dict)]
    require(len(names) == len(rows) == len(set(names)) and set(names) == expected, "exact unique move/side coverage")
    for row in rows:
        if not isinstance(row, dict):
            continue
        name = str(row.get("name"))
        frames = row.get("frames", [])
        require(isinstance(frames, list) and len(frames) >= 3 and row.get("ended") is True, name + ": completed nonempty frames")
        if not isinstance(frames, list) or not frames:
            continue
        ticks = [f.get("tick") for f in frames]
        require(all(type(t) is int for t in ticks) and all(b == a + 1 for a, b in zip(ticks, ticks[1:])), name + ": contiguous physics ticks")
        require({0, 1, 2, 3}.issubset({f.get("phase") for f in frames}), name + ": all phases and return")
        require(all(isinstance(f.get("angles"), dict) and f["angles"] and all(isinstance(a, (int, float)) and math.isfinite(a) for a in f["angles"].values()) for f in frames), name + ": finite actual bone observations")
        for frame in frames:
            floor = frame.get("foot_ground_error")
            valid = type(frame.get("on_floor")) is bool and isinstance(floor, list) and len(floor) == 2 and all(type(v) in (int, float) and math.isfinite(v) for v in floor)
            require(valid and (not frame.get("on_floor") or max(floor) <= 0.5), name + ": measured grounded foot anchors")
        results = row.get("results", {})
        require(METRICS.issubset(results), name + ": every metric present")
        for key in METRICS:
            value = results.get(key, {})
            number, limit = value.get("value"), value.get("limit")
            require(type(number) in (int, float) and type(limit) in (int, float) and math.isfinite(number) and limit == LIMITS[key] and number <= limit, name + ": metric " + key)
        if all(isinstance(f.get("angles"), dict) and f["angles"] for f in frames):
            try:
                pop = max(abs((current["angles"][bone] - previous["angles"][bone] + math.pi) % (2 * math.pi) - math.pi) / 2.2 for previous, current in zip(frames, frames[1:]) for bone in current["angles"])
                require(math.isfinite(pop) and pop <= LIMITS["angle_pop"] and abs(pop - results.get("angle_pop", {}).get("value", math.inf)) < 1e-5, name + ": independently recalculated angle changes")
            except (TypeError, KeyError, ValueError):
                require(False, name + ": incomplete actual angle trace")
        require(row.get("path_samples", 0) > 0 and row.get("palm_max", math.inf) <= 1 and row.get("second_max", math.inf) <= 1.5 and row.get("second_missed") == 0, name + ": measured grips")
        require(type(row.get("held")) is bool and row["held"] == name.endswith("-held"), name + ": held scenario identity")
        if name.endswith("-held"):
            require(row.get("released") is True and any(f.get("held_input") is True and f.get("hold_mode") for f in frames) and frames[-1].get("held_input") is False, name + ": actual held input and release")
        if native:
            for frame in frames:
                if name.startswith("whip/"):
                    require(rope_inside_crop(frame), name + ": all actual world rope nodes lie inside the native crop")
                relative = frame.get("image", "")
                path = (directory / relative).resolve()
                require(bool(relative) and path.is_relative_to(directory.resolve()), name + ": image path stays in evidence")
                for image, rect in [(path, frame.get("crop")), (path.with_name(path.stem + "-hands.png"), frame.get("hands_crop"))]:
                    try:
                        header = image.read_bytes()[:24]
                        size = struct.unpack(">II", header[16:24])
                        require(header[:8] == b"\x89PNG\r\n\x1a\n" and isinstance(rect, list) and len(rect) == 4 and size == tuple(rect[2:]) and min(size) > 0, name + ": unscaled native image geometry")
                    except (OSError, ValueError, struct.error):
                        require(False, name + ": missing or invalid native image")
    if native:
        require(data.get("renderer") == "forward_plus" and data.get("display") != "headless" and bool(data.get("adapter")), "real native Forward+ renderer")
    return errors


def verify_feedback(data: dict, expected: set[str], events: dict) -> list[str]:
    errors = []
    if type(data.get("checks")) is not int or data["checks"] <= 0 or data.get("failures") != []:
        errors.append("nonempty passing feedback checks required")
    rows = data.get("rows", [])
    if not isinstance(rows, list):
        return errors + ["feedback rows must be an array"]
    names = [r.get("name") for r in rows if isinstance(r, dict)]
    if not expected or len(names) != len(rows) or len(names) != len(set(names)) or set(names) != expected:
        errors.append("exact unique contact/mode/side coverage")
    for row in rows:
        if not isinstance(row, dict):
            continue
        name = str(row.get("name"))
        settings = row.get("settings", {})
        reduced = row.get("reduced")
        shakes = row.get("world_shakes")
        if type(reduced) is not bool or settings.get("reduce_flashes") != reduced or settings.get("shake") != (0.0 if reduced else 1.0) or settings.get("zoom_enabled") != (not reduced):
            errors.append(name + ": actual accessibility settings readback required")
        if not isinstance(shakes, list) or (bool(shakes) if reduced else not shakes) or any(type(e.get("px")) not in (int, float) or not math.isfinite(e["px"]) or e["px"] <= 0 for e in (shakes or [])):
            errors.append(name + ": actual world shake signals must obey motion setting")
        hits = row.get("hits", [])
        frames = row.get("frames", [])
        if not hits or not frames or not row.get("first_observed_pair_freeze"):
            errors.append(name + ": actual contact and first-frame pair freeze required")
            continue
        hit = hits[0]
        if not hit.get("attacker") or not hit.get("freeze_attacker") or not isinstance(hit.get("amount"), (int, float)) or not math.isfinite(hit["amount"]) or hit["amount"] <= 0:
            errors.append(name + ": actual attacker/damage required")
        first = next((f for f in frames if f.get("tick", -1) >= hit.get("tick", math.inf)), {})
        if not first.get("player_frozen") or not first.get("enemy_frozen"):
            errors.append(name + ": observed first contact must freeze both actors")
        layers = row.get("expected_layers", [])
        if len(layers) != 2 or len(set(layers)) != 2:
            errors.append(name + ": distinct declared low/high layers required")
        for layer in layers:
            groups = [part.get("sounds", []) for part in events[layer].get("layers", [])] if layer in events else [[layer]]
            if not groups or any(not group or not any(leaf in row.get("played", []) for leaf in group) for group in groups):
                errors.append(name + ": missing resolved sound layer " + layer)
    return errors
