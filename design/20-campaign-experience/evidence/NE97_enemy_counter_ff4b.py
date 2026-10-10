#!/usr/bin/env python3
"""Count enemy placements by resolving each LevelData legend to EnemyData resources."""
import argparse
import collections
import hashlib
import json
import pathlib
import re


COMMIT = "ff4b9dd095eab83076e030c92bb8625168f3cf43"


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resource_id(text):
    match = re.search(r'(?m)^id\s*=\s*&"([^"]+)"', text)
    return match.group(1) if match else None


def level_data(repo, level_id):
    for path in sorted((repo / "data/levels").glob("*.tres")):
        text = path.read_text(encoding="utf-8")
        block = re.search(r"(?s)\[resource\](.*?)(?=\n\[|\Z)", text)
        if block and re.search(rf'(?m)^id\s*=\s*&"{re.escape(level_id)}"', block.group(1)):
            return path, text, block.group(1)
    raise FileNotFoundError(f"LevelData id not found: {level_id}")


def enemy_resources(repo):
    result = {}
    for path in sorted((repo / "data/enemies").rglob("*.tres")):
        text = path.read_text(encoding="utf-8")
        if not re.search(r'\bscript_class="EnemyData"', text.splitlines()[0]):
            continue
        ident = resource_id(text)
        if ident:
            result[path.as_posix().replace(repo.as_posix() + "/", "")] = ident
    return result


