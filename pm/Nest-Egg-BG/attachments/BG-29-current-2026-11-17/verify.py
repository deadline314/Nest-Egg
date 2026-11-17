from pathlib import Path
from PIL import Image,ImageChops
from io import BytesIO
import hashlib,json,math,statistics,sys,zipfile

def verify(folder):
    manifest=json.loads((folder/'manifest.json').read_text(encoding='utf-8'))
    files=manifest['files'];aliases=manifest['aliases'];locations={};archives=[]
    for part in manifest['archives']:
        path=folder/part['name']
        assert path.stat().st_size==part['bytes']
        assert hashlib.sha256(path.read_bytes()).hexdigest()==part['sha256'],path.name
        archive=zipfile.ZipFile(path);archives.append(archive)
        for name in archive.namelist():
            assert name not in locations,name
            locations[name]=archive
    assert set(locations)==set(files)-set(aliases)
    def read(name):
        target=aliases.get(name,name)
        assert target in locations and target not in aliases
        return locations[target].read(target)
    def data(name):return json.loads(read(name))
    def photo(name):
        image=Image.open(BytesIO(read(name))).convert('RGB')
        assert image.size==(1280,720),name
        return image
    for name,expected in files.items():assert hashlib.sha256(read(name)).hexdigest()==expected,name
    source=data('checks/source-after.json')
    assert len(source)==10088 and source==data('checks/source-before.json')
    for phase in ['redraw-after','native-final','stage-poses-final','motion-final','performance']:
        assert data(phase+'/source-before.json')==data(phase+'/source-after.json')==source,phase
    assert data('checks/result.json')['exit']==0
    assert 'checks: 56939, new failures: 0, known failures (tests/known_failures.txt): 0' in read('checks/raw.log').decode('utf-8')
    old=read('source/before-contact-shadow.gd').replace(b'\r\n',b'\n')
    expected=old.replace(b'\t\tstrength = pow(1.0 - height, 1.5)\n',b'\t\tstrength = pow(1.0 - height, 1.5)\n\telse:\n\t\tsurface = 0.0\n').replace(b'\t\t_surface = surface if surface != INF else 0.0',b'\t\t_surface = surface')
    assert expected==read('source/contact_shadow.gd').replace(b'\r\n',b'\n')
    assert hashlib.sha256(read('source/contact_shadow.gd')).hexdigest()==source['game/level/environment/contact_shadow.gd']
    redraw=data('redraw-after/redraw.json');assert redraw['failures']==0
    before,current=redraw['rows'];assert before['pit_draws']>=20 and current['pit_draws']==0
    assert all(x['pit_physics_frames']>=25 and x['reacquired'] and not x['pit_cast'] for x in redraw['rows'])
    assert data('redraw-before/redraw.json')['failures']>0 and data('redraw-before/run.json')['exit']==1
    native=0;wider=0
    for q,quality in enumerate(['low','medium','high']):
        for level in ['ch1_warehouse','ch1_street']:
            prefix='native-final/'+quality+'-'+level+'/'
            report=data(prefix+'native-index.json');assert report['failures']==0 and len(report['rows'])==10
            by_label={x['label']:x for x in report['rows']}
            assert by_label['watchdog']['half_width']>by_label['sweeper']['half_width']*2
            assert by_label['player-dead']['half_width']>by_label['player-landed']['half_width']
            assert by_label['player-raised']['strength']<by_label['player-landed']['strength']
            for row in report['rows']:
                assert row['quality']==q and row['same_pixels'] and row['cast'] and row['in_view']
                label=prefix+row['label'];on=photo(label+'-on.png');before_image=photo(label+'-before.png');off=photo(label+'-off.png')
                assert on.tobytes()==before_image.tobytes()
                difference=ImageChops.difference(on,off).getbbox();assert difference is not None
                x,y,w,h=row['pixel_bounds']
                wider+=int(difference[0]<x-2 or difference[1]<y-2 or difference[2]>x+w+2 or difference[3]>y+h+2)
                native+=1
    assert native==60
    fixtures=data('stage-poses-final/stage-fixtures.json');assert len(fixtures)==9
    authored=data('stage-poses-final/authored-source.json')
    assert authored['sha256']==source[authored['path']]
    assert fixtures[-1]['scene']['steps'][:2]==[authored['stage'],authored['actor']]
    stage_count=0
    for q in [0,1,2]:
        prefix='stage-poses-final/'+str(q)+'/'
        report=data(prefix+'stage-index.json');assert report['failures']==0 and len(report['records'])==9
        for row,fixture in zip(report['records'],fixtures):
            assert row['name']==fixture['name'] and row['quality']==q and row['saved'] and len(row['actors'])==1
            actor=row['actors'][0];expected=fixture['scene']['steps'][1]
            assert actor['facing']==actor['rig_facing']==expected['facing'] and actor['posture_ready']
            assert actor['position']==expected['pos'] and actor['pose']==expected['pose']
            x,y,w,h=actor['pixel_bounds'];assert x>=0 and y>=0 and x+w<=1280 and y+h<=720
            photo(prefix+row['name']+'.png');stage_count+=1
    motion_count=0
    for q,name in [(0,'low-ch1_street'),(2,'high-ch1_warehouse')]:
        prefix='motion-final/'+name+'/'
        report=data(prefix+'motion-index.json');rows=report['rows']
        assert report['quality']==q and report['airborne'] and report['landed'] and report['all_saved']
        assert len(rows)==240 and [x['frame'] for x in rows]==list(range(240)) and set(x['facing'] for x in rows)=={-1,1}
        assert max(x['feet'][1] for x in rows)-min(x['feet'][1] for x in rows)>50
        assert rows[21]['jump_held'] and not rows[23]['jump_held'] and rows[140]['jump_held'] and not rows[162]['jump_held']
        assert all(math.isfinite(v) for x in rows for v in x['feet']+x['bounds']+[x['strength']])
        for frame in report['image_frames']:photo(prefix+('motion-%03d.png'%frame))
        motion_count+=len(rows)
    ratios=[];intervals=0
    for trial in ['1']:
        report=data('performance/'+trial+'/walls-index.json');perf=report['perf'];groups=perf['contact_samples']
        assert report['failures']==0 and len(groups)==120 and perf['actors_before']['valid'] and perf['actors_after']['valid']
        pairs=[]
        for i in range(0,120,2):
            pair={}
            for group in groups[i:i+2]:
                assert group['contacts']>=13 and group['rays']==group['contacts']*5 and not group['wall_suspended'] and group['quality']==2
                assert len(group['frames_ms'])==45 and all(0<x<10000 and math.isfinite(x) for x in group['frames_ms'])
                pair[group['enabled']]=statistics.median(group['frames_ms']);intervals+=45
            pairs.append(pair[True]/pair[False])
        exact=statistics.median(pairs);assert abs(exact-perf['ratio_exact'])<1e-9 and exact<=1.08
        ratios.append(exact)
        photo('performance/'+trial+'/walls-perf-context.png')
        if trial=='1':
            reenter=report['reenter'];assert len(reenter['nodes'])==len(reenter['texture_mib'])==10 and not reenter['accumulates']
            assert reenter['nodes'][-1]<=reenter['nodes'][1]
            assert max(reenter['texture_mib'][-3:])<=max(reenter['texture_mib'][:3])*1.02+.5
    runs=data('performance/runs.json');assert len(runs)==1
    for run in runs:
        assert run['exit']==run['script_errors']==0 and not run['engine_error'] and run['source_held']
        assert all(p['headless'] for p in run['processes_before']+run['processes_after'])
    for archive in archives:archive.close()
    return {'members':len(files),'physical_members':len(locations),'deduplicated_exact_capture_files':len(aliases),'native_pairs':native,
        'on_off_differences_outside_contact_bounds':wider,'stage_png':stage_count,'motion_samples':motion_count,'frame_intervals':intervals,'ratios':ratios,'quiet_runs':[r['quiet'] for r in runs]}

if __name__=='__main__':
    folder=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).resolve().parent
    print(json.dumps(verify(folder),indent=2))
