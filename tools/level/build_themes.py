#!/usr/bin/env python3
"""環境主題產生器：輸出 data/environment/themes/*.tres。

主題是「哪一段用哪種材質與立面」的資料；這個腳本只是方便一次改很多段後重新產生，
也可以直接在編輯器改 .tres。用法：python3 tools/level/build_themes.py
"""
import os

ROOT = os.path.join(os.path.dirname(__file__), '..', '..')
OUT = os.path.join(ROOT, 'data', 'environment', 'themes')

# 第一章：(起點欄, 標籤, 材質, 立面清單, 室內牆面貼圖 或 None, 鏤空機率)
CHAPTER_1 = [
    (0, "屋頂巷弄", "rooftop", ["apartment", "brick_block", "shutter_block"], None, 0.22),
    (53, "街道", "asphalt", ["apartment", "shutter_block", "shopfront"], None, 0.22),
    (70, "霓虹市集", "asphalt", ["shopfront", "apartment", "shutter_block"], None, 0.22),
    (160, "貨運站", "concrete", ["warehouse", "shutter_block", "brick_block"], None, 0.22),
    (240, "設施入口", "facility_floor", ["facility_wall"], "facility_panel", 0.0),
    (262, "停電走廊", "steel_plate", ["facility_wall"], "steel_plate", 0.0),
    (310, "頭目機庫", "hangar", ["warehouse"], "hangar_wall", 0.0),
]
BACKDROP = [("far_skyline", 0.12, 300.0), ("mid_buildings", 0.26, 320.0), ("near_foreground", 0.5, 360.0)]


def write_theme(name, zones, backdrop):
    ext = {}            # 路徑 -> id
    lines_ext = []

    def ref(path, kind="Resource"):
        if path not in ext:
            ext[path] = f"{len(ext) + 1}_{os.path.basename(path).split('.')[0]}"
            lines_ext.append(f'[ext_resource type="{kind}" path="{path}" id="{ext[path]}"]')
        return ext[path]

    zone_script = ref("res://data/scripts/env_zone.gd", "Script")
    theme_script = ref("res://data/scripts/environment_theme.gd", "Script")
    layer_script = ref("res://data/scripts/backdrop_layer.gd", "Script")
    facade_script = ref("res://data/scripts/facade_data.gd", "Script")
    layer_script_id = layer_script
    subs = []
    zone_ids = []
    for i, (start, label, material, facades, interior, holes) in enumerate(zones):
        mat = ref(f"res://data/environment/materials/{material}.tres")
        facade_refs = ", ".join(f'ExtResource("{ref(f"res://data/environment/facades/{f}.tres")}")' for f in facades)
        sid = f"Resource_zone{i}"
        zone_ids.append(sid)
        body = [f'[sub_resource type="Resource" id="{sid}"]', f'script = ExtResource("{zone_script}")',
                f'from_tile = {start}', f'material = ExtResource("{mat}")',
                f'facades = Array[ExtResource("{facade_script}")]([{facade_refs}])']
        if interior:
            body.append(f'interior = "res://art/environment/materials/{interior}_body.png"')
        body.append(f'hole_chance = {holes}')
        body.append(f'label = "{label}"')
        subs.append("\n".join(body))
    layer_ids = []
    for i, (tex, scroll, bottom) in enumerate(backdrop):
        sid = f"Resource_layer{i}"
        layer_ids.append(sid)
        subs.append("\n".join([f'[sub_resource type="Resource" id="{sid}"]', f'script = ExtResource("{layer_script_id}")',
                               f'texture = "res://art/environment/backdrop/{tex}.png"', f'scroll_scale = {scroll}', f'bottom_y = {bottom}']))
    zone_script_id = zone_script
    total = len(ext) + len(subs) + 1
    out = [f'[gd_resource type="Resource" script_class="EnvironmentTheme" load_steps={total} format=3]', ''] + lines_ext + [''] + \
        ["\n\n".join(subs), '', '[resource]', f'script = ExtResource("{theme_script}")',
         f'zones = Array[ExtResource("{zone_script_id}")]([' + ", ".join(f'SubResource("{z}")' for z in zone_ids) + '])']
    if layer_ids:
        out.append(f'backdrop = Array[ExtResource("{layer_script_id}")]([' + ", ".join(f'SubResource("{z}")' for z in layer_ids) + '])')
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + '.tres')
    with open(path, 'w') as f:
        f.write("\n".join(out) + "\n")
    print("wrote", path)


if __name__ == '__main__':
    write_theme('chapter1', CHAPTER_1, BACKDROP)
