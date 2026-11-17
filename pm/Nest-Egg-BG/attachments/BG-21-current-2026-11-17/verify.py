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

guard=data('affected/source-before.json')
require(guard==data('affected/source-after.json') and data('affected/result.json')['exit']==0 and data('affected/result.json')['source_held'],'formal source guard')
require(b'checks: 19275, new failures: 0' in read('affected/raw.log') and b'Detected script errors' not in read('affected/raw.log'),'original affected checks')
for path in ['game/props/fixture_art.gd','tests/suite/test_environment.gd']:
    require(hashlib.sha256(read('source/'+path)).hexdigest()==guard[path],'same tested source')
native=data('native/source-before.json')
require(native==data('native/high-source-before.json')==data('native/high-source-after.json'),'native source guards')
core=data('core-fixtures-v3/source-before.json')
require(core==data('core-fixtures-v3/source-after.json')==native,'same actual campaign source')
require(all(guard[p]==v for p,v in native.items()),'native matches tested product')
counter=data('native/runs.json')[0]
require(counter['name']=='counter' and counter['exit']==counter['script_errors']==0 and counter['source_held'],'logical old/current control')
require(read('native/counter/raw.log').count(b'BG21_COUNTER ')==1,'actual cache counter')
count=0
for group,runs,expected,checks in [('native',[data('native/runs.json')[1],data('native/high-run.json')[0]],17,29),('core-fixtures-v3',data('core-fixtures-v3/runs.json'),11,20)]:
    for run,quality in zip(runs,['low','high']):
        require(run['exit']==run['script_errors']==0 and run['source_held'] and run['images']==expected,'native exit, source and image count')
        folder=group+'/'+quality+'/'
        report=data(folder+'receipt.json')
        require(report['failures']==0 and report['checks']==checks and report['quality']=={'low':0,'high':2}[quality] and len(report['shots'])==expected,'actual quality and checks')
        raw=read(folder+'raw.log')
        require(b'Forward+' in raw and b'9070 XT' in raw and b'SCRIPT ERROR:' not in raw,'actual physical native renderer')
        for shot in report['shots']:
            png=read(folder+shot['file'])
            require(png[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',png[16:24])==(1280,720),'actual PNG size')
            count+=1
require(count==56,'all final native captures')
assets=data('asset-audit/result.json')
require(len(assets['assets'])==7 and assets['png_bytes']==7437 and assets['rgba_bytes_without_mips']==1011712,'asset footprint audit')
for item in assets['assets']:
    require(item['same_generated_rgba'] and hashlib.sha256(read('source/'+item['path'])).hexdigest()==item['sha256'],'original procedural assets')
require(data('history/core-fixtures/runs.json')[0]['script_errors']==1,'rejected observer failure retained')
require(data('history/core-fixtures/intentional-close.json')['accepted'] is False,'owned rejected run cancellation retained')
print(json.dumps({'members':len(members),'native_images':count,'original_affected_checks':19275,'actual_mechanism_checks':98,'cache_counter':1,'failures':0},indent=2))
