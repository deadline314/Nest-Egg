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

import re,statistics
guard=data('native-fit-final/source-before.json')
require(guard==data('native-fit-final/source-after.json') and data('native-fit-final/result.json')['all_passed'],'final native source guard')
for path in ['tools/scene_motion_probe.gd','tools/environment_motion_probe.gd']:
    require(hashlib.sha256(read('source/'+path)).hexdigest()==(data('chapter-focused-final/source-before.json') if path=='tools/environment_motion_probe.gd' else guard)[path],'exact final source')
def png(name):
    raw=read(name);require(raw[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',raw[16:24])==(1280,720),'actual native PNG '+name)
def clean(name):
    raw=read(name);require(b'Forward+' in raw and b'9070 XT' in raw and b'SCRIPT ERROR:' not in raw,'actual physical renderer');return raw
images=checks=0
runs=data('native-fit-final/runs.json');require(len(runs)==20,'twelve props, four props at three qualities')
for row in runs:
    require(row['exit']==row['script_errors']==0 and row['source_held'],'native natural exit and source')
    folder='native-fit-final/'+row['name']+'-'+row['quality']+'/'
    report=data(folder+row['name']+'-report.json');raw=clean(folder+'raw.log')
    require(report['failures']==0 and len(report['shots'])==row['images'],'actual native checks')
    framing=[json.loads(line.split(b'BG25_FRAMING ',1)[1]) for line in raw.splitlines() if line.startswith(b'BG25_FRAMING ')]
    observer=[json.loads(line.split(b'BG25_OBSERVER ',1)[1]) for line in raw.splitlines() if line.startswith(b'BG25_OBSERVER ')]
    require(len(framing)==len(observer)==1 and framing[0]['entire_prop_visible'] and observer[0]['held'] and observer[0]['visible_prompts']==0,'full prop and light focus')
    if report['reentries']:
        entries=report['reentries'];require(len(entries)==10 and entries[1]['nodes']==entries[-1]['nodes'] and entries[-1]['orphans']==0,'ten real reentries')
    if 'pause' in report:require(report['pause']['before']==report['pause']['during'] and report['pause']['during']!=report['pause']['after'],'actual pause and resume clocks')
    for shot in report['shots']:png(folder+shot['file']);images+=1
    checks+=report['checks']
require(images==115,'all final prop originals')
context_guard=data('contexts-final/source-before.json');require(context_guard==data('contexts-final/source-after.json'),'context sources held')
require([p for p in guard if context_guard[p]!=guard[p]]==['tools/scene_motion_probe.gd'],'only later parent-run framing cap differs')
old=read('source-history/context_scene_motion_probe.gd');new=read('source/tools/scene_motion_probe.gd')
require(hashlib.sha256(old).hexdigest()==context_guard['tools/scene_motion_probe.gd'],'actual context parent source')
def body(source,name):
    start=source.index(('func '+name+'(').encode());end=source.find(b'\nfunc ',start+1);return source[start:end if end>=0 else len(source)].strip()
for name in ['_open_level','_find_prop','_settle','_check','_finish']:
    require(body(old,name)==body(new,name),'same used context helper '+name)
for row in data('contexts-final/runs.json'):
    require(row['exit']==row['script_errors']==0 and row['source_held'] and row['images']==11,'context native exit')
    folder='contexts-final/'+row['quality']+'/';report=data(folder+'context-report.json');raw=clean(folder+'raw.log')
    require(report['failures']==0 and report['damage_events']>0,'actual shot damage and all context checks')
    wrap=[s for s in report['shots'] if s['file']=='cycle-after-wrap.png'];require(len(wrap)==1 and wrap[0]['clock']<.2,'actual cycle seam crossed')
    require(b'"active":true' in raw and b'"paused":true' in raw,'actual NPC dialogue active')
    for shot in report['shots']:png(folder+shot['file']);images+=1
    checks+=report['checks']
chapter=data('chapter-focused-final/result.json');require(chapter['source_held'] and chapter['actual_route_exit']==chapter['actual_script_errors']==0 and chapter['route_images']==13,'reused successful original chapter route')
route=data('chapter-focused-final/runs.json')[0];require(route['images']==len(route['captures'])==13,'all thirteen actual chapter captures')
for shot in route['captures']:png('chapter-focused-final/route/'+shot['file']);images+=1
require(read('chapter-focused-final/route/raw.log').count(b'BG25_SWITCH cycle=')==10,'actual ten chapter roundtrips')
require([r['exit'] for r in data('chapter/runs.json')]==[0,1,1] and data('directory-control/result.json')['exit']==2,'actual capture and directory negatives; earlier driver error retained')
require([r['exit'] for r in data('environment-controls/runs.json')]==[0,0,1],'missing environment and actual save refusal control')
fixed=data('fixed-points/runs.json');require([r['exit'] for r in fixed]==[1,0,0,0] and not fixed[0]['framing'][0]['entire_prop_visible'],'old fixed zoom correctly rejected')
for row in fixed[1:]:
    require(row['framing'][0]['entire_prop_visible'] and row['source_held'] and row['script_errors']==0,'diagnostic fixed ends fully visible')
    for tick in [0,1300,2800,4200,5800]:png('fixed-points/'+row['name']+'/anchors-t%04d.png'%tick)
perf=data('perf/result.json');require(perf['source_held'] and perf['runs']==16 and data('perf/source-before.json')==data('perf/source-after.json'),'quiet current-source performance')
for row in data('perf/runs.json'):
    require(row['exit']==row['script_errors']==0 and row['source_held'] and not row['workload_before'] and not row['workload_after'],'own exclusive Godot timing')
    samples=row['BG25_PERF_SAMPLES'];require(len(samples)==180 and all(x>0 for x in samples),'all original frame intervals')
    require(row['BG25_WINDOWS_MEMORY']['working_set_bytes']>0 and row['BG25_WINDOWS_MEMORY']['private_bytes']>0,'actual Windows own-process memory')
require(data('affected-focused-final/result.json')['exit']==0 and data('affected-focused-final/result.json')['source_held'],'original changed entry')
require(data('local-tests/result.json')['exit']==0 and b'checks: 7663, new failures: 0' in read('local-tests/raw.log'),'extra existing local suites')
print(json.dumps({'members':len(members),'final_actual_light_images':images,'flat_diagnostic_images':15,'prop_and_context_checks':checks,'quiet_performance_runs':16,'extra_existing_checks':7663,'failures':0},indent=2))
