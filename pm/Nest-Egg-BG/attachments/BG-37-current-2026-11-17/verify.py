"""Read-only BG-37 evidence verification; Python 3.10+ and Pillow."""
from pathlib import Path, PurePosixPath
import hashlib
import io
import json
import re
import sys
import zipfile
from PIL import Image

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
index = json.loads((root / 'archives.json').read_text())
members = {}
def require(value, message):
    if not value: raise ValueError(message)
def sha(stream):
    result = hashlib.sha256()
    for block in iter(lambda: stream.read(1024*1024), b''): result.update(block)
    return result.hexdigest()
for archive in index['archives']:
    path = root / archive['file']
    require(path.parent.resolve() == root.resolve(), 'archive outside packet')
    with path.open('rb') as stream:
        require(path.stat().st_size == archive['bytes'] < 50_000_000 and sha(stream) == archive['sha256'], 'archive bytes')
    expected = {m['path']:m for m in archive['members']}
    require(len(expected) == len(archive['members']), 'duplicate manifest member')
    with zipfile.ZipFile(path) as source:
        require(len(source.infolist()) == len(expected), 'member count')
        for member in source.infolist():
            name = PurePosixPath(member.filename)
            require(not name.is_absolute() and '..' not in name.parts and '\\' not in member.filename and ':' not in member.filename, 'unsafe member')
            require(not any(p.lower() in ['private-profile','user','user-data','app_userdata'] or p.startswith('data_') for p in name.parts), 'profile included')
            require(member.filename in expected and member.filename.casefold() not in members, 'unexpected or duplicate member')
            row = expected[member.filename]
            with source.open(member) as stream:
                require(member.file_size == row['bytes'] and sha(stream) == row['sha256'], 'member bytes')
            members[member.filename.casefold()] = (archive['file'],member.filename)
    print(path.name, len(expected), 'verified', flush=True)
require(len(members) == index['file_count'], 'total member count')
def read(name):
    archive, member = members[name.casefold()]
    with zipfile.ZipFile(root/archive) as source: return source.read(member)
def data(name): return json.loads(read(name))
sources = data('native/source-before.json')
require(sources == data('native/source-after.json') and len(sources) == 9548 and data('native/source-held.json')['source_held'], 'native source guard')
for path in ['game/props/training_art.gd','tools/training_art_probe.gd']:
    require(hashlib.sha256(read('source/current/'+path)).hexdigest() == sources[path], 'current product bytes')
runs = data('native/runs.json')
require([r['name'] for r in runs] == ['art-low','art-high','actual-input'], 'native cases')
for run in runs:
    require(run['exit'] == run['script_errors'] == 0 and not run['unexpected_errors'], 'native exit and errors')
    log = read('native/'+run['name']+'/raw.log')
    require(b'Forward+' in log and b'9070 XT' in log and b'SCRIPT ERROR:' not in log, 'physical native GPU')
    if run['name'].startswith('art-'):
        quality = run['name'][4:]
        stations = data('native/'+run['name']+'/'+quality+'-report.json')['stations']
        require(len(stations) == 5 and all(s['has_art'] for s in stations), 'five authored stations')
    else:
        require(b'PROLOGUE_PLAY_PROBE failures=0' in log and b'PROLOGUE_PATH_PLAYED' in log, 'actual public-input route')
    pngs = [n for n in members if n.startswith('native/'+run['name']+'/') and n.endswith('.png')]
    require(len(pngs) == run['images'] == (9 if run['name']=='actual-input' else 36), 'complete native PNG count')
    for name in pngs:
        with Image.open(io.BytesIO(read(name))) as image: require(image.size == (1280,720), 'native dimensions')
lamp_runs = data('lamp/runs.json')
require([r['quality'] for r in lamp_runs] == ['low','high'], 'two lamp qualities')
measurements = 0
for run in lamp_runs:
    require(run['exit'] == run['script_errors'] == 0 and run['probe_source_held'] and len(run['measurements']) == 16, 'lamp native run')
    poses = [json.loads(line.removeprefix(b'ARM_CAPTURE ')) for line in read('lamp/'+run['quality']+'/raw.log').splitlines() if line.startswith(b'ARM_CAPTURE ')]
    require(len(poses)==2 and poses[0]['phase']=='warn' and poses[1]['phase']=='strike', 'rendered pose records')
    require(poses[0]['left'] > .8 and poses[0]['right'] < -.8 and abs(poses[1]['left']) < .1 and poses[1]['right'] > .4, 'warning and actual strike angles')
    for row in run['measurements']:
        x,y,w,h = row['rect']
        cx,cy = row['actual_center']; radius = row['physical_radius_px']
        require(w>0 and h>0 and w*h==row['total'] and x<=cx-radius and cx+radius<=x+w and y<=cy-radius and cy+radius<=y+h, 'nonempty enclosing lamp ROI')
        with Image.open(io.BytesIO(read('lamp/'+run['quality']+'/'+row['file']))) as image:
            require(list(image.size)==row['image_size']==[1280,720] and 0<=x<x+w<=1280 and 0<=y<y+h<=720, 'lamp geometry')
            crop = image.convert('RGB').crop((x,y,x+w,y+h))
            white = sum(all(c/255>row['threshold'] for c in crop.getpixel((px,py))) for py in range(h) for px in range(w))
        require(white == row['white'] == 0 and row['threshold']==.92, 'independent lamp pixels')
        measurements += 1
require(measurements==32, 'all lamp measurements')
empty = data('empty/run.json')
require(empty['exit']==1 and empty['specific_error'] and empty['script_errors']==0 and empty['source_held'], 'actual empty ROI rejection')
missing = data('missing/run.json')
counter = data('counter/run.json')
require(missing['exit']==missing['script_errors']==0 and missing['specific_paths_reported'] and len(missing['cases'])==2 and all(r['original_drawing'] and r['prompt_retained'] for r in missing['cases']), 'actual missing-texture fallback')
require(counter['exit']==counter['script_errors']==0 and len(counter['cases'])==2 and all(r['old_partial_art'] and r['current_original_drawing'] and r['children_held'] for r in counter['cases']), 'historical counter and current cache-poison protection')
formal = data('affected/result.json')
require(formal['exit']==0 and formal['source_held'] and data('affected/source-before.json')==data('affected/source-after.json'), 'original affected source and exit')
require(hashlib.sha256(read('source/current/tests/suite/test_environment.gd')).hexdigest() == data('affected/source-before.json')['tests/suite/test_environment.gd'], 'regression suite source')
terminal = read('affected/raw.log').decode('utf8')
match = re.search(r'checks: (\d+), new failures: 0, known failures .*: 0',terminal)
require(match is not None and 'Detected script errors' not in terminal, 'actual affected terminal')
require(data('import/run.json')['source_held'] and data('import/run.json')['generated_trim_caches'] and data('root-import/run.json')['source_held'], 'both actual checkout imports')
print(json.dumps({'members':len(members),'native_images':81,'lamp_measurements':measurements,'missing_texture_cases':2,'historical_counter_cases':2,'affected_checks':int(match.group(1)),'failures':0},indent=2))
