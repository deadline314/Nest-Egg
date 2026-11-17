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

import math,re,statistics
formal=data('root-affected-guarded-final/result.json')
guard=data('root-affected-guarded-final/source-before.json')
require(formal['exit']==0 and formal['source_held'] and guard==data('root-affected-guarded-final/source-after.json'),'final original source guard')
require(b'checks: 64722, new failures: 0, known failures' in read('root-affected-guarded-final/raw.log'),'original 63-group terminal result')
for p in [p for p in guard if 'source/'+p in members]:
    require(hashlib.sha256(read('source/'+p)).hexdigest()==guard[p],'tested source '+p)
images=0
for prefix in ['readability-guarded-final','readability-guarded-full-final']:
    result=data(prefix+'/result.json')
    require(result['source_held'] and result['all_original_thresholds_passed'] and len(result['runs'])==8,'all eight native samplers')
    require(data(prefix+'/source-before.json')==data(prefix+'/source-after.json'),'native source guard')
    for run in result['runs']:
        require(run['exit']==run['script_errors']==0 and run['source_held'] and run['spots']==run['expected_spots'],'native exit and point count')
        folder=prefix+'/'+run['scene']+'-'+run['quality']+'/'
        log=read(folder+'raw.log')
        require(b'Forward+' in log and b'9070 XT' in log and b'SCRIPT ERROR:' not in log,'real hardware renderer')
        report=data(folder+'readability-report.json')
        require(report['thresholds']=={'player':.6,'edge':1.0,'enemy':.45},'unchanged original thresholds')
        for row in report['results']:
            require(row['sampling_valid'] and row['passed'],'valid original sample')
            for field,threshold in [('player_contrast',.6),('edge_contrast',1.0),('enemy_contrast',.45)]:
                value=row[field]
                require(value is None or math.isfinite(value) and value>=threshold,'original contrast gate')
            png=read(folder+row['screenshot']);require(png[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',png[16:24])==(640,360),'actual PNG dimensions');images+=1
require(images==304,'76 points, two qualities, two resolutions')
perf=data('abba-root-final-v6/results.json')
require(perf['source_held'] and perf['numeric_105_percent_gate'] and perf['machine_exclusive'],'final ABBA source and Godot-presence audit')
require(data('abba-root-final-v6/source-before.json')==data('abba-root-final-v6/source-after.json'),'perf sources held')
require([r['epoch'] for r in perf['records']]==['legacy','current','current','legacy'],'ABBA order')
for run in perf['records']:
    require(run['exit']==run['script_errors']==0 and not run['workload_before'] and not run['workload_after'],'natural native exit, no other Godot presence')
    for actor in run['actor_contracts']:
        require(actor['no_characters'] and actor['active_npcs']==actor['active_rigs']==actor['enemies']==0 and not actor['player_can_process'],'actual actor exclusion')
for row in perf['ratios'].values():
    actual=statistics.mean(row['current_means'])/statistics.mean(row['legacy_means'])
    require(abs(actual-row['ratio'])<1e-12 and actual<=1.05,'105 percent gate')
payload=data('replaced-comparison-v2/independent-payload-recount.json')
totals=[]
for epoch in payload['epochs']:
    total=0
    for texture in epoch['textures']:
        w,h=texture['width'],texture['height'];channels={4:3,5:4}[texture['format']];size=0
        while True:
            size+=w*h*channels
            if not texture['mipmaps'] or w==h==1:break
            w=max(1,w//2);h=max(1,h//2)
        require(size==texture['reported_bytes']==texture['independent_bytes'],'actual complete mip chain')
        total+=size
    totals.append(total)
require(totals==[322205351,120619372] and totals[1]/totals[0]<.5,'actual loaded payload below half')
controls=data('probe-controls-npc-contract-final/results.json')
require(controls['before']==controls['after'] and [r['exit'] for r in controls['cases']]==[2,1,2] and all(r['script_errors']==0 and r['specific_error_present'] for r in controls['cases']),'position, PNG save and migration error controls')
npc=data('npc-contract-control/cases/results.json')
require(npc['source_held'] and [r['exit'] for r in npc['cases']]==[0,0,2],'actor exclusion, retained normal mode, ALWAYS-child rejection')
prompt=data('prompt-npc-controls-v2/runs.json')
require([r['exit'] for r in prompt]==[1,0] and all(r['script_errors']==0 and r['source_held'] for r in prompt),'overlap negative control')
for sample in prompt[1]['samples']:
    require(sample['visible_people']==sample['active_people']==sample['visible']==sample['enabled']==sample['processing']==sample['showing']==0,'no UI or NPC contamination')
require(data('legacy-pair-framing-v2/source-before.json')==data('legacy-pair-framing-v2/source-after.json'),'full-pair source guard')
for run in data('legacy-pair-framing-v2/runs.json'):
    require(run['exit']==run['script_errors']==0 and run['source_held'],'supplement natural exit')
    check=run['pair_checks'][0];head=check['head'];require(check['actors_held'] and check['both_conservative_body_rects_fully_visible'] and head['source_held'],'unobstructed full pair')
    folder='legacy-pair-framing-v2/'+run['quality']+'/'
    world=read(folder+head['files']['world_raw']);mask=read(folder+head['files']['mask_raw'])
    require(head['world_format']==14 and head['mask_format']==15 and len(world)==head['width']*head['height']*6 and len(mask)==head['width']*head['height']*8,'actual HDR and alpha formats')
    x,y,w,h=head['sample_rect'];H=W=Ws=0
    for py in range(y,y+h):
        for px in range(x,x+w):
            i=py*head['width']+px
            rgb=struct.unpack_from('<eee',world,i*6);alpha=struct.unpack_from('<e',mask,i*8+6)[0]
            white=all(v>.92 for v in rgb);H+=alpha>=.999;W+=white;Ws+=white and alpha>0
    require(H==head['opaque_head_pixels'] and W==head['white_rectangle_pixels'] and H>0 and Ws==0,'same-frame complete head-support upper bound')
require(any(row['blank'] and row['H']==0 and row['bound'] is None for row in data('legacy-lighting-diagnostic-v3/independent-head-recount.json')['cases']),'blank GPU mask rejected')
require(b'new failures: 1' in read('root-affected-final/raw.log'),'first missing-ambience failure retained')
require(all(r['exit']==0 for r in data('root-python-final/runs.json')),'original Python tests and full policy check')
print(json.dumps({'members':len(members),'final_native_images':images,'original_affected_checks':64722,'loaded_payload_bytes':totals,'final_ABBA_ratios':{k:v['ratio'] for k,v in perf['ratios'].items()},'failures':0},indent=2))

