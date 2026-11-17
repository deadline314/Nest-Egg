from pathlib import Path
import hashlib,io,json,math,re,sys,zipfile
from PIL import Image

def verify(folder):
    manifest=json.loads((folder/'manifest.json').read_text(encoding='utf-8'));archives={}
    try:
        for name,digest in manifest['archives'].items():
            assert hashlib.sha256((folder/name).read_bytes()).hexdigest()==digest,'Archive digest mismatch'
            archives[name]=zipfile.ZipFile(folder/name)
        def raw(name):
            entry=manifest['files'][name];value=archives[entry['archive']].read(entry['member'])
            assert hashlib.sha256(value).hexdigest()==entry['sha256'],name
            return value
        def data(name):return json.loads(raw(name))
        def photo(name):
            im=Image.open(io.BytesIO(raw(name)));im.load();assert im.size==(640,360),name
        for name in manifest['files']:raw(name)
        for name,z in archives.items():
            expected={f['member'] for f in manifest['files'].values() if f['archive']==name}
            assert set(z.namelist())==expected and len(z.namelist())==len(expected)
        source=data('formal-v2/source-before.json')
        for phase in ['formal-v2','fixtures-v2','shared-seeded','states-v3','guard-wall','checks']:
            assert data(phase+'/source-before.json')==data(phase+'/source-after.json')==source
        for phase in ['formal-v2','shared-seeded','states-v3','guard-wall']:assert data(phase+'/result.json')['passed']
        assert data('checks/result.json')['all_passed']
        # The original fixture wrapper rejected its additional scenery nondrop gate; retain that failure.
        assert not data('fixtures-v2/result.json')['passed']
        cfg=data('pipeline-extract.json');assert len(cfg['props'])==6 and {p['seed'] for p in cfg['props']}==set(range(7301,7307))
        for p in cfg['props']:
            ident=p['id'];tres=raw('assets/'+ident+'.tres').decode();size=re.search(r'^size = Vector2\(([^,]+),\s*([^)]+)\)',tres,re.M)
            assert size and abs(float(size[2])-p['height_m']*30)<.11
            im=Image.open(io.BytesIO(raw('assets/'+ident+'.png')));assert im.mode=='RGBA' and im.getchannel('A').getextrema()[0]==0
        proof=data('baseline-proof.json');assert len(proof)==2
        for p in proof:
            ident=p['level'].removeprefix('ch2_');current=data('source/ch2_'+ident+'_map.json');before=data('replay/'+ident+'/before-map.json');old=data(ident+'-original-map.json')
            assert p['same_nonprops'] and p['current_generator_props_match'] and len(current['props'])==p['current_props'] and len(before['props'])==p['before_props']
            assert {k:v for k,v in before.items() if k!='props'}=={k:v for k,v in current.items() if k!='props'}
            assert [v['id'] for v in before['props']]==[v['id'] for v in old['props']]
            assert all(v['ground']==False and v['y']==35 and v['dy']==0 for v in before['props'])
            tour=raw('source/scene_tour.gd');needle=b'var path := "res://data/levels/%s.tres" % level_id'
            assert raw('replay/'+ident+'/formal-before-tour.gd')==tour.replace(needle,('var path := "res://work/bg41-current/'+ident+'/formal-before-level.tres"').encode())
        assert b'enemy_fill_scale = 0.6' in raw('market-before.tres') and b'enemy_fill_scale = 1.2' in raw('source/market.tres')
        runs=data('formal-v2/runs.json');assert len(runs)==16
        for run in runs:
            assert run['exit']==run['script_errors']==0 and not run['engine_error'] and run['source_held'] and run['private_held'] and run['shots']==32
            assert '--no-enemies' in run['command']
            for o in run['observations']:assert o['environment'] and o['glow'] and o['hdr'] and o['count']==1 and o['size']==[640,360] and o['quality']==(0 if '-low-' in run['name'] else 2)
        tour_png=0;points=0;decreases=0;minima=[]
        for ident in ['loading','market']:
            for quality in ['low','high']:
                for mode in ['normal','flat']:
                    reports=[]
                    for side in ['before','after']:
                        prefix=f'formal-v2/{ident}-{side}-{quality}-{mode}/'+('bg41_before_'+ident if side=='before' else 'ch2_'+ident)+'/'
                        report=data(prefix+'tour-index.json');assert report['columns']==8 and report['rows']==4 and len(report['shots'])==32
                        for shot in report['shots']:photo(prefix+shot['file']);tour_png+=1
                        reports.append(report)
                    a,b=reports
                    for x,y in zip(a['shots'],b['shots']):assert x['world']==y['world'] and x.get('player_world')==y.get('player_world')
                    if mode=='flat':continue
                    row={'level':'ch2_'+ident,'quality':quality}
                    for x,y in zip(a['shots'],b['shots']):
                        if 'player_contrast' not in x:continue
                        points+=1;decreases+=int(y['player_contrast']<x['player_contrast'])
                        assert y['passed'] and y['player_contrast']>=.6 and y['edge_contrast']>=1 and x['fog_clock']==y['fog_clock']
                    for key in ['player_contrast','edge_contrast']:
                        row[key]=[min(s[key] for s in r['shots'] if key in s) for r in reports]
                        assert all(math.isfinite(v) for v in row[key]) and row[key][1]>=row[key][0]
                    minima.append(row)
        assert tour_png==512
        fixture_png=0;sample_count=0;enemy_minima=[]
        for phase in ['fixtures-v2','shared-seeded']:
            runs=data(phase+'/runs.json');assert len(runs)==(4 if phase=='fixtures-v2' else 12)
            for run in runs:
                assert run['script_errors']==0 and not run['engine_error'] and run['source_held']
                side=run.get('side',run['name'].split('-')[0]);assert run['exit']==0 if side=='after' else run['exit'] in [0,1]
                folder=phase+'/'+run['name']+'/';report=data(folder+'readability-report.json');samples=data(folder+'frame-samples.json')
                assert report['thresholds']=={'player':.6,'edge':1.,'enemy':.45} and len(samples)==len(report['results'])*16
                sample_count+=len(samples)
                for s in report['results']:
                    assert s['sampling_valid']
                    records=[v for v in samples if v['level']==s['level'] and v['spot']==s['spot']]
                    assert [v['sample'] for v in records]==list(range(16))
                    for i,key in enumerate(['player_contrast','edge_contrast','enemy_contrast']):assert records[-1]['sums'][i]==0 if s[key] is None else abs(records[-1]['sums'][i]-s[key])<1e-8
                    if side=='after':assert s['passed'] and s['player_contrast']>=.6 and s['edge_contrast']>=1 and (s['enemy_contrast'] is None or s['enemy_contrast']>=.45)
                    photo(folder+'ST-6-'+s['level']+'-'+str(s['column'])+'.png');fixture_png+=1
                    if phase=='fixtures-v2' and s['enemy']:assert all(abs(v['enemy_fill_scale']-(.6 if side=='before' else 1.2))<1e-6 for v in records)
        for quality in ['low','high']:
            values=[]
            for side in ['before','after']:
                records=data('fixtures-v2/'+side+'-'+quality+'/readability-report.json')['results'];foes=[s for s in records if s['enemy']]
                assert len(foes)==5 and sorted(s['enemy_column'] for s in foes)==[30,41,62,71,78]
                values.append(min(s['enemy_contrast'] for s in foes))
            assert values[1]>=.45 and values[1]>=values[0];enemy_minima.append({'quality':quality,'enemy':values})
        assert fixture_png==92 and sample_count==1472
        state_png=0
        for quality in ['low','high']:
            report=data('states-v3/'+quality+'/states.json');rows={s['name']:s for s in report['rows']};assert len(rows)==7 and report['actual_lever_talk']
            assert report['routes']==['res://data/levels/ch2_market.tres','res://data/levels/ch2_loading.tres']
            for name,s in rows.items():photo('states-v3/'+quality+'/'+name+'.png');state_png+=1
            for name in ['rent-window','collection-book','drying-desk','bridge-lever']:assert rows[name]['in_range'] and rows[name]['prompt_visible']
            for name,opened in [('bridge-closed',False),('bridge-open',True),('bridge-reentry',True)]:
                s=rows[name];assert s['swapped']==s['portal_open']==s['flag']==opened and s['down_size'][1]==78 and abs(s['down_top'][1]+78-s['base_bottom'])<.01
                assert s['lamp']==('52d98cff' if opened else 'ff6a4aff')
            guard=data('guard-wall/'+quality+'/states.json');assert guard['wall_supported']
            for s in guard['rows']:photo('guard-wall/'+quality+'/'+s['name']+'.png');state_png+=1
        assert state_png==18
        log=raw('checks/changed/raw.log').decode();count=re.search(r'checks: (\d+), new failures: (\d+), known failures \(tests/known_failures.txt\): (\d+)',log)
        assert count and tuple(map(int,count.groups()))==(58083,0,0)
        assert '總計：0 錯誤、0 警告' in raw('checks/scene-report/raw.log').decode()
        return {'passed':True,'logical_files':len(manifest['files']),'native_png':tour_png+fixture_png+state_png,'tour_pairs':points,'individual_player_decreases':decreases,'fixture_raw_records':sample_count,'minima':minima,'real_enemy_minima':enemy_minima,'changed_checks':58083}
    finally:
        for z in archives.values():z.close()
if __name__=='__main__':print(json.dumps(verify(Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).parent),ensure_ascii=False,indent=2))
