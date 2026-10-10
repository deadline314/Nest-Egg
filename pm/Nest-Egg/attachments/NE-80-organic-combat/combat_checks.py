from __future__ import annotations

import copy
import json
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
EXPECTED_CASE = "NE-80 heavy_gunner organic combat preflight"


def validate(report: dict, actual_head: str, native: bool = False) -> list[str]:
    errors: list[str] = []
    if report.get("head") != actual_head:
        errors.append("revision label differs from current HEAD")
    if report.get("case") != EXPECTED_CASE:
        errors.append("report is not the isolated NE-80 case")
    if report.get("capture_images") is not native:
        errors.append("capture mode is inconsistent")
    if not isinstance(report.get("checks"), int) or report["checks"] <= 0:
        errors.append("headless checks are missing or zero")
    if report.get("failures") != []:
        errors.append("Godot reported failed checks")

    events = report.get("events", [])
    def events_named(name: str) -> list[dict]:
        return [event for event in events if event.get("event") == name]

    states = [event.get("data", {}).get("state") for event in events_named("fsm_state")]
    if not all(state in states for state in ("spin_up", "fire")):
        errors.append("natural spin_up/fire FSM events missing")
    if not events_named("natural_vent_reached"):
        errors.append("natural armor-open vent was not reached")
    emitted = [event.get("data", {}).get("shot_number") for event in events_named("enemy_projectile_fired")]
    if emitted != list(range(1, 14)):
        errors.append(f"expected exact 13 sampled natural shots, got {emitted}")
    vent_events = events_named("natural_vent_reached")
    if vent_events and vent_events[-1].get("data", {}).get("shots_fired") != 13:
        errors.append("vent counters do not report 13 fired rounds")

    closed = events_named("NE80_closed_armor_result")
    if not closed or closed[-1].get("data", {}).get("enemy_health_before") != closed[-1].get("data", {}).get("enemy_health_after"):
        errors.append("closed armor did not preserve enemy HP")
    if closed and "blocked" not in closed[-1].get("data", {}).get("markers", []):
        errors.append("closed armor did not report a blocked production projectile")
    hit = events_named("NE80_vent_hit")
    if not hit or hit[-1].get("data", {}).get("health_after", 0) >= hit[-1].get("data", {}).get("health_before", 0):
        errors.append("actual Player projectile did not damage the vent-open enemy")
    damage_events = report.get("player_damage_events", [])
    if not damage_events or any(event.get("source_id") != "heavy_gunner_shot" for event in damage_events):
        errors.append("natural heavy-gunner shots did not resolve through Player health damage")

    hashes = report.get("source_sha256", {})
    expected_inputs = ("fixture_script", "fixture_scene", "level", "level_data", "physics_fixture",
                       "enemy_data", "enemy_behavior", "enemy_base", "player", "weapon_system",
                       "projectile", "projectile_pool", "hurtbox", "health_component",
                       "heavy_projectile", "player_pistol", "player_pistol_projectile", "rig",
                       "character", "weapon_visual_config", "weapon_visual", "weapon_normal", "weapon_glow")
    for key in expected_inputs:
        value = hashes.get(key, "")
        if len(value) != 64 or any(ch not in "0123456789abcdef" for ch in value.lower()):
            errors.append(f"missing or invalid source hash: {key}")
    textures = report.get("character_texture_sha256", {})
    if not textures or any(len(value) != 64 for value in textures.values()):
        errors.append("character diffuse/normal/glow source hash ledger is empty or invalid")
    if report.get("missing_character_textures"):
        errors.append("required character texture/normal is absent")
    if not native and any(event.get("event") == "native_capture" for event in events):
        errors.append("CPU run unexpectedly contains native screenshots")
    return errors


def self_test(report: dict, head: str) -> None:
    mutations = {
        "wrong revision": lambda r: r.update(head="0" * 40),
        "missing final shot": lambda r: r["events"].__setitem__(slice(None), [e for e in r["events"] if not (e.get("event") == "enemy_projectile_fired" and e.get("data", {}).get("shot_number") == 13)]),
        "closed armor leaked damage": lambda r: next(e for e in r["events"] if e.get("event") == "NE80_closed_armor_result")["data"].update(enemy_health_after=0),
        "missing natural Player damage": lambda r: r.update(player_damage_events=[]),
        "corrupt source hash": lambda r: r["source_sha256"].update(enemy_data="bad"),
        "CPU captured a frame": lambda r: r.update(capture_images=True),
    }
    for label, mutate in mutations.items():
        sample = copy.deepcopy(report)
        mutate(sample)
        if not validate(sample, head):
            raise AssertionError(f"negative control escaped verifier: {label}")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: verify_preflight.py <NE80-heavy-preflight.json>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1]).resolve()
    report = json.loads(path.read_text(encoding="utf-8"))
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    source = (Path(__file__).with_name("replay.gd")).read_text(encoding="utf-8")
    if "fsm.transition(" in source:
        print("ERROR: fixture contains a direct FSM transition", file=sys.stderr)
        return 1
    errors = validate(report, head)
    if errors:
        for error in errors:
            print("FAIL:", error, file=sys.stderr)
        return 1
    self_test(report, head)
    print(f"NE80_VERIFY checks={report['checks']} shots=13 player_damage_events={len(report['player_damage_events'])} negative_controls=6 head={head}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
