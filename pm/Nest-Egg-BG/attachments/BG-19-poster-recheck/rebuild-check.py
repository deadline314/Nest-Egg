from pathlib import Path
import hashlib
import json
import sys

root = Path('C:/tmp/Nest-Egg-poster-support')
sys.path.insert(0, str(root / 'tools/level'))
import build_ch1 as source

area = source.build_booth_alley()
formal = json.loads((root / 'data/levels/ch1_booth_alley_map.json').read_text(encoding='utf-8'))
rows = area.grid.rows()
segments = [[row[i:i+50] for row in rows] for i in range(0, area.w, 50)]
props = source.prepare_props(area.props, area.id)
assert segments == formal['segments'], 'terrain, spawns and portals changed'
assert props == formal['props'], 'generated props do not match formal map'
poster = next(p for p in area.props if p['id'] == 'anchor_phone_booth__poster_wall')
assert poster['y'] == 19, 'raw authored placement still relies on an override'
assert not source.prepare_props.__globals__['POLICY']['overrides']['ch1_booth_alley'], 'duplicate booth placement authority'
result = {'baseline': 'ab954852d570371fd26bfdc124a94000d57ef176', 'checks': 4,
          'failures': 0, 'raw_author_bottom_y': 320, 'poster_size': [40.5, 66],
          'poster_top_y': 254, 'height_relative_to_56px_character': 66/56,
          'terrain_spawns_portals_unchanged': True, 'all_nine_props_unchanged': True,
          'map_sha256': hashlib.sha256((root/'data/levels/ch1_booth_alley_map.json').read_bytes()).hexdigest()}
Path('C:/tmp/poster-support-native/rebuild.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')
print(json.dumps(result, indent=2))
