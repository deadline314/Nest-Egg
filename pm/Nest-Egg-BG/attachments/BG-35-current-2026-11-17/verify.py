from pathlib import Path
import hashlib,json,math,struct,sys,zipfile
b=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).parent
m=json.loads((b/'manifest.json').read_text());p=b/m['archive'];h=hashlib.sha256()
with p.open('rb') as f:
    for chunk in iter(lambda:f.read(1024*1024),b''):h.update(chunk)
assert p.stat().st_size==m['bytes'] and h.hexdigest()==m['sha256']
with zipfile.ZipFile(p) as z:
    assert len(z.namelist())==len(set(z.namelist())) and set(z.namelist())==set(m['members'])
    for name,record in m['members'].items():
        data=z.read(name);assert len(data)==record['bytes'] and hashlib.sha256(data).hexdigest()==record['sha256'],name
    def raw(name):return z.read(name)
    def read(name):return json.loads(raw(name))
    def png(name,size):
        header=raw(name)[:24];assert header[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',header[16:24])==size,name
    source=read('native-quality-final/source-before.json')
    assert len(source)==10087 and source==read('native-quality-final/source-after.json')
    runs=read('native-quality-final/runs.json');assert len(runs)==4
    identities=[];frame_count=lamp_count=0
    for run in runs:
        assert run['exit']==run['script_errors']==0 and not run['engine_error'] and run['source_held'] and run['images']==8
        assert run['observations'] and all(o['actual_quality']==(0 if run['quality']=='low' else 2) and o['normal_maps']==(run['quality']=='high') and o['environments']==1 and o['glow'] and o['hdr'] and o['visible_prompts']==0 and o['lighting_target_x']==o['lamp_x'] and o['original_player_x']==72 for o in run['observations'])
        if run['name']=='high-reduced':assert all(o['precreated_environment_preserved'] for o in run['observations'])
        prefix='native-quality-final/'+run['name'];report=read(prefix+'/flicker-index.json')
        assert report['capture_failures']==0 and report['limit']==3 and report['seconds']==10 and report['reduce_flashes']==(run['mode']=='reduced')
        identity={}
        for level,group in report['levels'].items():
            assert group['over_limit']==0 and group['observed_seconds']>=10 and group['buzz_far_gain']<=.02 and not group['buzz_far_sounding']
            if level in ['ch1_warehouse','ch1_vault']:
                assert sum(n for state,n in group['states'].items() if state!='stable')>len(group['lamps'])/2 and group['buzz_peak']>0 and group['buzz_far_distance']>=210
            else:assert set(group['states'])=={'stable'} and group['buzz_peak']==0
            for lamp in group['lamps']:
                events=lamp['events'];assert events==sorted(events) and len(events)==lamp['changes_total'] and all(0<=t<=group['observed_seconds'] for t in events)
                worst=max((sum(0<=u-t<=1 for u in events) for t in events),default=0)
                assert worst==lamp['worst_second'] and worst<=(1 if run['mode']=='reduced' else 3)
                if run['mode']=='reduced' and lamp['state']!='stable':
                    low,high=(.72,1) if lamp['state']=='loose' else (.1,.42)
                    assert low<=lamp['lowest']<=lamp['highest']<=high
                key=level+str(lamp['tile']);identity[key]=[lamp['state'],lamp['fixture'],lamp['pattern'],lamp['pattern_offset'],lamp['calm_phase']];lamp_count+=1
        identities.append(identity)
        assert len(report['captures'])==4
        for capture in report['captures']:
            png(prefix+'/'+capture['file'],(2000,750));png(prefix+'/'+capture['context'],(1280,720))
            assert capture['lamp']==capture['focus'] and capture['size']==[1280,720]
            x,y,w,h=capture['crop'];assert w==200 and h==250 and x>=0 and y>=0 and x+w<=1280 and y+h<=720
            samples=capture['samples'];times=[s['time'] for s in samples];clocks=[s['clock'] for s in samples]
            assert len(samples)==30 and all(0<b-a<=.2 for a,b in zip(times,times[1:])) and times[-1]<=3.25 and all(a<b for a,b in zip(clocks,clocks[1:]))
            values=[s['shown'] for s in samples];assert capture['context_frame']==values.index(max(values))
            for sample in samples:
                # Lamp._show_level intentionally caches values using is_equal_approx.
                assert math.isclose(sample['shown'],sample['fixture_level'],rel_tol=1e-5,abs_tol=1e-5) and math.isclose(sample['shown'],sample['shaft'],abs_tol=1e-6)
                assert sample['glow_visible']==(sample['shown']>.01)
                if abs(sample['shown']-.2)>1e-5:assert sample['wants_shadow']==(sample['shown']>=.2)
                if not sample['wants_shadow']:assert not sample['shadow_enabled']
            frame_count+=len(samples)
    assert all(identity==identities[0] for identity in identities) and lamp_count==116 and frame_count==480
    negatives=[r for r in read('native-final/runs.json') if r['name'] in ['sheet-write-failure','context-write-failure','framing-control']]
    assert len(negatives)==3
    for r in negatives:
        assert r['exit']==1 and r['script_errors']==0 and r['engine_error'] and r['source_held'] and r['images']==(0 if r['name']=='framing-control' else 2)
        assert read('native-final/'+r['name']+'/flicker-index.json')['capture_failures']==2
    assert read('native-final/source-before.json')==read('native-final/source-after.json')==source
    assert read('before/result.json')['write_false_success_reproduced'] and read('before/result.json')['missing_environment_reproduced']
    before=read('before/runs.json');assert before[1]['exit']==0 and before[1]['images']==0 and before[1]['engine_error']
    assert all(o['environments']==0 and o['visible_prompts']==27 and o['lighting_target_x']!=o['lamp'][0] for r in before for o in r['observations'])
    assert read('checks-final/result.json')['all_passed'] and all(r['exit']==r['script_errors']==0 and not r['engine_error'] and r['source_held'] for r in read('checks-final/runs.json'))
    checked=read('checks-final/source-before.json');assert checked==read('checks-final/source-after.json') and all(source[p]==value for p,value in checked.items())
    assert b'BG35_SELFCHECK checks=8 failures=0' in raw('checks-final/selfcheck/raw.log') and b'lamp flicker patterns OK' in raw('checks-final/patterns/raw.log')
    previous=read('reused-bg33/source-before.json');assert previous==read('reused-bg33/source-after.json')
    differences=[p for p in previous if previous[p]!=source[p]];assert sorted(differences)==['tools/lamp_flicker_probe.gd','tools/readability_check.gd']
    sampler=raw('sources/tools/readability_check.gd');original=raw('reused-bg33/readability-before.gd')
    assert sampler.replace(b'\tawait AudioRelease.settle(get_tree())\n',b'')==original and hashlib.sha256(original).hexdigest()==previous['tools/readability_check.gd']
    assert b'lamp_flicker_probe' not in sampler
    for mode in ['normal','dim']:
        for q in ['low','high']:
            prefix='reused-bg33/'+mode+'-'+q;report=read(prefix+'/readability-report.json')
            assert len(report['results'])==18 and report['thresholds']=={'player':.6,'edge':1,'enemy':.45}
            for r in report['results']:
                assert r['passed'] and r['sampling_valid'] and r['player_contrast']>=.6 and r['edge_contrast']>=1 and (r['enemy_contrast'] is None or r['enemy_contrast']>=.45)
                png(prefix+'/'+r['screenshot'],(640,360))
    license=read('audio-registration.json');assert license['pack']['license']=='CC0-1.0' and license['pack']['author']=='orsi'
    assert hashlib.sha256(raw('audio/lamp_buzz_01.ogg')).hexdigest()==source['audio/sfx/lamp_buzz_01.ogg']
    old=raw('sources/before/lamp_flicker_probe.gd').replace(b'\r\n',b'\n');new=raw('sources/tools/lamp_flicker_probe.gd').replace(b'\r\n',b'\n')
    assert old.split(b'func _track(',1)[1].split(b'func _rewind_before_change',1)[0]==new.split(b'func _track(',1)[1].split(b'func _rewind_before_change',1)[0]
    for path in ['tools/lamp_flicker_probe.gd','tools/readability_check.gd']:
        assert hashlib.sha256(raw('sources/'+path)).hexdigest()==source[path]
    reviewed=read('review/reviewed.json');assert len(reviewed['pages'])==4 and len(reviewed['contexts'])==16
    for r in reviewed['pages']:assert hashlib.sha256(raw('review/'+r['page'])).hexdigest()==r['sha256']
print('BG35_PACKET_PASS',len(m['members']),'members; actual LOW/HIGH, 480 burst frames, 116 lamp traces, 72 reused readability, 8 headless checks, 3 native negative controls')
