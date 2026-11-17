"""Offline BG-33 evidence checks; Python standard library only."""
from pathlib import Path
import hashlib,json,math,struct,sys,zipfile

base=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).parent
manifest=json.loads((base/'manifest.json').read_text(encoding='utf8'))
def sha(path):
    h=hashlib.sha256()
    with path.open('rb') as f:
        for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
    return h.hexdigest()
archives={}
for row in manifest['archives']:
    path=base/row['file'];assert path.stat().st_size==row['bytes'] and sha(path)==row['sha256'],path
    z=zipfile.ZipFile(path)
    assert len(z.namelist())==len(set(z.namelist()))
    for name in z.namelist():assert name not in archives;archives[name]=z
assert set(archives)==set(manifest['members'])
for name,row in manifest['members'].items():
    h=hashlib.sha256();size=0
    with archives[name].open(name) as stream:
        for data in iter(lambda:stream.read(1024*1024),b''):h.update(data);size+=len(data)
    assert size==row['bytes'] and h.hexdigest()==row['sha256'],name
def raw(name):return archives[name].read(name)
def read(name):return json.loads(raw(name))
def png(name,size):
    header=raw(name)[:24]
    assert header[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',header[16:24])==size,name

final=read('native-final-v3/source-before.json')
assert len(final)==10085 and final==read('native-final-v3/source-after.json')
runs=read('native-final-v3/runs.json')
assert [r['name'] for r in runs]==['low','medium','high','maximum-brightness','write-failure']
for r in runs:
    assert r['script_errors']==0 and r['source_held'] and r['exit']==(1 if r['name']=='write-failure' else 0)
    assert r['observations'] and all(o['environments']==1 and o['glow'] and o['hdr'] and o['visible_prompts']==0 and o['image_size']==[1280,720] for o in r['observations'])
    assert r['images']==(33 if r['name'] in ['low','medium','high'] else 2 if r['name']=='maximum-brightness' else 0)
eligible=0;minimum={}
for q in ['low','medium','high']:
    report=read('native-final-v3/'+q+'/pools-index.json')
    assert report['capture_failures']==report['invalid_focus_samples']==0 and len(report['levels'])==8
    ratios=[]
    for level,group in report['levels'].items():
        assert group['flags_unchanged']
        for row in group['records']:
            png('native-final-v3/'+q+'/'+row['file'],(1280,720))
            assert row['sampling_valid'] and row['focus']['lamp_x']==row['focus']['target_x'] and row['focus']['lamp_zone']==row['focus']['target_zone']
            if level in ['ch1_pawnshop','ch1_lounge']:continue
            if row.get('note'):
                assert level=='ch1_street' and row['tile'][0]==150 and row['ratio']==0
                continue
            assert math.isclose(row['ratio'],row['pool']/max(row['far'],0.004),rel_tol=1e-12)
            assert row['ratio']>=2,(q,level,row)
            ratios.append(row['ratio']);eligible+=1
    assert len(ratios)==20;minimum[q]=min(ratios)
assert eligible==60
for level in ['ch1_warehouse','ch1_vault']:png('native-final-v3/maximum-brightness/pools-'+level+'-lamp00.png',(1280,720))
assert all(o['brightness']==1 for o in runs[3]['observations'])
assert read('native-final-v3/write-failure/pools-index.json')['capture_failures']==1 and runs[4]['engine_error']
old=read('before/runs.json');assert old[0]['observations'][0]['environments']==0 and old[0]['observations'][0]['visible_prompts']>0
assert old[1]['exit']==0 and old[1]['images']==0 and old[1]['engine_error']
assert read('diagnostics/result.json')['inherited_original_environment_preserved']
inherited=[json.loads(line.split(b'BG33_INHERITED ',1)[1]) for line in raw('diagnostics/inherited/raw.log').splitlines() if line.startswith(b'BG33_INHERITED ')]
assert inherited==[{'environments':1,'valid':True}]
gate=read('gate-calibration/calibration.json')
assert gate['valid'] and gate['lamp_alive'] and gate['supported'] and gate['records'][0]['point']==[1448,594] and gate['records'][1]['point']==[1400,594]
assert len(gate['records'][0]['hits'])==1 and gate['records'][0]['hits'][0]['parent_class']=='Gate' and gate['records'][1]['hits']==[]

count=0
for branch in ['readability-final','readability-regression']:
    assert read(branch+'/source-before.json')==read(branch+'/source-after.json')==final
assert all(r['exit']==r['script_errors']==0 and r['source_held'] for r in read('readability-final/runs.json'))
assert all(r['exit']==r['script_errors']==0 and r['source_held'] for r in read('readability-regression/runs-final.json'))
def readability(prefix,expected,mapping=None):
    global count
    report=read(prefix+'/readability-report.json')
    assert report['thresholds']=={'player':0.6,'edge':1.0,'enemy':0.45} and report['samples_per_spot']==16 and len(report['results'])==expected
    for i,row in enumerate(report['results']):
        assert row['sampling_valid'] and row['passed'] and row['player_contrast']>=.6 and row['edge_contrast']>=1
        assert (row['enemy_contrast'] is None and not row['enemy']) or row['enemy_contrast']>=.45
        filename=mapping[i] if mapping else prefix+'/'+row['screenshot']
        png(filename,(640,360));count+=1
for condition in ['normal','dim']:
    for q in ['low','high']:readability('readability-final/'+condition+'-'+q,18)
mapping=read('readability-regression/screenshot-map.json')
assert len(mapping)==116 and len({m['screenshot'] for m in mapping})==116
for scene,expected in [('readability_check',16),('ch2_readability_check',22),('ch3_readability_check',20)]:
    for q in ['low','high']:
        selected=[m for m in mapping if m['scene']==scene and m['quality']==q]
        assert [m['index'] for m in selected]==list(range(expected))
        paths=['readability-regression/'+m['screenshot'] for m in selected]
        for m,p in zip(selected,paths):assert hashlib.sha256(raw(p)).hexdigest()==m['sha256']
        readability('readability-regression/'+scene+'-'+q,expected,paths)
assert count==188
regression=read('readability-regression/result.json')
assert regression['supplemental_spots']==len(regression['supplements'])==4
for supplement in regression['supplements']:
    readability('readability-regression/'+supplement['folder'],1)

heads=0;worst=0
for branch,expected in [('head-exposure-final',9),('head-exposure-warehouse',3),('head-exposure-lounge',3)]:
    assert read(branch+'/source-before.json')==read(branch+'/source-after.json')==final
    for q in ['low','high','blank-mask']:
        prefix=branch+'/'+q;report=read(prefix+'/head-results.json')
        assert len(report['records'])==(1 if q=='blank-mask' else expected)
        for row in report['records']:
            assert row['world_format']==14 and row['mask_format']==15 and row['width']==1280 and row['height']==720 and row['source_held'] and row['expanded_geometry_fully_in_bounds']
            world=raw(prefix+'/'+row['files']['world_raw']);mask=raw(prefix+'/'+row['files']['mask_raw'])
            assert len(world)==1280*720*6 and len(mask)==1280*720*8
            x,y,w,h=row['sample_rect'];assert x>=0 and y>=0 and x+w<=1280 and y+h<=720
            opaque=white=0;peak=0
            for py in range(y,y+h):
                for px in range(x,x+w):
                    offset=py*1280+px
                    alpha=struct.unpack_from('<4e',mask,offset*8)[3]
                    rgb=struct.unpack_from('<3e',world,offset*6)
                    opaque+=alpha>=.999;white+=all(v>.92 for v in rgb);peak=max(peak,*rgb)
            assert opaque==row['opaque_head_pixels'] and white==row['white_rectangle_pixels'] and peak==row['peak']
            for key in ['world_png','mask_png']:png(prefix+'/'+row['files'][key],(1280,720))
            if q=='blank-mask':
                assert opaque==0 and not row['bound_valid'] and row['white_ratio_upper_bound'] is None
            else:
                assert opaque>0 and row['bound_valid'] and white/opaque<=.02 and math.isclose(white/opaque,row['white_ratio_upper_bound'],rel_tol=1e-12)
                heads+=1;worst=max(worst,white/opaque)
    runs=read(branch+'/runs.json')
    assert [r['exit'] for r in runs]==[0,0,1] and all(r['source_held'] and r['script_errors']==0 for r in runs)
assert heads==30

prior=read('affected-final/source-after.json')
assert prior==read('affected-final/source-before.json')==read('delta-baseline/capture-source-before.json')==read('delta-baseline/capture-source-after.json')
assert read('affected-final/result.json')['all_passed']
assert b'checks: 58374, new failures: 0' in raw('affected-final/changed/raw.log')
assert [p for p in prior if prior[p]!=final[p]]==['data/environment/lamp_fixtures.json']
old_fixtures=read('delta-baseline/passed-sources/data/environment/lamp_fixtures.json')
new_fixtures=read('sources/current/data/environment/lamp_fixtures.json')
assert old_fixtures['fixtures']['bulkhead_wall']['energy']==.85 and new_fixtures['fixtures']['bulkhead_wall']['energy']==1
old_fixtures['fixtures']['bulkhead_wall']['energy']=1
assert old_fixtures==new_fixtures
assert read('delta-checks/source-before.json')==read('delta-checks/source-after.json')==final
assert read('delta-checks/result.json')['exit']==0 and read('delta-checks/result.json')['changed_runtime_paths']==['data/environment/lamp_fixtures.json']
assert b'checks: 9799, new failures: 0' in raw('delta-checks/raw.log')
latest=read('exit-cleanup/source-before.json')
assert latest==read('exit-cleanup/source-after.json')==read('cleanup-checks/source-before.json')==read('cleanup-checks/source-after.json')
assert [p for p in final if final[p]!=latest[p]]==['tools/readability_check.gd']
assert read('cleanup-checks/result.json')['exit']==0 and b'checks: 9799, new failures: 0' in raw('cleanup-checks/raw.log')
sampling_before=raw('exit-cleanup/readability-before.gd')
sampling_after=raw('sources/current/tools/readability_check.gd')
assert sampling_after==raw('exit-cleanup/readability-after.gd')
assert sampling_after.replace(b'\tawait AudioRelease.settle(get_tree())\n',b'')==sampling_before
assert hashlib.sha256(sampling_before).hexdigest()==final['tools/readability_check.gd']
assert hashlib.sha256(sampling_after).hexdigest()==latest['tools/readability_check.gd']
clean_runs=read('exit-cleanup/runs.json');assert len(clean_runs)==6
for r in clean_runs:
    assert r['exit']==r['script_errors']==0 and not r['engine_error'] and not r['resource_leak']
    prefix='exit-cleanup/'+r['scene']+'-'+r['quality']
    assert b'ERROR:' not in raw(prefix+'/raw.log') and b'leaked at exit' not in raw(prefix+'/raw.log')
    readability(prefix,1)
assert read('exit-cleanup/result.json')['clean_native_exits']==6
old_tool=raw('sources/before/tools/light_pool_probe.gd').replace(b'\r\n',b'\n')
new_tool=raw('sources/current/tools/light_pool_probe.gd').replace(b'\r\n',b'\n')
assert old_tool.split(b'func _measure_lamp(',1)[1]==new_tool.split(b'func _measure_lamp(',1)[1]
for line in old_tool.splitlines():
    if line.startswith(b'const '):assert line in new_tool.splitlines()
for p in ['tools/light_pool_probe.gd','tests/suite/test_environment.gd','data/environment/lamp_fixtures.json','data/levels/ch1_warehouse_map.json']:
    assert hashlib.sha256(raw('sources/current/'+p)).hexdigest()==final[p]
for branch,expected in [('review-main',32),('review-regression',11)]:
    reviewed=read(branch+'/reviewed.json')
    assert len(reviewed['pages'])==expected
    for page in reviewed['pages']:assert hashlib.sha256(raw(branch+'/'+page['page'])).hexdigest()==page['sha256']
print('BG33_PACKET_PASS',len(archives),'members; 60/60 pools',minimum,'; 188 mapped readability + 4 overwritten-elevation supplements; 30 raw HDR heads worst',worst,'; 58374 + 9799 checks')
