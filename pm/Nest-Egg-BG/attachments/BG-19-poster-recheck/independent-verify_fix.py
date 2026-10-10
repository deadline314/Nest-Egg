import sys,json,hashlib,importlib.util
from pathlib import Path
sys.dont_write_bytecode=True
R=Path('C:/tmp/Nest-Egg-poster-support');sys.path.insert(0,str(R/'tools/level'))
spec=importlib.util.spec_from_file_location('booth_review',R/'tools/level/build_ch1.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
a=m.build_booth_alley();actual=json.loads((R/'data/levels/ch1_booth_alley_map.json').read_text(encoding='utf8'))
raw=next(e for e in a.props if e['id']=='anchor_phone_booth__poster_wall');prepared=m.prepare_props(a.props,a.id)
print('raw',raw,'prepared',next(e for e in prepared if e['id']==raw['id']))
print('props exact',prepared==actual['props'],'count',len(prepared))
print('grid representation',type(a.grid).__name__,vars(a.grid).keys())
formalrows=[''.join(seg[y] for seg in actual['segments']) for y in range(len(actual['segments'][0]))]
rows=[''.join(a.grid.at(x,y) for x in range(a.w)) for y in range(m.H)]
print('grid exact',rows==formalrows)
policy=json.loads((R/'assets_src/pipeline/scenery_placement.json').read_text(encoding='utf8'));print('poster override removed','anchor_phone_booth__poster_wall:28' not in policy['overrides']['ch1_booth_alley'])
paths=['tools/level/build_ch1.py','assets_src/pipeline/scenery_placement.json','data/levels/ch1_booth_alley_map.json','tests/suite/test_scene_sanity.gd']
r={'root':str(R),'raw_poster':raw,'props_exact':prepared==actual['props'],'grid_exact':rows==formalrows,'override_removed':'anchor_phone_booth__poster_wall:28' not in policy['overrides']['ch1_booth_alley'],'sha256':{p:hashlib.sha256((R/p).read_bytes()).hexdigest() for p in paths}}
Path('C:/tmp/scenery-wall-independent/poster-source-verification.json').write_text(json.dumps(r,indent=2)+'\n')
