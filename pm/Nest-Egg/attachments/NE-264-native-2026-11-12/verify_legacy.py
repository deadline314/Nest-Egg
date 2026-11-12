"""Verify selected retained failures without relabeling them as complete captures."""
from pathlib import Path
import hashlib,json,math,tempfile,zipfile

here=Path(__file__).resolve().parent
index=json.loads((here/'legacy-index.json').read_text(encoding='utf-8'))
results=[]
with zipfile.ZipFile(here/'legacy-selected-original.zip') as z:
    for case in index['cases']:
        prefix=case['case']+'/'
        for member in case['members']:
            raw=z.read(member['path']);assert len(raw)==member['bytes'] and hashlib.sha256(raw).hexdigest()==member['sha256']
        report=json.loads(z.read(prefix+'result.json'))
        rows=report['frames'];receipt=json.loads(z.read(prefix+'exit.json'))
        name=case['case'];result={'case':name,'original_result_sha256':hashlib.sha256(z.read(prefix+'result.json')).hexdigest()}
        if name=='original-horizontal-room-precondition':
            run=[r for r in rows if r['phase']=='run'];assert len(run)==240 and run[-1]['tray_above']>.99
            assert receipt['exit']==1 and any(not c['ok'] for c in report['checks'])
            result.update(cause='original horizontal-input run never establishes enough room; stimulus failure retained',draws=240,remains_above=run[-1]['tray_above'])
        elif name=='v8-mixed-product-red':
            before=report['phase_baselines'][0]['far_slot_local'];points=[before]+[r['far_slot_local'] for r in rows]
            movement=[math.dist(a,b) for a,b in zip(points,points[1:])];peak=max(movement)
            assert peak>24 and movement.index(peak)==2 and receipt['exit']==1
            result.update(cause='actual mixed jump displacement violates original24 gate',original_threshold=24,peak=peak,peak_sample=2)
        elif name=='v11-view-head-product-red':
            bad=[r for r in rows if r['reserve_logical'][0]<0]
            assert bad and receipt['exit']==0
            result.update(cause='engine exited0 but independent original viewport gate rejects reserve clipping',minimum_reserve_x=min(r['reserve_logical'][0] for r in bad))
        elif name=='v12-aim-product-red':
            row=next(r for r in rows if r['phase']=='run-aim-up' and r['sample']==0)
            guard=row['guard_logical'];x,y=row['aim_start_logical'];assert abs(row['aim'][0])<1e-12 and row['aim'][1]<-.99
            assert guard[0]<=x<=guard[0]+guard[2] and guard[1]+guard[3]<y
            assert row['guard_ratio']==1 and row['tag_alpha']>=.95 and row['tag_pop']==row['tag_shake']==0
            result.update(cause='narrower v12 reader passed but true UP ray crosses the actual full guard draw primitive',muzzle=[x,y],full_guard_draw=guard)
        else:raise AssertionError(name)
        results.append(result)
print(json.dumps({'passed':True,'scope':'selected original failure bytes and independent cause checks only; full old captures remain at legacy-index original_capture paths','cases':results},indent=2))
