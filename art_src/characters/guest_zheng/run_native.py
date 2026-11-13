"""Repeatable, serial NE-267 native checks; run only after the team's GPU handoff."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs"
GODOT = os.environ.get("GODOT", "C:/Tools/Godot/Godot_v4.7.2-stable_win64_console.exe")


def git_head():
    result = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True)
    return result.stdout.decode("ascii").strip() if result.returncode == 0 else None


def run(name, command):
    log = OUT / (name + ".log")
    start = time.monotonic()
    with log.open("wb") as stream:
        result = subprocess.run(command, cwd=ROOT, stdout=stream, stderr=subprocess.STDOUT,
                                env={**os.environ, "PYTHONUTF8": "1"})
    errors = re.findall(rb"(?m)^\s*(?:SCRIPT ERROR:|ERROR:).*$", log.read_bytes())
    receipt = dict(command=command, log=log.name, seconds=time.monotonic() - start,
                   exit_code=result.returncode, engine_errors=[e.decode("utf8", "replace") for e in errors])
    (OUT / (name + "-run.json")).write_text(json.dumps(receipt, indent=2), encoding="utf8")
    print(name, receipt["exit_code"], "errors", len(errors), flush=True)
    return result.returncode == 0 and not errors


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("phase", choices=["bootstrap", "import", "scene", "performance", "transitions", "flow", "colour"])
    parser.add_argument("--tag", required=True, help="new evidence name; never overwrite an earlier run")
    parser.add_argument("--frames", type=int, help="short diagnosis override; final coverage uses default 360/120")
    parser.add_argument("--joints", help="optional scoped sensor or failure-control joints")
    parser.add_argument("--displace-part", help="explicit failure control, never a normal run")
    parser.add_argument("--trace-joint", help="read-only material UV/transform trace on the first frame")
    parser.add_argument("--trace-frame", type=int, default=0)
    parser.add_argument("--npc-pose", help="scope one existing NPC performance state")
    parser.add_argument("--diagnostic-include-part", help="explicit single-factor visibility control; not normal acceptance")
    parser.add_argument("--diagnostic-whole-rig", action="store_true", help="whole visible silhouette control, not isolated joint acceptance")
    parser.add_argument("--alpha-only", action="store_true", help="optional white diagnostic RGB; alpha must be A/A verified")
    parser.add_argument("--diagnostic-part-texture", help="part:absolute-native-PNG; explicit unchanged-pivot failure control")
    parser.add_argument("--joint-context", action="store_true", help="record same-frame actual bone anchors; never changes native alpha")
    parser.add_argument("--zooms", default="1,2.2,3.4,3.7")
    parser.add_argument("--expected-animator-sha", help="refuse to run if the team's frozen shared source changed")
    parser.add_argument("--capture-only", action="store_true", help="capture valid native inputs; explicitly defer all acceptance checkers")
    args = parser.parse_args()
    if args.capture_only and args.phase not in {"performance", "transitions"}:
        parser.error("--capture-only applies only to joint frame captures")
    if args.frames is not None and args.frames < 1:
        parser.error("--frames must be positive")
    name = args.tag
    if (OUT / (name + "-run.json")).exists():
        raise SystemExit("Refusing to overwrite a prior evidence receipt")
    sources = [ROOT / f for f in ["tools/ne267_guest_scene_probe.gd", "tools/rig_joint_audit.gd",
                                 "tools/rig_preview.gd", "tools/npc_motion_strip.gd",
                                 "tools/viewport_capture.gd", "tools/check_joint_frames.py", "tools/story/ch2_source.py",
                                 "tools/npc_joint_scope.py", "tools/check_npc_joint_scope.py",
                                 "tools/comfyui/refine_parts.py", "tools/comfyui/cut_layers.py", "tools/comfyui/make_parts.py",
                                 "tools/comfyui/crop_phase.py", "tools/comfyui/check_spec.py",
                                 "tools/comfyui/build_character.py", "tools/comfyui/character_source.py", "tools/comfyui/field_spec.py",
                                 "tools/story/guest_ticket_staging.py", "data/story/ch2_heron.json",
                                 "tools/comfyui/specs/guest_zheng_side.json", "tools/comfyui/recipes/guest_zheng.json",
                                 "art_src/characters/guest_zheng/hand_contact.json", "art_src/characters/guest_zheng/cut_registration.json",
                                 "art_src/characters/guest_zheng/02_pose/hand_contact_original.json",
                                 "art_src/characters/guest_zheng/register_hand_contact.py",
                                 "art_src/characters/guest_zheng/register_joint_repairs.py",
                                 "tools/assets/build_guest_paper.py", "assets_src/pipeline/guest_book_contacts.json",
                                 "assets_src/pipeline/guest_book_contacts-receipt.json",
                                 "data/cutscene/stages/ch2_guest_book_room.json", "art/rigs/guest_zheng.json",
                                 "art/motion/guest_zheng.json", "art/characters/guest_zheng/character.json"]]
    sources.append(Path(__file__).resolve())
    if args.diagnostic_part_texture:
        sources.append(Path(args.diagnostic_part_texture.split(":", 1)[1]).resolve())
    sources += [ROOT / f for f in ["game/rig/character_rig.gd", "game/rig/rig_part_mesh.gd",
                "game/rig/humanoid_animator.gd", "game/rig/npc_animator.gd", "game/rig/npc_life.gd",
                "art/rigs/npc_animations.json", "game/cutscene/cutscene_actor.gd", "game/cutscene/cutscene_player.gd",
                "game/cutscene/stage_prop_hold.gd", "game/cutscene/stage_prop_binding.gd"]]
    sources += sorted((ROOT / "art/characters/guest_zheng/parts").glob("*.png"))
    sources += sorted((ROOT / "art/characters/guest_zheng/parts").glob("*.png.import"))
    sources += sorted((ROOT / "art/environment/scene_props/guest_book_contacts").glob("*"))
    # Preserve the actual rig/cutscene/lighting framework, not just the role JSON.
    for directory in ("game/rig", "game/cutscene", "core"):
        sources += sorted((ROOT / directory).glob("*.gd"))
    sources += sorted((ROOT / "art/shaders").glob("*.gdshader"))
    project = ROOT / "project.godot"
    sources.append(project)
    section = ""
    for line in project.read_text(encoding="utf8").splitlines():
        if line.startswith("["):
            section = line
        if section == "[autoload]":
            match = re.search(r'="\*?res://([^"]+)"', line)
            if match:
                sources.append(ROOT / match[1])
    sources = list(dict.fromkeys(sources))
    head_before = git_head()
    before = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    if args.expected_animator_sha and before["game/rig/humanoid_animator.gd"] != args.expected_animator_sha:
        raise SystemExit("Shared HumanoidAnimator differs from the team's frozen expected SHA")
    with zipfile.ZipFile(OUT / (name + "-source.zip"), "w", zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sources:
            archive.writestr(path.relative_to(ROOT).as_posix(), path.read_bytes())
    if args.phase == "bootstrap":
        # New stage-state PNGs must be imported before any game autoload validates
        # them. In particular, the normals runtime comes AFTER this bootstrap.
        command = [sys.executable, "tools/comfyui/gpu_lock.py", "--", GODOT, "--path", str(ROOT),
                   "--headless", "--editor", "--quit"]
    elif args.phase == "import":
        # build_character already locks each Godot call. Do not acquire a nested lock.
        command = [sys.executable, "tools/comfyui/build_character.py", "--recipe",
                   "tools/comfyui/recipes/guest_zheng.json", "--from", "normals", "--to", "import"]
    else:
        folder = OUT / name
        folder.mkdir()
        command = [sys.executable, "tools/comfyui/gpu_lock.py", "--", GODOT, "--path", str(ROOT),
                   "--resolution", "1280x720", "--rendering-driver", "vulkan", "--rendering-method",
                   "forward_plus", "--audio-driver", "Dummy", "--max-fps", "120", "--quit-after", "18000"]
        if args.phase == "colour":
            # Four full bodies per 640-unit page: hands remain inside the page
            # at cutscene zoom. Each cell independently simulates the same seed.
            pages = [("sit-entry", "seated_converse", .8, .4),
                     ("sit-converse", "seated_converse", 2.0, 2.0),
                     ("sit-exit", "seated_converse", 9.9, .4),
                     ("wave-entry", "wave", .4, .5),
                     ("wave-exit", "wave", 2.5, .5)]
            ok = True
            for zoom in (2.2, 3.4, 3.7):
                for facing in (-1, 1):
                    for label, script, start, step in pages:
                        page = f"{label}-{zoom}-{facing}"
                        ok = run(name + "-" + page, command + [
                            "res://tools/npc_motion_strip.tscn", "--", "--chars=guest_zheng",
                            "--seat-sag=.298", f"--script={script}", "--frames=4",
                            f"--from={start}", f"--step={step}", f"--zoom={zoom}", f"--facing={facing}",
                            "--bright", f"--out={folder / (page + '.png')}"]) and ok
            (OUT / (name + "-run.json")).write_text(json.dumps({
                "phase": "colour", "pages": 30, "all_processes_passed": ok,
                "classification": "native full-body phase pages; fixed-step simulation, not human play",
                "frames_per_page": 4, "zooms": [2.2, 3.4, 3.7], "facings": [-1, 1],
                "pages_definition": pages}, indent=2), encoding="utf8")
            command = None
        elif args.phase == "flow":
            # Logic-only real interaction fixture; no native rendering claim or GPU lock.
            command = [GODOT, "--headless", "--path", str(ROOT), "--max-fps", "120", "--quit-after", "18000",
                       "res://tools/ch2_flow_probe.tscn", "--", "--guest-book-only", f"--out={folder}"]
        elif args.phase == "scene":
            command += ["res://tools/ne267_guest_scene_probe.tscn", "--", f"--out={folder}"]
        else:
            command += ["res://tools/rig_joint_audit.tscn", "--", "--chars=guest_zheng",
                        f"--out={folder}", "--seat-sag=.298", "--zooms=" + args.zooms,
                        "--npc-performance" if args.phase == "performance" else "--npc-transitions",
                        f"--frames={args.frames or (360 if args.phase == 'performance' else 120)}"]
            if args.joints:
                command.append("--joints=" + args.joints)
            if args.displace_part:
                command.append("--displace-part=" + args.displace_part)
            if args.trace_joint:
                command.append("--trace-joint=" + args.trace_joint)
                command.append("--trace-frame=" + str(args.trace_frame))
            if args.npc_pose:
                command.append("--npc-pose=" + args.npc_pose)
            if args.diagnostic_include_part:
                command.append("--diagnostic-include-part=" + args.diagnostic_include_part)
            if args.diagnostic_whole_rig:
                command.append("--diagnostic-whole-rig")
            if args.alpha_only:
                command.append("--alpha-only")
            if args.diagnostic_part_texture:
                command.append("--diagnostic-part-texture=" + args.diagnostic_part_texture)
            if args.joint_context:
                command.append("--joint-context")
    if command is not None:
        ok = run(name, command)
    after = {p.relative_to(ROOT).as_posix(): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources}
    (OUT / (name + "-source-hashes.json")).write_text(json.dumps({"before": before, "after": after,
                "unchanged": before == after, "phase": args.phase,
                "git_head_before": head_before, "git_head_after": git_head(),
                "note": "import phase intentionally regenerates normal maps; other source must be stable"}, indent=2), encoding="utf8")
    if args.phase not in {"import", "bootstrap"} and before != after:
        ok = False
    if ok and args.capture_only:
        (OUT / (name + "-acceptance-pending.json")).write_text(json.dumps({
            "classification": "native capture only; acceptance NOT yet evaluated",
            "raw_checker_required": "tools/check_joint_frames.py",
            "scope_checker_required": "tools/check_npc_joint_scope.py" if args.joint_context else None,
            "folder": folder.relative_to(ROOT).as_posix()}, indent=2) + "\n", encoding="utf8", newline="\n")
        print(name, "capture complete; acceptance pending", flush=True)
    if ok and not args.capture_only and args.phase in {"performance", "transitions"}:
        raw_ok = run(name + "-checker", [sys.executable, "tools/check_joint_frames.py", str(folder)])
        ok = raw_ok
        if args.joint_context:
            command = [sys.executable, "tools/check_npc_joint_scope.py", str(folder),
                       "--expected-chars=guest_zheng", "--expected-zooms=" + args.zooms]
            if args.frames is not None and args.frames != (360 if args.phase == "performance" else 120):
                command.append("--diagnostic")
            ok = run(name + "-scope-checker", command)
    raise SystemExit(0 if ok else 1)


if __name__ == "__main__":
    main()
