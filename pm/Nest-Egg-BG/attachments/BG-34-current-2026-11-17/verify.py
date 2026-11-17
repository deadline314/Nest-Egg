from pathlib import Path
from io import BytesIO
import hashlib,json,math,statistics,sys,zipfile
from PIL import Image
b=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).parent
m=json.loads((b/'manifest.json').read_text());p=b/m['archive'];h=hashlib.sha256()
with p.open('rb') as f:
    for chunk in iter(lambda:f.read(1048576),b''):h.update(chunk)
assert p.stat().st_size==m['bytes'] and h.hexdigest()==m['sha256']
with zipfile.ZipFile(p) as z:
    assert len(z.namelist())==len(set(z.namelist())) and set(z.namelist())==set(m['members'])
    for name,r in m['members'].items():
        data=z.read(name);assert len(data)==r['bytes'] and hashlib.sha256(data).hexdigest()==r['sha256'],name
    def read(name):return json.loads(z.read(name))
    def photo(name,size=(1280,720)):
        im=Image.open(BytesIO(z.read(name))).convert('RGB');assert im.size==size,name
        return im
    def delta(on,off):
        a=on.load();c=off.load();dark=bright=count=0
        for y in range(0,on.height,3):
            for x in range(0,on.width,3):
                u=sum(v*w for v,w in zip(a[x,y],[.2126,.7152,.0722]))/255
                v=sum(v*w for v,w in zip(c[x,y],[.2126,.7152,.0722]))/255
                count+=1
                if max(u,v)<.004:continue
                dark+=u<v*.8;bright+=v<u*.8
        return (dark-bright)/count
    source=read('checks-restored/source-before.json');assert len(source)==10088 and source==read('checks-restored/source-after.json')
    for prefix in ['native-capped','causality-capped','performance-capped']:
        sample=read(prefix+'/source-before.json');assert sample==read(prefix+'/source-after.json') and all(source[k]==v for k,v in sample.items())
    assert read('checks-restored/result.json')['all_passed']
    assert all(r['exit']==r['script_errors']==0 and not r['engine_error'] and r['source_held'] for r in read('checks-restored/runs.json'))
    for path in ['tools/wall_shadow_probe.gd','game/level/environment/wall_shadows.gd','tests/suite/test_environment.gd']:
        assert hashlib.sha256(z.read('sources/'+path)).hexdigest()==source[path]
    runs=read('native-capped/runs.json');assert len(runs)==9
    fault=z.read('observers/bg34-native-capped/missing.gd')
    assert fault.replace(b'res://data/enemies/bg34-deliberately-missing.tres',b'res://data/enemies/sweeper.tres')==z.read('sources/tools/wall_shadow_probe.gd')
    pairs=0
    for r in runs:
        assert r['source_held'] and r['script_errors']==0
        prefix='native-capped/'+r['name'];d=read(prefix+'/walls-index.json')
        if r['expected_exit']==1:
            assert r['exit']==1 and r['engine_error'] and d['failures']>0
            assert r['images']==(1 if r['name']=='write-failure' else 3)
            continue
        assert r['exit']==0 and not r['engine_error'] and d['failures']==0
        q=['low','medium','high'].index(d['quality'])
        assert all(o['actual_quality']==q and o['environments']==1 and o['hdr'] and o['glow'] and o['visible_prompts']==0 and o['restored_time_scale']==1 for o in r['observations'])
        shots={**{'lamp-'+k:v for k,v in d.get('lamp',{}).get('shots',{}).items()},'gun':d['gun']}
        assert d['gun']['enemies']==3 and d['gun']['actors']['valid'] and len(d['gun']['actors']['records'])==3
        for actor in d['gun']['actors']['records']:assert actor['visible'] and actor['in_view'] and actor['on_floor']
        for tag,record in shots.items():
            on=photo(prefix+'/walls-'+tag+'-on.png');off=photo(prefix+'/walls-'+tag+'-off.png');aa=photo(prefix+'/walls-'+tag+'-aa.png')
            assert record['aa_identical'] and on.tobytes()==aa.tobytes()
            if d['level']=='ch1_street' and tag.startswith('lamp-'):
                assert on.crop((0,0,1280,60)).tobytes()==off.crop((0,0,1280,60)).tobytes()
            exact=delta(on,off);assert abs(exact-record['shadowed_share'])<.00006,(prefix,tag,exact,record)
            if q==0:assert record['lights']==0 and on.tobytes()==off.tobytes()
            else:assert 0<record['lights']<=(2 if q==1 else 4) and record['silhouette_share']>0 and record['shadowed_share']>=.001
            pairs+=1
    assert pairs==15
    cadence=read('cadence/cadence-index.json');assert cadence['failures']==0 and len(cadence['groups'])==4
    assert read('cadence/source-before.json')==source==read('cadence/source-after.json')
    for group in cadence['groups']:
        frames=group['frames'];assert len(frames)==180
        draws=[(row['wall_frame'],row['draw_usec']) for i,row in enumerate(frames) if i and row['draw_usec']!=frames[i-1]['draw_usec']]
        gaps=[v[0]-u[0] for u,v in zip(draws,draws[1:])]
        assert all(v[1]-u[1]>=8333 for u,v in zip(draws,draws[1:])) and all(g in [3,6] for g in gaps)
        fps=179e6/(frames[-1]['now_usec']-frames[0]['now_usec'])
        if group['cap'] in [60,144]:assert all(g==3 for g in gaps)
        if group['cap']==0:assert fps>360 and all(g==6 for g in gaps)
        photo('cadence/motion-'+str(group['cap'])+'.png')
    causal=read('causality-capped/causal-index.json');assert causal['failures']==0 and len(causal['records'])==15
    for r in causal['records']:
        prefix='causality-capped/'+r['tag'];on=photo(prefix+'-on.png');off=photo(prefix+'-off.png');aa=photo(prefix+'-aa.png')
        assert r['aa_identical'] and on.tobytes()==aa.tobytes()
        assert all(not p['casts'] for p in r['snapshot']['prompt_records'])
        if r['lights']==0:assert r['on_off_identical'] and on.tobytes()==off.tobytes()
        else:assert r['lights'] in [1,2] and delta(on,off)>0
    performance=read('performance-capped/runs.json');assert len(performance)==3
    ratios=[]
    for r in performance:
        assert r['exit']==r['script_errors']==0 and not r['engine_error'] and r['source_held'] and not r['processes_before'] and not r['processes_after'] and r['frames']==5400 and r['actor_valid']
        d=read('performance-capped/high-'+str(r['trial'])+'/walls-index.json');perf=d['perf'];assert d['failures']==0 and perf['enemies']==12
        assert all(len(perf[key]['records'])==12 and perf[key]['valid'] for key in ['actors_before','actors_after'])
        groups=perf['groups'];assert len(groups)==120
        pairs={}
        for i,g in enumerate(groups):
            assert g['round']==i//2 and g['enabled']==(i%2==0 if (i//2)%2==0 else i%2==1)
            assert len(g['frames_ms'])==45 and all(math.isfinite(x) and x>0 for x in g['frames_ms'])
            pairs.setdefault(g['round'],{})[g['enabled']]=statistics.median(g['frames_ms'])
        exact=statistics.median(v[True]/v[False] for v in pairs.values())
        assert abs(exact-perf['ratio_exact'])<1e-10 and exact<=1.08
        ratios.append(exact)
        photo('performance-capped/high-'+str(r['trial'])+'/walls-perf-context.png')
        if r['trial']==1:
            re=d['reenter'];nodes=re['nodes'];mem=re['texture_mib'];assert len(nodes)==len(mem)==10 and not re['accumulates'] and nodes[-1]<=nodes[1] and max(mem[-3:])<=max(mem[:3])*1.02+.5
    rb=read('readability-capped/source-before.json');assert rb==read('readability-capped/source-after.json') and all(source[k]==v for k,v in rb.items())
    runs=read('readability-capped/runs.json');assert len(runs)==4
    for r in runs:
        assert r['exit']==r['script_errors']==0 and not r['engine_error'] and r['source_held'] and r['spots']==r['images']==18
        prefix='readability-capped/'+r['condition']+'-'+r['quality'];report=read(prefix+'/readability-report.json')
        assert report['thresholds']=={'player':.6,'edge':1,'enemy':.45} and len(report['results'])==18
        assert report['light_quality']==(0 if r['quality']=='low' else 2)
        for spot in report['results']:
            assert spot['passed'] and spot['player_contrast']>=.6 and spot['edge_contrast']>=1
            assert spot['enemy_contrast'] is None or spot['enemy_contrast']>=.45
        for n in z.namelist():
            if n.startswith(prefix+'/') and n.endswith('.png'):photo(n,(640,360))
    old=read('before/runs.json');bad=next(r for r in old if r['name']=='write-failure');assert bad['exit']==0 and bad['engine_error'] and bad['main_images']==0
    assert read('before-street/runs.json')[0]['observations'][0]['aa_identical']==False
    assert b'"prompt_casts":true' in z.read('prompt-red.log') and b'"leader_casts":true' in z.read('prompt-red.log')
print(json.dumps({'members':len(m['members']),'native_pairs':15,'causal_pairs':15,'readability':72,'timed_frames':16200,'ratios':ratios,'verified':True}))
