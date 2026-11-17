from pathlib import Path
import hashlib,io,json,math,re,sys,zipfile
from PIL import Image

def verify(folder):
    manifest=json.loads((folder/'manifest.json').read_text(encoding='utf-8'))
    archive=folder/'evidence.zip'
    assert hashlib.sha256(archive.read_bytes()).hexdigest()==manifest['archive_sha256'],'Archive digest mismatch'
    with zipfile.ZipFile(archive) as z:
        assert set(z.namelist())==set(manifest['files']) and len(z.namelist())==len(set(z.namelist()))
        def raw(name):
            value=z.read(name);assert hashlib.sha256(value).hexdigest()==manifest['files'][name],name
            return value
        def data(name):return json.loads(raw(name))
        def photo(name):
            im=Image.open(io.BytesIO(raw(name)));im.load();assert im.size==(640,360),name
        for name in manifest['files']:raw(name)
        proof=data('baseline-proof.json');assert proof['before_props']==3 and proof['after_props']==11
        old=data('original-map.json');current=data('source/current-map.json')
        before=data('replay/before-map.json')
        assert before['props']==old['props'] and len(current['props'])==11
        assert {k:v for k,v in before.items() if k!='props'}=={k:v for k,v in current.items() if k!='props'}
        booth=next(p for p in current['props'] if p['id']=='gate_hall__guard_booth')
        bench=next(p for p in current['props'] if p['id']=='gate_hall__waiting_bench')
        assert booth['x']==57 and booth['ground'] and bench['x']==61
        assert b"a.prop('gate_hall__guard_booth', 57)" in raw('source/build_ch3.py')
        for prop in current['props']:assert prop.get('ground') or prop.get('support') in ['wall','ceiling']
        gate=next(p for p in current['props'] if p['id']=='gate_hall__scanner_gate');assert gate['x']==17
        rows=[row for segment in current['segments'] for row in segment]
        assert 'Ⓖ' in ''.join(rows) and 'Ю' in ''.join(rows) and 'ⓙ' in ''.join(rows)
        cfg=data('pipeline-extract.json');assert len(cfg['props'])==8
        assert {p['seed'] for p in cfg['props']}==set(range(7201,7209)) and cfg['background'][0]['seed']==7290
        for entry in cfg['props']:
            ident=entry['id'];resource=raw('assets/'+ident+'.tres').decode()
            match=re.search(r'^size = Vector2\(([^,]+),\s*([^)]+)\)',resource,re.M);assert match
            assert abs(float(match[2])-entry['height_m']*30)<.11
            image=Image.open(io.BytesIO(raw('assets/'+ident+'.png')));assert image.mode=='RGBA'
            assert image.getchannel('A').getextrema()[0]==0
            normal='assets/'+ident+'_n.png'
            if normal in manifest['files']:assert Image.open(io.BytesIO(raw(normal))).size==image.size
        guard=data('native-final/source-before.json');assert guard==data('native-final/source-after.json')
        prior=data('diagnostics/native/source-before.json')
        assert sorted(p for p in prior if prior[p]!=guard[p])==['data/levels/ch3_gate_hall_map.json','tools/level/build_ch3.py']
        for name,path in [('current-map.json','data/levels/ch3_gate_hall_map.json'),('current-level.tres','data/levels/ch3_gate_hall.tres'),('current-theme.tres','data/environment/themes/ch3_gate_hall.tres'),('build_ch3.py','tools/level/build_ch3.py'),('scene_tour.gd','tools/scene_tour.gd'),('readability_phase_probe.gd','tools/readability_phase_probe.gd'),('contrast_probe.gd','tools/contrast_probe.gd')]:
            assert hashlib.sha256(raw('source/'+name)).hexdigest()==guard[path]
        tour=raw('source/scene_tour.gd');phase=raw('source/readability_phase_probe.gd')
        assert raw('replay/before-tour.gd')==tour.replace(b'var path := "res://data/levels/%s.tres" % level_id',b'var path := "res://work/bg39-current/before-level.tres"')
        assert raw('replay/before-phase.gd')==phase.replace(b'extends "res://tools/scene_tour.gd"',b'extends "res://work/bg39-current/before-tour.gd"',1)
        assert guard==data('checks-final/source-before.json')==data('checks-final/source-after.json')
        runs=data('native-final/runs.json');assert len(runs)==8
        for run in runs:
            assert run['exit']==run['script_errors']==0 and not run['engine_error'] and run['source_held'] and run['private_held'] and run['shots']==12
            quality=0 if '-low-' in run['name'] else 2
            assert len(run['observations'])==12
            for observation in run['observations']:
                assert observation['environment'] and observation['glow'] and observation['count']==1 and observation['hdr'] and observation['quality']==quality and observation['size']==[640,360]
                assert len(observation['enemies'])==1 and observation['enemies'][0]['kind']=='JanusBoss'
        png=0;pairs=0;samples=0;decreases=0;minima=[]
        for mode in ['normal','flat']:
            for quality in ['low','high']:
                reports=[]
                for side,level in [('before','bg39_before'),('after','ch3_gate_hall')]:
                    prefix='native-final/'+side+'-'+quality+'-'+mode+'/'+level+'/'
                    report=data(prefix+'tour-index.json');assert report['columns']==4 and report['rows']==3 and len(report['shots'])==12
                    for shot in report['shots']:photo(prefix+shot['file']);png+=1
                    reports.append(report)
                if mode=='flat':continue
                a,b=reports
                for x,y in zip(a['shots'],b['shots']):
                    assert x['world']==y['world'] and x.get('player_world')==y.get('player_world')
                    if 'player_contrast' not in x:assert 'player_contrast' not in y;continue
                    assert x['fog_clock']==y['fog_clock'] and x['lamps']==y['lamps']
                    assert y['passed'] and y['cycle_passed'] and y['player_contrast']>=.6 and y['edge_contrast']>=1
                    for shot in [x,y]:
                        assert len(shot['cycle_samples_raw'])==16
                        for key in ['player','edge']:
                            values=[s[key] for s in shot['cycle_samples_raw']];assert all(math.isfinite(v) for v in values)
                            assert min(values)==shot['cycle_'+key+'_min']
                        samples+=16
                    pairs+=1;decreases+=int(y['player_contrast']<x['player_contrast'])
                row={'quality':quality}
                for key in ['player_contrast','edge_contrast','cycle_player_min','cycle_edge_min']:
                    left=min(s[key] for s in a['shots'] if key in s);right=min(s[key] for s in b['shots'] if key in s)
                    assert right>=left,(quality,key,left,right)
                    row[key]=[left,right]
                av=[v for s in a['shots'] for v in s.get('enemy_contrast',[])];bv=[v for s in b['shots'] for v in s.get('enemy_contrast',[])]
                assert len(av)==len(bv)==2 and min(bv)>=.45 and min(bv)>=min(av)
                row['enemy_contrast']=[min(av),min(bv)];minima.append(row)
        assert png==96 and pairs==14 and samples==448
        for phase in ['extras','aftercare']:
            assert data(phase+'/result.json')['passed']
            assert data(phase+'/source-before.json')==data(phase+'/source-after.json')==guard
        extras=data('extras/runs.json');assert len(extras)==2
        for run in extras:
            assert run['exit']==run['script_errors']==0 and not run['engine_error'] and run['source_held']
            for path in run['png']:photo('extras/'+run['name']+'/'+path)
        gate=next(r for r in extras if r['name']=='gate-context')['gate'][0]
        assert gate['present'] and gate['in_range'] and gate['prompt_visible'] and '掃夾層證' in gate['prompt']
        assert b'props  9  OK' in raw('extras/pack/raw.log')
        aftercare=data('aftercare/runs.json');assert len(aftercare)==2
        for run in aftercare:
            assert run['exit']==run['script_errors']==0 and not run['engine_error'] and run['source_held']
            for observation in run['observations']:
                keeper=next(n for n in observation['npcs'] if n['id']=='ch3_gatekeeper')
                assert keeper['present'] and keeper['pose']=='sit' and observation['enemies']==0
        checks=data('checks-final/runs.json');assert len(checks)==3 and all(r['exit']==r['script_errors']==0 and not r['engine_error'] and r['source_held'] for r in checks)
        assert data('checks-final/result.json')['all_passed']
        changed=raw('checks-final/changed/raw.log').decode()
        summary=re.search(r'checks: (\d+), new failures: (\d+), known failures \(tests/known_failures.txt\): (\d+)',changed)
        assert summary and summary[2]==summary[3]=='0'
        shard_checks=0;groups=0
        for name in manifest['files']:
            if re.fullmatch(r'checks-final/changed/shards/shard_\d+\.log',name):
                transcript=raw(name).decode();assert 'SCRIPT ERROR:' not in transcript
                totals=re.search(r'^checks: (\d+), failures: (\d+)',transcript,re.M);assert totals and totals[2]=='0'
                shard_checks+=int(totals[1]);groups+=len(re.findall(r'^SUITE_TIME ',transcript,re.M))
        assert groups==53 and shard_checks==int(summary[1])
        report=raw('checks-final/scene-report/raw.log').decode();assert '總計：0 錯誤、0 警告' in report
        maps=[line for line in report.splitlines() if line.startswith('== ') and '.tres（' in line];assert len(maps)==32
        assert raw('checks-final/assets/raw.log').decode().rstrip().endswith('OK')
    return {'passed':True,'members':len(manifest['files']),'tour_png':png,'matched_visible_pairs':pairs,'raw_cycle_samples':samples,'regional_minima':minima,'individual_player_decreases':decreases,'scene_maps':32,'test_groups':groups,'checks':shard_checks,'scope':'Original regional minima contract; individual decreases disclosed. Stationary real Janus, not combat-AI performance. Numeric cycle reports recounted; the tour PNG precedes later samples.'}

if __name__=='__main__':print(json.dumps(verify(Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).resolve().parent),indent=2))
