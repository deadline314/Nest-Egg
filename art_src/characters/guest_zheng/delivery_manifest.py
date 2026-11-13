"""List only NE-267 owned changes, with raw bytes/SHA; never stage or commit."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / "pm/Nest-Egg/attachments/NE-267-guest-rigs"
PRODUCT = [
    ".agents/skills/character-art-pipeline/SKILL.md", ".agents/skills/portrait-to-godot/SKILL.md", ".agents/skills/rig-animation/SKILL.md",
    ".claude/skills/character-art-pipeline/SKILL.md", ".claude/skills/portrait-to-godot/SKILL.md", ".claude/skills/rig-animation/SKILL.md",
    "design/12-cast-redraw/CH2_SUPPORTING_CAST.md", "design/12-cast-redraw/NATIVE_CROP_PHASE.md", "design/12-cast-redraw/JOINT_AUDIT_CONTEXT.md",
    "tools/comfyui/build_character.py", "tools/comfyui/character_source.py", "tools/comfyui/test_character_source.py",
    "tools/comfyui/field_spec.py", "tools/comfyui/make_parts.py", "tools/comfyui/test_stage_resolution.py",
    "tools/comfyui/refine_parts.py", "tools/comfyui/test_underlap_material.py", "tools/comfyui/cut_layers.py",
    "tools/comfyui/crop_phase.py", "tools/comfyui/check_spec.py", "tools/comfyui/test_crop_phase.py",
    "tools/comfyui/test_guest_contact_source.py", "tools/comfyui/test_guest_material_registration.py",
    "tools/comfyui/recipes/guest_zheng.json", "tools/comfyui/specs/guest_zheng_side.json",
    "game/cutscene/cutscene_player.gd", "game/rig/npc_animator.gd",
    "tests/suite/test_cutscene.gd", "tests/suite/test_npc_animation.gd", "tests/helpers/seated_move_checks.gd", "tests/helpers/seated_move_checks.gd.uid",
    "tools/story/ch2_source.py", "tools/story/guest_ticket_staging.py", "tools/story/test_ch2_guest_cast.py",
    "tools/assets/stage_defs.py", "tools/assets/build_guest_paper.py",
    "tools/rig_joint_audit.gd", "tools/rig_preview.gd", "tools/npc_motion_strip.gd",
    "tools/ne267_guest_scene_probe.gd", "tools/ne267_guest_scene_probe.gd.uid", "tools/ne267_guest_scene_probe.tscn",
    "tools/ne267_failed_joint_trace.gd", "tools/ne267_failed_joint_trace.gd.uid", "tools/ne267_failed_joint_trace.tscn",
    "tools/npc_joint_scope.py", "tools/check_npc_joint_scope.py", "tools/test_npc_joint_scope.py",
    "art/characters/guest_zheng", "art/rigs/guest_zheng.json", "art/motion/guest_zheng.json",
    "data/story/ch2_heron.json", "data/cutscene/stages/ch2_guest_book_room.json",
    "art/environment/scene_props/guest_book_contacts", "assets_src/pipeline/guest_book_contacts.json",
    "assets_src/pipeline/guest_book_contacts-receipt.json",
    "art_src/characters/guest_zheng", "art_src/characters/guest_chen", "art_src/characters/guest_hong",
]
EVIDENCE = ["pm/Nest-Egg/attachments/NE-267-guest-rigs", "pm/Nest-Egg/images/NE-267-zheng-rig",
            "pm/Nest-Egg/images/NE-267-zheng-material", "pm/Nest-Egg/[NE-267]補畫第二章新登場的配角.md"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("kind", choices=("validation", "delivery"))
    parser.add_argument("--tag", required=True)
    args = parser.parse_args()
    if Path(args.tag).name != args.tag or "/" in args.tag or "\\" in args.tag:
        raise ValueError("tag must be one new manifest basename")
    destination = OUT / (args.tag + ".json")
    if destination.exists():
        raise ValueError("Preserve previous manifest; choose a new tag")
    scopes = PRODUCT + (EVIDENCE if args.kind == "delivery" else [])
    names = set()
    for command in (["git", "diff", "--name-only", "-z", "HEAD", "--", *scopes],
                    ["git", "ls-files", "--others", "--exclude-standard", "-z", "--", *scopes]):
        result = subprocess.run(command, cwd=ROOT, capture_output=True, check=True)
        names.update(value.decode("utf8") for value in result.stdout.split(b"\0") if value)
    records = []
    for name in sorted(names):
        path = ROOT / name
        if not path.is_file():
            raise ValueError("Unexpected deleted/non-file owned input: " + name)
        size = path.stat().st_size
        if path.suffix.lower() == ".zip" and size >= 45 * 1024 * 1024:
            raise ValueError("Oversized remote archive; keep original local and split evidence: " + name)
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(block)
        records.append(dict(path=name, bytes=size, sha256=digest.hexdigest()))
    receipt = dict(classification="NE-267 owned changes only; no stage/commit performed", kind=args.kind,
                   shared_skill_files="Stage only NE-267 retained-source/NPC/crop paragraphs; preserve any other ticket's hunks",
                   native_source_scope="Frozen working-tree union source ZIPs, not an exact published HEAD claim",
                   count=len(records), bytes=sum(record["bytes"] for record in records), files=records)
    destination.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf8", newline="\n")
    destination.with_suffix(".txt").write_text("\n".join(record["path"] for record in records) + "\n", encoding="utf8", newline="\n")
    print(destination, len(records), "files", receipt["bytes"], "bytes")


if __name__ == "__main__":
    main()
