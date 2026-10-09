"""Apply the reviewed support classification and placements when rebuilding maps."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
POLICY = json.loads((ROOT / "assets_src/pipeline/scenery_placement.json").read_text(encoding="utf-8"))

def prepare_props(props, level_id):
    if not level_id.startswith(("ch1_", "level_")):
        level_id = "ch1_" + level_id
    result = []
    for authored in props:
        entry = dict(authored)
        ident = entry["id"]
        override = POLICY["overrides"].get(level_id, {}).get(f'{ident}:{entry["x"]}', {})
        if override.get("remove"):
            continue
        if ident in POLICY["wall"] and not entry.get("ground"):
            entry["support"] = "wall"
        elif ident in POLICY["ceiling"]:
            entry.pop("ground", None)
            entry.pop("dy", None)
            entry.update(support="ceiling", ceiling_row=4)
        elif ident in POLICY["ground"]:
            entry.pop("y", None)
            entry.pop("dy", None)
            entry["ground"] = True
        entry.update(override)
        result.append(entry)
    return result

def prepare_grid(grid, level_id):
    for x, y in POLICY.get("remove_decor", {}).get(level_id, []):
        if grid.at(x, y) in "$%@":
            grid.put(x, y, ".")
    for x, y, target_x, target_y in POLICY.get("move_decor", {}).get(level_id, []):
        char = grid.at(x, y)
        if char not in "$%@" or grid.at(target_x, target_y) != ".":
            raise ValueError(f"{level_id}: invalid scenery move {(x, y)} -> {(target_x, target_y)}")
        grid.put(target_x, target_y, char)
        grid.put(x, y, ".")
