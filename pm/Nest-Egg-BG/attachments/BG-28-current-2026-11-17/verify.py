"""Read-only raw evidence verification, Python 3.10+, standard library only."""
from pathlib import Path, PurePosixPath
import hashlib
import json
import struct
import sys
import zipfile

root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent
index = json.loads((root / 'archives.json').read_text())
members = {}
def require(value, message):
    if not value: raise ValueError(message)
def sha(stream):
    value = hashlib.sha256()
    for block in iter(lambda: stream.read(1024 * 1024), b''): value.update(block)
    return value.hexdigest()
for archive in index['archives']:
    path = root / archive['file']
    require(path.parent.resolve() == root.resolve(), 'archive outside packet')
    with path.open('rb') as source:
        require(path.stat().st_size == archive['bytes'] < 50_000_000 and sha(source) == archive['sha256'], 'archive bytes: ' + path.name)
    expected = {m['path']: m for m in archive['members']}
    require(len(expected) == len(archive['members']), 'duplicate manifest member')
    with zipfile.ZipFile(path) as source:
        require(len(source.infolist()) == len(expected), 'member count')
        for member in source.infolist():
            name = PurePosixPath(member.filename)
            require(not name.is_absolute() and '..' not in name.parts and '\\' not in member.filename and ':' not in member.filename, 'unsafe member')
            require(not any(p.lower() in ['private-profile', 'app_userdata', 'user', 'user-data'] or p.startswith('data_') for p in name.parts), 'profile included')
            require(member.filename in expected and member.filename.casefold() not in members, 'unexpected or duplicate member')
            row = expected[member.filename]
            with source.open(member) as stream:
                require(member.file_size == row['bytes'] and sha(stream) == row['sha256'], 'member bytes: ' + member.filename)
            members[member.filename.casefold()] = (archive['file'], member.filename)
    print(path.name, len(expected), 'verified', flush=True)
require(len(members) == index['file_count'], 'total count')
def read(name):
    archive, member = members[name.casefold()]
    with zipfile.ZipFile(root / archive) as source: return source.read(member)
def data(name): return json.loads(read(name))

before=data('native/source-before.json')
require(before==data('native/source-after.json') and data('native/source-held.json')['source_held'] and len(before)==9548,'native source guard')
require(hashlib.sha256(read('source/current.gd')).hexdigest()==before['tools/scene_tour.gd'],'current tool source')
require(data('checks/source-before.json')==data('checks/source-after.json'),'formal source guard')
require(before['tools/scene_tour.gd']==data('checks/source-before.json')['tools/scene_tour.gd'],'same native and tested tool')
reference=data('reference/default-index.json')
def same_grid(a,b):
    return len(a['shots'])==len(b['shots']) and all((x['column'],x['row'])==(y['column'],y['row']) and all(abs(v-w)<.001 for v,w in zip(x['world'],y['world'])) for x,y in zip(a['shots'],b['shots']))
def size(raw):
    require(raw[:8]==b'\x89PNG\r\n\x1a\n','actual PNG')
    return list(struct.unpack('>II',raw[16:24]))
runs=data('native/runs.json')
require([r['tag'] for r in runs]==['ultrawide','four-three','sixteen-nine'],'three native aspect cases')
count=0
for run,window,capture in zip(runs,[[1680,720],[1024,768],[1280,720]],[[1280,720],[1024,576],[1280,720]]):
    require(run['exit']==run['script_errors']==0 and not run['unexpected_errors'] and run['source_held'] and run['images']==24,'native exit and count')
    tag=run['tag'];index=data('native/'+tag+'/ch1_rooftop/'+tag+'-index.json')
    require(index['window_size']==window and index['capture_size']==capture and index['columns']==4 and index['rows']==6 and len(index['shots'])==24 and same_grid(index,reference),'actual window, image and world grid')
    raw=read('native/'+tag+'/raw.log')
    require(b'Forward+' in raw and b'9070 XT' in raw and b'SCRIPT ERROR:' not in raw,'physical native rendering')
    for shot in index['shots']:
        require(size(read('native/'+tag+'/ch1_rooftop/'+shot['file']))==capture,'saved PNG dimensions')
        count+=1
require(count==72,'all final PNGs')
require(not same_grid(data('original/index.json'),reference),'actual original wrong-world counter')
require(data('first-corrected/index.json')['capture_size']!=size(read('first-corrected/first.png')),'actual texture-accessor mismatch counter')
require(data('first-corrected/rejected-first-corrected.json')['accepted'] is False,'first corrected rejection retained')
require(all(r['exit']==0 and r['source_held'] for r in data('checks/runs.json')),'original check exits')
require(b'checks: 459, new failures: 0' in read('checks/scene-sanity/raw.log') and b'Detected script errors' not in read('checks/scene-sanity/raw.log'),'actual459 scene checks')
print(json.dumps({'members':len(members),'native_images':count,'aspect_cases':3,'actual_metadata_counter_cases':2,'scene_sanity_checks':459,'failures':0},indent=2))
