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
before = data('final/source-before.json')
require(before == data('final/source-after.json') and data('final/source-held.json')['source_held'] and len(before) == 9544, 'final source guard')
original = data('original/source-before.json')
require(original == data('original/source-after.json') and set(original) == set(before), 'original source guard')
require([p for p in original if original[p] != before[p]] == ['tools/scene_tour.gd'], 'only the scene-tour tool changed')
require(hashlib.sha256(read('source/scene_tour.gd')).hexdigest() == before['tools/scene_tour.gd'], 'final tool source')
require(hashlib.sha256(read('source/scene_tour-before.gd')).hexdigest() == original['tools/scene_tour.gd'], 'original tool source')
runs = data('final/runs.json')
require([r['mode'] for r in runs] == ['low', 'high', 'flat'], 'three visual modes')
pngs = 0
for run in runs:
    mode = run['mode']
    require(run['exit'] == run['script_errors'] == 0 and len(run['levels']) == 11 and run['images'] == 279, 'full native run')
    log = read('final/' + mode + '/raw.log')
    require(b'Forward+' in log and b'9070 XT' in log and b'SCRIPT ERROR:' not in log, 'physical GPU and no script error')
    for level in run['levels']:
        current = data(f'final/{mode}/{level}/{mode}-index.json')
        low = data(f'final/low/{level}/low-index.json')
        require(len(current['shots']) == current['columns'] * current['rows'] and current['suppressed_player_prompts'] >= 0, 'complete indexed grid')
        for shot, reference in zip(current['shots'], low['shots']):
            require((shot['column'], shot['row']) == (reference['column'], reference['row']) and all(abs(a-b) < .001 for a,b in zip(shot['world'], reference['world'])), 'same native world cell')
            image = read(f"final/{mode}/{level}/{shot['file']}")
            require(image[:8] == b'\x89PNG\r\n\x1a\n' and struct.unpack('>II', image[16:24]) == (1280,720), 'actual full native PNG')
            pngs += 1
require(pngs == 837, 'all native images')
controls = data('controls/runs.json')
require([r['mode'] for r in controls] == ['static','shown-player','walking-player'] and [r['suppressed_player_prompts'] for r in controls] == [27,0,0], 'actual static and player counter controls')
require(all(r['exit'] == r['script_errors'] == 0 and r['images'] == 1 for r in controls) and data('controls/source-held.json')['source_held'], 'counter-control exits and source')
require(data('affected/result.json')['exit'] == 0 and data('sanity/result.json')['exit'] == 0 and data('sanity/result.json')['script_errors'] == 0, 'original checks exit')
require(b'checks: 459, new failures: 0' in read('sanity/raw.log'), 'actual scene sanity terminal count')
print(json.dumps({'members':len(members),'native_images':pngs,'levels':11,'scene_sanity_checks':459,'prompt_controls':[27,0,0],'failures':0}, indent=2))
