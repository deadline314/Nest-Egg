"""Serial isolated NE-277 probes with immutable source snapshots and raw ZIP evidence."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import time
import wave
import zipfile
from ne277_verify import verify_motion, verify_feedback, verify_gait
from ne277_contact_verify import verify_contacts

ROOT = Path(__file__).resolve().parents[1]
WEAPONS = {"blade": "thermal_blade", "dagger": "mono_dagger", "glaive": "ion_glaive", "maul": "hydraulic_maul", "whip": "mono_whip"}
SOURCES = ["tools/ne277_delivery_probe.gd", "tools/ne277_delivery_probe.tscn", "tools/ne277_feedback_probe.gd", "tools/ne277_feedback_probe.tscn", "tools/melee_joint_audit.gd", "tools/viewport_capture.gd", "tools/ne277_verify.py", "tools/run_ne277_delivery.py", "tools/test_ne277_verify.py", "tools/audio/ne277_recording_report.py", "game/melee/melee_module.gd", "game/melee/melee_move.gd", "game/player/player.gd", "game/player/player_visual.gd", "game/player/melee_held.gd", "game/player/melee_command_input.gd", "game/rig/character_rig.gd", "game/rig/humanoid_animator.gd", "game/rig/anim_audit.gd", "game/enemies/enemy.gd", "autoload/feel.gd", "autoload/fx.gd", "autoload/sfx.gd", "autoload/settings.gd", "data/feel/events.json", "data/feel/sound_events.json", "data/audio/sound_bank.json", "art/rigs/action_poses.json", "art/motion/rin.json", "data/weapon_art/melee.json", "project.godot"]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def write(path, data):
    path.write_bytes((json.dumps(data, indent=2, ensure_ascii=False) + "\n").encode("utf-8"))


def sources(include_feedback_assets=False):
    paths = set(SOURCES)
    paths.update(["tools/ne277_contact_probe.gd", "tools/ne277_contact_probe.tscn", "tools/ne277_contact_verify.py", "tools/test_ne277_contact_verify.py"])
    paths.update(["tests/helpers/melee_contact_geometry_checks.gd", "tests/helpers/melee_contact_parts_checks.gd"])
    weapon_art = json.loads((ROOT / "data/weapon_art/melee.json").read_bytes())
    for entry in weapon_art["weapons"].values():
        paths.update(entry[key].removeprefix("res://") for key in ["texture", "glow"] if entry.get(key))
    # Record shared runtime behavior and the frozen batch's audio/light definitions too.
    # Master recordings include background music/ambience, not isolated melee stems.
    for folder in ["game", "core", "autoload"]:
        paths.update(p.relative_to(ROOT).as_posix() for p in (ROOT / folder).rglob("*.gd"))
    paths.update(["tools/scenarios/scenario_base.gd", "tests/suite/test_new_enemies.gd", "tests/suite/test_melee.gd",
                  "tests/suite/test_locomotion.gd", "tests/helpers/gait_handoff_audit.gd", "tests/helpers/broken_gait_handoff.gd",
                  "tools/ne277_gait_handoff_probe.gd", "tools/ne277_gait_handoff_probe.tscn",
                  "data/lighting/market_gate.tres", "data/levels/ch2_market_gate.tres",
                  "tools/level/build_ch2.py", "data/audio/ambience.json", "data/audio/music.json",
                  "data/lighting_preview/scenes.json"])
    skin = json.loads((ROOT / "art/characters/rin/character.json").read_text(encoding="utf-8"))
    paths.add(skin["rig"].removeprefix("res://"))
    if include_feedback_assets:
        enemy = (ROOT / "data/enemies/grunt.tres").read_text(encoding="utf-8")
        match = re.search(r'^rig_skin\s*=\s*"([^"]+)"', enemy, re.MULTILINE)
        if not match:
            raise ValueError("formal grunt rig_skin is required for the feedback asset ledger")
        character = match.group(1)
        directory = ROOT / "art/characters" / character
        definition = json.loads((directory / "character.json").read_text(encoding="utf-8"))
        paths.add(definition["rig"].removeprefix("res://"))
        paths.add(f"art/motion/{character}.json")
        paths.update(p.relative_to(ROOT).as_posix() for p in directory.rglob("*") if p.is_file() and p.suffix != ".import")
        paths.add("art/weapons/weapons.json")
        paths.update(p.relative_to(ROOT).as_posix() for p in (ROOT / "art/weapons").glob("smg*") if p.is_file() and p.suffix != ".import")
    paths.update(["core/audio/audio_release.gd", "art/shaders/character_light.gdshader", "data/lighting/warehouse_interior.tres", "data/lighting/neutral.tres", "data/enemies/grunt.tres", "assets_src/audio/LICENSES.json"])
    events = json.loads((ROOT / "data/feel/sound_events.json").read_text(encoding="utf-8"))["events"]
    bank = json.loads((ROOT / "data/audio/sound_bank.json").read_text(encoding="utf-8"))["sounds"]
    if include_feedback_assets:
        paths.update(path.removeprefix("res://") for sound in bank.values() for path in sound.get("files", []))
    pending = ["hurt_humanoid", "mat_armor", "land_dirt", "hit_tail"]
    ambience = json.loads((ROOT / "data/audio/ambience.json").read_text(encoding="utf-8"))
    for profile in [ambience.get("default", [])] + list(ambience.get("profiles", {}).values()):
        pending += [layer["sound"] for layer in profile]
    music = json.loads((ROOT / "data/audio/music.json").read_text(encoding="utf-8"))
    paths.update(track["file"].removeprefix("res://") for track in music["tracks"].values())
    for profile in WEAPONS.values():
        definition = json.loads((ROOT / f"data/melee/{profile}.json").read_text(encoding="utf-8"))
        pending.append(definition["idle_sound"])
        for move in definition["attacks"].values():
            pending += list(move.get("sounds", {}).values())
            pending += [move.get("feedback", {}).get(key, "") for key in ["low", "high"]]
    visited = set()
    while pending:
        name = pending.pop()
        if not name or name in visited:
            continue
        visited.add(name)
        if name in events:
            for layer in events[name].get("layers", []):
                pending += layer.get("sounds", [])
        for path in bank.get(name, {}).get("files", []):
            paths.add(path.removeprefix("res://"))
    for folder, pattern in [("data/melee", "*.json"), ("data/weapons/melee", "*.tres"), ("art/characters/rin", "*")]:
        paths.update(p.relative_to(ROOT).as_posix() for p in (ROOT / folder).rglob(pattern) if p.is_file() and p.suffix != ".import")
    return sorted(paths)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--mode", choices=["motion", "feedback", "gait", "contacts"], default="motion")
    parser.add_argument("--weapon", choices=WEAPONS)
    parser.add_argument("--facing", choices=["-1", "1", "both"], default="both")
    parser.add_argument("--native", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--negative", choices=["missing-input"])
    parser.add_argument("--move")
    parser.add_argument("--contact-control", choices=["early-broad", "late-broad"])
    parser.add_argument("--context-manifest", type=Path, help="Additional immutable runtime context, with source_sha256 entries")
    parser.add_argument("--timeout", type=int, default=360)
    args = parser.parse_args()
    if args.negative and args.mode not in ["motion", "contacts"]:
        parser.error("missing-input negative control applies only to held motion")
    if (args.move or args.contact_control) and args.mode != "contacts":
        parser.error("contact filters/controls apply only to contacts mode")
    if args.mode == "gait" and (args.native or args.weapon or args.facing != "both"):
        parser.error("gait mode is the complete CPU kinematic/control matrix")
    out = args.out.resolve(); out.mkdir(parents=True, exist_ok=False); (out / ".gdignore").touch()
    inputs = sources(args.mode in ["feedback", "contacts"])
    context = {}
    if args.context_manifest:
        context = json.loads(args.context_manifest.read_bytes())["source_sha256"]
        if not context or any(sha(ROOT / p) != expected for p, expected in context.items()):
            parser.error("context manifest does not match actual source bytes")
        inputs = sorted(set(inputs) | set(context))
        shutil.copyfile(args.context_manifest, out / "context-manifest.json")
    before = {p: sha(ROOT / p) for p in inputs}
    for p in inputs:
        if Path(p).suffix in [".gd", ".tscn", ".json", ".py", ".godot", ".tres", ".gdshader"] or p.startswith("art/weapons/melee/"):
            target = out / "source" / p; target.parent.mkdir(parents=True, exist_ok=True); shutil.copyfile(ROOT / p, target)
    scene = {"motion": "ne277_delivery_probe", "feedback": "ne277_feedback_probe", "gait": "ne277_gait_handoff_probe", "contacts": "ne277_contact_probe"}[args.mode]
    cmd = [str(args.godot.resolve())]
    if args.verbose:
        cmd += ["--verbose"]
    if args.native:
        cmd += ["--rendering-method", "forward_plus", "--rendering-driver", "vulkan", "--resolution", "1280x720"]
    else:
        cmd += ["--headless", "--audio-driver", "Dummy"]
    cmd += ["--path", str(ROOT), "res://tools/" + scene + ".tscn", "--", "--out=" + str(out), "--facing=" + args.facing]
    if args.weapon:
        cmd += ["--weapon=" + args.weapon]
    if args.negative:
        cmd += ["--negative=" + args.negative]
    if args.move:
        cmd += ["--move=" + args.move]
    if args.contact_control:
        cmd += ["--contact-control=" + args.contact_control]
    if args.native:
        cmd += ["--capture"]
        cmd = [sys.executable, str(ROOT / "tools/comfyui/gpu_lock.py"), "--"] + cmd
    env = os.environ.copy(); env.update(APPDATA=str(out / "user"), LOCALAPPDATA=str(out / "user"), XDG_DATA_HOME=str(out / "user"), PYTHONUTF8="1")
    started = time.monotonic(); timed_out = False
    with (out / "process.log").open("wb") as log:
        process = subprocess.Popen(cmd, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=args.timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            # Only the process tree started immediately above; never broad Godot/service cleanup.
            if os.name == "nt":
                subprocess.run(["taskkill", "/PID", str(process.pid), "/T", "/F"], stdout=log, stderr=log, check=False)
            else:
                os.killpg(process.pid, signal.SIGKILL)
            code = process.wait(timeout=15)
    after = {p: sha(ROOT / p) for p in inputs}
    text = (out / "process.log").read_text(encoding="utf-8", errors="strict")
    diagnostics = [line for line in text.splitlines() if re.search(r"^ERROR:|SCRIPT ERROR|Parse Error|leaked at exit|resources still in use|crashed|handle_crash:", line)]
    errors = []
    try:
        data = json.loads((out / "result.json").read_text(encoding="utf-8"))
        if args.native and (data.get("renderer") != "forward_plus" or data.get("display") == "headless" or not data.get("adapter")):
            errors.append("native Forward+ device observations required")
        if args.mode in ["motion", "contacts"]:
            sides = [-1, 1] if args.facing == "both" else [int(args.facing)]
            expected = set()
            for id, profile in WEAPONS.items():
                if args.weapon and id != args.weapon:
                    continue
                definition = json.loads((ROOT / f"data/melee/{profile}.json").read_text(encoding="utf-8"))
                moves = list(definition["combo"])
                extension = definition.get("extension", {})
                if extension.get("attack"):
                    moves.append(extension["attack"])
                for side in sides:
                    if not args.negative:
                        expected.update(f"{id}/{side}/{move}" for move in moves if not args.move or args.move == move)
                    if not args.move or args.move == definition['hold']['attack']:
                        expected.add(f"{id}/{side}/{definition['hold']['attack']}-held")
            errors += verify_motion(data, expected, out, args.native)
            if args.mode == "contacts":
                contact_data = json.loads((out / "contact-result.json").read_bytes())
                errors += verify_contacts(contact_data, expected, out, args.native)
        elif args.mode == "feedback":
            expected = set()
            sides = [-1, 1] if args.facing == "both" else [int(args.facing)]
            for id, profile in WEAPONS.items():
                if args.weapon and id != args.weapon:
                    continue
                definition = json.loads((ROOT / f"data/melee/{profile}.json").read_text(encoding="utf-8"))
                combo = definition["combo"]
                choices = [combo[0]] + ([combo[-1]] if len(combo) > 1 else [])
                expected.update(f"{id}/{side}/{move}/reduced-{str(reduced).lower()}" for side in sides for reduced in [False, True] for move in choices)
            events = json.loads((ROOT / "data/feel/sound_events.json").read_text(encoding="utf-8"))["events"]
            errors += verify_feedback(data, expected, events)
        else:
            errors += verify_gait(data)
        if args.native and args.mode == "feedback":
            with wave.open(str(out / "master.wav"), "rb") as wav:
                samples = wav.readframes(wav.getnframes())
                if wav.getnframes() < wav.getframerate() or not any(samples):
                    errors.append("native WAV must contain nonzero recorded audio")
    except (OSError, ValueError, KeyError, TypeError, wave.Error) as error:
        errors.append(str(error))
    if before != after:
        errors.append("source/assets changed during process")
    if diagnostics:
        errors.append("engine/probe diagnostics")
    binaries = {str(args.godot.resolve()): sha(args.godot)}
    companion = args.godot.with_name(args.godot.name.replace("_console.exe", ".exe"))
    if companion != args.godot and companion.is_file():
        binaries[str(companion.resolve())] = sha(companion)
    receipt = {"command": cmd, "engine_sha256": sha(args.godot), "engine_binaries_sha256": binaries, "source_before_sha256": before, "source_after_sha256": after, "exit": code, "timeout_exceeded": timed_out, "wall_seconds_not_performance": round(time.monotonic() - started, 3), "diagnostics": diagnostics, "verification_errors": errors, "passed": code == 0 and not timed_out and not errors}
    files = [p for p in out.rglob("*") if p.is_file() and "user" not in p.relative_to(out).parts and "__pycache__" not in p.parts and p.suffix != ".pyc"]
    receipt["files_sha256"] = {p.relative_to(out).as_posix(): sha(p) for p in files}
    write(out / "run.json", receipt)
    with zipfile.ZipFile(out / "raw.zip", "w", zipfile.ZIP_DEFLATED) as archive:
        for path in files + [out / "run.json"]:
            archive.write(path, path.relative_to(out).as_posix())
    print(json.dumps({"passed": receipt["passed"], "exit": code, "errors": errors, "raw_zip_sha256": sha(out / "raw.zip")}, ensure_ascii=False), flush=True)
    return 0 if receipt["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