def count_level(repo, level_id, known_enemy_resources):
    level_path, text, resource_block = level_data(repo, level_id)
    layout = re.search(r'(?m)^layout_path\s*=\s*"res://([^"]+)"', resource_block)
    if not layout:
        raise ValueError(f"No layout_path in {level_path}")
    map_path = repo / layout.group(1)
    data = json.loads(map_path.read_text(encoding="utf-8"))
    ext = {
        match.group(2): match.group(1)
        for match in re.finditer(
            r'\[ext_resource\s+type="Resource"\s+path="res://([^\"]+)"\s+id="([^\"]+)"\]', text
        )
    }
    legend_match = re.search(r"(?s)legend\s*=\s*Dictionary\[String, Resource\]\(\{(.*?)\}\)", resource_block)
    if not legend_match:
        raise ValueError(f"No Resource legend in {level_path}")
    glyph_to_id = {}
    glyph_to_path = {}
    for match in re.finditer(r'"(.)"\s*:\s*ExtResource\("([^"]+)"\)', legend_match.group(1)):
        glyph, ref = match.groups()
        path = ext.get(ref)
        if path and path.startswith("data/enemies/"):
            if path not in known_enemy_resources:
                raise ValueError(f"Enemy path is not a recognized EnemyData resource: {path}")
            glyph_to_id[glyph] = known_enemy_resources[path]
            glyph_to_path[glyph] = "res://" + path

    segments = []
    total = collections.Counter()
    for index, rows in enumerate(data["segments"], start=1):
        chars = collections.Counter(char for row in rows for char in row if char in glyph_to_id)
        ids = collections.Counter()
        for glyph, amount in chars.items():
            ids[glyph_to_id[glyph]] += amount
        total.update(ids)
        segments.append({
            "segment": index,
            "glyph_to_enemy_data_id": {
                glyph: {"id": glyph_to_id[glyph], "resource": glyph_to_path[glyph], "count": amount}
                for glyph, amount in sorted(chars.items())
            },
            "counter_by_id": dict(sorted(ids.items())),
            "enemy_count": sum(ids.values()),
        })
    return {
        "level_id": level_id,
        "level_data": level_path.as_posix().replace(repo.as_posix() + "/", ""),
        "level_data_sha256": sha256(level_path),
        "map_json": map_path.as_posix().replace(repo.as_posix() + "/", ""),
        "map_sha256": sha256(map_path),
        "legend_glyph_to_enemy_data_id": {
            glyph: {"id": ident, "resource": glyph_to_path[glyph]}
            for glyph, ident in sorted(glyph_to_id.items())
        },
        "segments": segments,
        "counter_by_id": dict(sorted(total.items())),
        "enemy_count": sum(total.values()),
        "identity_count": len(total),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo", required=True, help="Path to the checked-out Nest-Egg repository")
    parser.add_argument("--out", required=True, help="Output JSON path")
    args = parser.parse_args()
    repo = pathlib.Path(args.repo).resolve()
    roster_path = repo / "data/combat/chapter_rosters.json"
    roster = json.loads(roster_path.read_text(encoding="utf-8"))
    enemy_files = enemy_resources(repo)
    ch1_ids = roster["chapters"]["ch1_kasa"]["levels"]
    ch2_ids = roster["chapters"]["chapter_02"]["levels"]
    ch1_levels = [count_level(repo, level_id, enemy_files) for level_id in ch1_ids]
    ch2_levels = [count_level(repo, level_id, enemy_files) for level_id in ch2_ids]
    ch1_maps = {}
    for record in ch1_levels:
        ch1_maps.setdefault(record["map_json"], record)
    ch1_total = collections.Counter()
    for record in ch1_maps.values():
        ch1_total.update(record["counter_by_id"])
    ch2_total = collections.Counter()
    for record in ch2_levels:
        ch2_total.update(record["counter_by_id"])
    ch1_segment_total = sum(seg["enemy_count"] for rec in ch1_maps.values() for seg in rec["segments"])
    ch2_segment_total = sum(seg["enemy_count"] for rec in ch2_levels for seg in rec["segments"])
    assert sum(ch1_total.values()) == ch1_segment_total == 36, (sum(ch1_total.values()), ch1_segment_total)
    assert len(ch1_total) == 6, len(ch1_total)
    assert sum(ch2_total.values()) == ch2_segment_total == 36, (sum(ch2_total.values()), ch2_segment_total)
    assert len(ch2_total) == 18, len(ch2_total)
    assert set(ch1_total).isdisjoint(ch2_total), set(ch1_total) & set(ch2_total)
    result = {
        "basis_commit": COMMIT,
        "method": "LevelData layout_path -> map JSON segments; LevelData legend glyph -> ExtResource path; validate path against data/enemies/**/*.tres with script_class EnemyData and resource id; Counter each grid character by segment, then aggregate by EnemyData id.",
        "enemy_data_resource_count": len(enemy_files),
        "roster_sha256": sha256(roster_path),
        "formal_ch1": {
            "roster_enemy_ids": roster["chapters"]["ch1_kasa"]["enemies"],
            "level_ids": ch1_ids,
            "unique_maps": list(ch1_maps.values()),
            "counter_by_id": dict(sorted(ch1_total.items())),
            "enemy_count": sum(ch1_total.values()),
            "identity_count": len(ch1_total),
            "segment_enemy_count_sum": ch1_segment_total,
        },
        "legacy_chapter_02": {
            "roster_enemy_ids": roster["chapters"]["chapter_02"]["enemies"],
            "level_ids": ch2_ids,
            "maps": ch2_levels,
            "counter_by_id": dict(sorted(ch2_total.items())),
            "enemy_count": sum(ch2_total.values()),
            "identity_count": len(ch2_total),
            "segment_enemy_count_sum": ch2_segment_total,
        },
        "chapter_03_roster": roster["chapters"]["chapter_03"],
    }
    out = pathlib.Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({
        "basis_commit": COMMIT,
        "formal_ch1": {"count": result["formal_ch1"]["enemy_count"], "identities": result["formal_ch1"]["identity_count"], "counter": result["formal_ch1"]["counter_by_id"]},
        "legacy_chapter_02": {"count": result["legacy_chapter_02"]["enemy_count"], "identities": result["legacy_chapter_02"]["identity_count"], "counter": result["legacy_chapter_02"]["counter_by_id"]},
        "raw_json": str(out.resolve()),
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
