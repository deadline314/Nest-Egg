"""Document every reviewed map prop, including unchanged placements, against a fixed base."""
import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools/level"))
from scenery_placement import prepare_props, POLICY
CONTACTS = json.loads((ROOT / "data/environment/scenery_contacts.json").read_text(encoding="utf-8"))


def rows_of(data):
    return ["".join(segment[y] for segment in data["segments"]) for y in range(len(data["segments"][0]))]


def rect_of(entry, size, rows, original=False):
    x = int(entry["x"])
    bottom = (int(entry.get("y", 0)) + 1) * 16
    if entry.get("ground"):
        center = min(max(x + int(size[0] / 32), 0), len(rows[0]) - 1)
        floors = [y for y in range(0 if original else 1, len(rows)) if rows[y][center] in ("#=" if original else "#=~") and (original or rows[y-1][center] != "#")]
        if not floors:
            return None
        bottom = floors[0] * 16
        if not original:
            bottom += size[1] * CONTACTS.get(entry["id"], {}).get("bottom_margin", 0)
    if not original and entry.get("support") == "ceiling":
        bottom = entry["ceiling_row"] * 16 + size[1]
    bottom += entry.get("dy", 0)
    return [round(x * 16 + entry.get("dx", 0), 2), round(bottom-size[1], 2), *size]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True)
    parser.add_argument("--out", required=True)
    args = parser.parse_args()
    sizes = {}
    for path in (ROOT / "data/environment").rglob("*.tres"):
        source = path.read_text(encoding="utf-8")
        ident = re.search(r'^id = &"([^\"]+)"', source, re.M)
        size = re.search(r'^size = Vector2\(([^,]+), ([^)]+)\)', source, re.M)
        if ident and size:
            sizes[ident[1]] = [float(size[1]), float(size[2])]
    levels = []
    for path in sorted((ROOT / "data/levels").glob("*_map.json")):
        relative = path.relative_to(ROOT).as_posix()
        original = json.loads(subprocess.check_output(["git", "show", args.base+":"+relative], cwd=ROOT))
        current = json.loads(path.read_text(encoding="utf-8"))
        level_id = path.stem.removesuffix("_map")
        unchanged = all(original.get(key) == current.get(key) for key in set(original) | set(current) if key not in ("props", "segments"))
        for old_row, new_row in zip(rows_of(original), rows_of(current)):
            unchanged = unchanged and len(old_row) == len(new_row) and all(a == b or (a in ".$%@" and b in ".$%@") for a, b in zip(old_row, new_row))
        if not unchanged:
            raise ValueError(f"{relative}: terrain, enemies, portals, regions, or story data changed during scenery rebuild")
        props = []
        for entry in original.get("props", []):
            prepared = prepare_props([entry], level_id)
            updated = prepared[0] if prepared else None
            before = rect_of(entry, sizes[entry["id"]], rows_of(original), True)
            after = rect_of(updated, sizes[entry["id"]], rows_of(current)) if updated else None
            changed = updated is None or before != after or entry != updated
            props.append({"id": entry["id"], "before": entry, "after": updated,
                          "before_world_rect": before, "after_world_rect": after,
                          "action": "removed" if updated is None else "corrected" if changed else "retained",
                          "support": updated.get("support", "ground") if updated else "none"})
        levels.append({"map": relative, "terrain_and_spawns_unchanged": unchanged, "props_before": len(original.get("props", [])), "props_after": len(current.get("props", [])),
                       "decor_removed_cells": POLICY.get("remove_decor", {}).get(level_id, []),
                       "decor_moved_cells": POLICY.get("move_decor", {}).get(level_id, []), "props": props})
    result = {"base": args.base, "levels": levels, "stages": sorted(p.stem for p in (ROOT/"data/cutscene/stages").glob("*.json"))}
    target = Path(args.out)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(result, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
    print(f"{len(levels)} maps, {sum(x['props_before'] for x in levels)} props, {len(result['stages'])} stages -> {target}")


if __name__ == "__main__":
    main()
