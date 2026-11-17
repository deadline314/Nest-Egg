from pathlib import Path
from PIL import Image
from io import BytesIO
import hashlib,json,math,re,sys,zipfile

def verify(folder):
    manifest=json.loads((folder/'manifest.json').read_text(encoding='utf-8'))
    archive_path=folder/'evidence.zip'
    assert hashlib.sha256(archive_path.read_bytes()).hexdigest()==manifest['archive_sha256']
    with zipfile.ZipFile(archive_path) as archive:
        assert len(archive.namelist())==len(set(archive.namelist())) and set(archive.namelist())==set(manifest['files'])
        def read(name):return archive.read(name)
        def data(name):return json.loads(read(name))
        def photo(name):
            image=Image.open(BytesIO(read(name)));assert image.size==(640,360),name
        for name,expected in manifest['files'].items():assert hashlib.sha256(read(name)).hexdigest()==expected,name
        source=data('native/source-before.json');assert len(source)==10088 and source==data('native/source-after.json')
        old_source=data('environment-before-v2/source-before.json')
        assert old_source==data('environment-before-v2/source-after.json')
        assert {p for p in source if source[p]!=old_source[p]}=={'tools/scene_tour.gd','tools/bg55_enemy_readability_probe.gd'}
        for phase in ['checks','extras']:assert data(phase+'/source-before.json')==data(phase+'/source-after.json')==source
        assert data('native/private-before.json')==data('native/private-after.json')
        old=read('source/scene_tour-before.gd').replace(b'\r\n',b'\n')
        current=read('source/scene_tour.gd').replace(b'\r\n',b'\n')
        assert current==old.replace(b'func _run() -> void:\n',b'func _run() -> void:\n\tif get_viewport().find_world_3d().environment == null:\n\t\tadd_child(LightKit.create_environment())\n',1)
        assert hashlib.sha256(read('source/scene_tour.gd')).hexdigest()==source['tools/scene_tour.gd']
        assert hashlib.sha256(read('source/scene_tour-before.gd')).hexdigest()==old_source['tools/scene_tour.gd']
        assert hashlib.sha256(read('source/bg55-before.gd')).hexdigest()==old_source['tools/bg55_enemy_readability_probe.gd']
        assert hashlib.sha256(read('source/bg55-current.gd')).hexdigest()==source['tools/bg55_enemy_readability_probe.gd']
        old_bg55=read('source/bg55-before.gd').replace(b'\r\n',b'\n')
        bg55=read('source/bg55-current.gd').replace(b'\r\n',b'\n')
        assert [l for l in old_bg55.splitlines() if not l.strip().startswith(b'#')]==[l for l in bg55.splitlines() if not l.strip().startswith(b'#')]
        assert read('replay/before-tour.gd').replace(b'\r\n',b'\n')==current.replace(b'var path := "res://data/levels/%s.tres" % level_id',b'var path := "res://work/bg38-current/before-level.tres"',1)
        assert read('replay/before-phase.gd').replace(b'\r\n',b'\n')==read('source/readability_phase_probe.gd').replace(b'\r\n',b'\n').replace(b'extends "res://tools/scene_tour.gd"',b'extends "res://work/bg38-current/before-tour.gd"',1)
        old_map=data('original-map.json');current_map=data('source/current-map.json');baseline=data('replay/before-map.json')
        expected=dict(current_map);expected['props']=old_map['props'];assert baseline==expected
        assert len(old_map['props'])==6 and len(current_map['props'])==8 and all(p['id'].startswith('ali_kitchen__') for p in current_map['props'])
        for name,path in [('current-map.json','data/levels/ch2_ali_home_map.json'),('current-theme.tres','data/environment/themes/ch2_ali_home.tres'),('current-level.tres','data/levels/ch2_ali_home.tres')]:
            assert hashlib.sha256(read('source/'+name)).hexdigest()==source[path]
        expected_level=read('source/current-level.tres').decode().replace('\r\n','\n').replace('res://data/environment/themes/ch2_ali_home.tres','res://work/bg38-current/before-theme.tres').replace('res://data/levels/ch2_ali_home_map.json','res://work/bg38-current/before-map.json')
        assert read('replay/before-level.tres').decode().replace('\r\n','\n')==expected_level
        assert set(''.join(current_map['segments'][0]))<=set('#.PⅨ⇥Ⓐ*')
        theme=read('source/current-theme.tres').decode().replace('\r\n','\n')
        dirs=next(l for l in read('original-theme.tres').decode().splitlines() if l.startswith('extra_prop_dirs = '))
        assert read('replay/before-theme.tres').decode().replace('\r\n','\n')==re.sub(r'^extra_prop_dirs = .*$',lambda _:dirs,theme,flags=re.M)
        proof=data('baseline-proof.json');assert proof['same_nonprop_map_data'] and not proof['historical_nonprop_matches_current']
        assert hashlib.sha256(read('original-map.json')).hexdigest()==proof['original_map_sha256']
        cfg=data('pipeline-extract.json');assert len(cfg['props'])==8 and {e['seed'] for e in cfg['props']}==set(range(7101,7109))
        assert len(cfg['background'])==1 and cfg['background'][0]['seed']==7190
        for entry in cfg['props']:
            ident=entry['id'];tres=read('assets/'+ident+'.tres').decode()
            match=re.search(r'^size = Vector2\(([^,]+),\s*([^)]+)\)',tres,re.M);assert match
            assert abs(float(match[2])-entry['height_m']*30)<1e-6 and entry['prompt']
            color=Image.open(BytesIO(read('assets/'+ident+'.png'))).convert('RGBA');normal=Image.open(BytesIO(read('assets/'+ident+'_n.png')))
            assert color.size==normal.size and color.getextrema()[3][0]==0
        before_env=data('environment-before-v2/result.json');assert before_env['exit']==0 and before_env['source_held']
        assert before_env['observations'][0]['count']==0 and not before_env['observations'][0]['environment'] and before_env['observations'][0]['hdr']
        runs=data('native/runs.json');assert len(runs)==8
        for run in runs:
            assert run['exit']==run['script_errors']==0 and not run['engine_error'] and run['source_held'] and run['private_held']
            assert len(run['observations'])==9 and run['shots']==9
            for o in run['observations']:
                assert o['count']==1 and o['environment'] and o['glow'] and o['hdr'] and o['size']==[640,360]
                assert o['quality']==(0 if '-low-' in run['name'] else 2)
        native_png=0;visible_pairs=0;samples=0;decreased=0;minima=[]
        for quality in ['low','high']:
            for mode in ['normal','flat']:
                a_prefix='native/before-'+quality+'-'+mode+'/bg38_before/'
                b_prefix='native/after-'+quality+'-'+mode+'/ch2_ali_home/'
                a=data(a_prefix+'tour-index.json');b=data(b_prefix+'tour-index.json')
                assert len(a['shots'])==len(b['shots'])==9 and a['capture_size']==b['capture_size']==[640,360]
                assert a['level_size']==b['level_size'] and a['columns']==b['columns']==3 and a['rows']==b['rows']==3
                for x,y in zip(a['shots'],b['shots']):
                    assert x['world']==y['world'] and x['column']==y['column'] and x['row']==y['row']
                    photo(a_prefix+x['file']);photo(b_prefix+y['file']);native_png+=2
                if mode!='normal':continue
                ar=[r for r in a['shots'] if 'player_contrast' in r];br=[r for r in b['shots'] if 'player_contrast' in r]
                assert len(ar)==len(br)==6
                for x,y in zip(ar,br):
                    assert x['player_world']==y['player_world'] and x['fog_clock']==y['fog_clock'] and y['passed'] and y['cycle_passed']
                    assert y['player_contrast']>=.6 and y['edge_contrast']>=1
                    assert len(x['cycle_samples_raw'])==len(y['cycle_samples_raw'])==16
                    for row in [x,y]:
                        assert abs(min(s['player'] for s in row['cycle_samples_raw'])-row['cycle_player_min'])<1e-10
                        assert abs(min(s['edge'] for s in row['cycle_samples_raw'])-row['cycle_edge_min'])<1e-10
                        assert all(math.isfinite(s[k]) for s in row['cycle_samples_raw'] for k in ['player','edge'])
                        samples+=16
                    decreased+=int(y['player_contrast']<x['player_contrast']);visible_pairs+=1
                row={'quality':quality}
                for key in ['player_contrast','edge_contrast','cycle_player_min','cycle_edge_min']:
                    left=min(r[key] for r in ar);right=min(r[key] for r in br);assert right>=left
                    row[key]=[left,right]
                minima.append(row)
        assert native_png==72 and visible_pairs==12 and samples==384 and decreased==8
        assert data('native/regional-review.json')['passed'] and data('native/regional-review.json')['original_driver_exit']==1
        extra=data('extras/runs.json');assert len(extra)==2
        for run in extra:
            assert run['exit']==run['script_errors']==0 and not run['engine_error'] and run['source_held'] and len(run['png'])==1
            photo('extras/'+run['name']+'/'+run['png'][0])
        assert extra[0]['observations'][0]['count']==1 and extra[0]['observations'][0]['environment']
        assert 'props  8  OK' in read('extras/pack/raw.log').decode() and '== 8 props in 1 scene(s)' in read('extras/pack/raw.log').decode()
        assert data('checks/result.json')['all_passed']
        assert '沒有受影響的測試要跑' in read('checks/changed/raw.log').decode()
        report=read('checks/scene-report/raw.log').decode();assert '總計：0 錯誤、0 警告' in report
        maps=[line for line in report.splitlines() if line.startswith('== ') and '.tres（' in line]
        assert all('（0 錯誤、0 警告）' in line for line in maps)
        assert len([line for line in maps if line.startswith('== ch2_') or line.startswith('== ch3_')])==19
        assert 'Environment import policy: 0 noncompliant import/metadata files' in read('checks/assets/raw.log').decode()
        assert read('checks/assets/raw.log').decode().rstrip().endswith('OK')
    return {'members':len(manifest['files']),'tour_png':native_png,'pack_png':1,'visible_pairs':visible_pairs,'cycle_samples':samples,
        'regional_minima':minima,'individual_player_decreases':decreased,'scene_maps':len(maps),'chapter2_3_maps':19,'note':'Regional minimum is the original BG38 table contract; individual decreases remain visible. Numeric cycle statistics are recounted, not reconstructed from the earlier tour PNG.'}

if __name__=='__main__':
    print(json.dumps(verify(Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).resolve().parent),indent=2))
