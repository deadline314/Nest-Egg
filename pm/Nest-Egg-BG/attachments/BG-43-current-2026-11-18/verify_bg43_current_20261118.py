"""Read only original float pixels; report regional minima and every point decline."""
from pathlib import Path
import hashlib,json,sys
import numpy as np
from verify_bg49_held import contrast,load_pixels,raster,section,verify_owners,transform_values
LABELS=['A0','A1','product-old','restore-old','reference-new','product-new','restore-new','restore-original','authored-final']
WORLD=['actors','rain','fog_time','shader_time_scale','camera','player','aim','player_support','weapon_light_position','weapon_light_energy']
def verify(folder,diagnostic=False):
 receipts=json.loads((folder.parent/'runs.json').read_text());receipt=next(r for r in receipts if r['name']==folder.name)
 assert receipt['exit']==0 or diagnostic and receipt['exit']==1
 assert receipt['script_errors']==0 and not receipt['engine_error'] and receipt['source_held']
 assert any('gpu_lock.py' in c for c in receipt['command'])
 assert json.loads((folder.parent/'source-before.json').read_text())==json.loads((folder.parent/'source-after.json').read_text())
 index=folder/'ch3_plaza/bg43-index.json';data=json.loads(index.read_text());assert data['level']=='ch3_plaza'
 assert data['capture_size']==[640,360]
 cols,rows=int(data['columns']),int(data['rows']);assert len(data['shots'])==cols*rows
 assert {(s['column'],s['row']) for s in data['shots']}=={(x,y) for x in range(cols) for y in range(rows)}
 observations=[]
 for shot in data['shots']:
  group=shot['bg43'];assert group['controls_valid'];records=group['records'];assert [r['label'] for r in records]==LABELS
  assert len({records[i]['raw_sha256'] for i in [0,1,3,7]})==1
  assert records[4]['raw_sha256']==records[6]['raw_sha256'] and records[5]['raw_sha256']==records[8]['raw_sha256']
  first=records[0];witness={k:first['held'][k] for k in WORLD};cache={};values=[]
  for i,r in enumerate(records):
   assert {k:r['held'][k] for k in WORLD}==witness
   assert r['enemy_inventory']==first['enemy_inventory'] and r['held']['lamps']==first['held']['lamps']
   assert r['world_environment']['active'] and r['world_environment']['glow_enabled'] and r['profile_valid']
   assert r['prop_reference']==(i in [0,1,3,4,6,7]) and r['profile_candidate']==(i in [4,5,6,8])
   assert r['character_fill']==first['character_fill'] and r['character_floor']==first['character_floor'] and r['enemy_fill_scale']==first['enemy_fill_scale']
   if 'tone_shadow' in r:
    for color,shader,base in [('tone_shadow','shader_shadow',[.95,.9,1.1,1]),('tone_highlight','shader_highlight',[1.05,1,.97,1])]:
     actual=transform_values(r[color]);readback=transform_values(r[shader]);gain=1.1 if r['profile_candidate'] else 1
     assert len(actual)==4 and actual[3]==1 and np.isfinite(actual+readback).all()
     assert np.max(np.abs(np.array(actual[:3])-np.array(base[:3])*gain))<1e-6
     assert np.max(np.abs(np.array(actual[:3])-np.array(readback[:3])))<1e-6
    edge_color=transform_values(r['terrain_edge_color'])
    assert abs(edge_color[3]-(.9 if r['profile_candidate'] else .55))<1e-6
   for entry in group['prop_delta']['added']:
    nodes=[p for p in r['props'] if p['id']==entry['id']];assert len(nodes)==1 and nodes[0]['visible']==(not r['prop_reference'])
   selected={e['id'] for e in group['prop_delta']['added']}
   assert [p for p in r['props'] if p['id'] not in selected]==[p for p in first['props'] if p['id'] not in selected]
   verify_owners(r['held']['lighting_owners'],r['canvas_transform_values'])
   key=r['raw_sha256']
   if key not in cache:cache[key]=load_pixels(index.parent,r)
   rgb=cache[key];assert np.isfinite(rgb).all();row={'enemies':[]}
   if r['player_visible']:
    assert r['held']['player_support']['valid'] and r['held']['player_support']['solver_contact']
    p=r['player'];fx,fy=p['feet'];body=raster([fx-9,fy-58,18,54],r);outer=raster([fx-29,fy-78,58,94],r)
    assert body==p['screen_rect'] and outer==p['outer_screen_rect']
    parts=contrast(rgb,body,outer);assert all(abs(parts[k]-p['parts'][k])<2e-6 for k in parts)
    main=float(max(parts['bright'],parts['dark']));assert abs(main-p['contrast'])<2e-6
    edge=raster([fx-24,fy,48,3],r);below=raster([fx-24,fy+8,48,6],r)
    assert edge==p['edge_screen_rect'] and below==p['below_screen_rect']
    luma=rgb@[.2126,.7152,.0722];ev=float((section(luma,edge).mean()-section(luma,below).mean())/(section(luma,below).mean()+.02))
    assert abs(ev-p['edge_contrast'])<2e-6;row.update(player=main,edge=ev)
   for e in r['enemies']:
    ex,ey=e['feet'];body=raster([ex-9,ey-44,18,40],r);outer=raster([ex-29,ey-64,58,80],r)
    assert body==e['screen_rect'] and outer==e['outer_screen_rect']
    parts=contrast(rgb,body,outer);value=float(max(parts['bright'],parts['dark']));assert abs(value-e['contrast'])<2e-6
    row['enemies'].append({'id':e['id'],'feet':e['feet'],'contrast':value})
   values.append(row)
  a,b=values[0],values[-1];deltas={k:b[k]-a[k] for k in ['player','edge'] if k in a}
  assert [(e['id'],e['feet']) for e in a['enemies']]==[(e['id'],e['feet']) for e in b['enemies']]
  ed=[y['contrast']-x['contrast'] for x,y in zip(a['enemies'],b['enemies'])]
  observations.append({'cell':[shot['column'],shot['row']],'before':a,'after':b,'deltas':deltas,'enemy_deltas':ed,'point_nondrop':all(v>=0 for v in list(deltas.values())+ed)})
 minima={k:[min(o[side][k] for o in observations if k in o[side]) for side in ['before','after']] for k in ['player','edge']}
 enemies=[e for o in observations for e in o['after']['enemies']]
 absolute=minima['player'][1]>=.6 and minima['edge'][1]>=1 and all(e['contrast']>=.45 for e in enemies)
 regional=all(v[1]>=v[0] for v in minima.values())
 return {'passed':absolute and regional,'absolute_pass':absolute,'regional_nondrop':regional,'minima':minima,'cells':len(observations),'standable':sum('player' in o['after'] for o in observations),'enemy_observations':len(enemies),'point_decreases':[o for o in observations if not o['point_nondrop']],'observations':observations,'contract':'Original BG43 regional-minimum nondecrease plus original absolute thresholds .6/.45/1. Every per-point decline disclosed separately; no exact per-point nondecrease claim. Native held 640x360 full-lamp phase, actual geometry, no full historic checkout or natural combat/performance claim.','reader_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest()}
if __name__=='__main__':
 folder=Path(sys.argv[1]);r=verify(folder,'--diagnostic' in sys.argv)
 (folder/'independent.json').write_text(json.dumps(r,indent=2)+'\n')
 print(json.dumps({k:v for k,v in r.items() if k not in ['observations','point_decreases']})+'\npoint_decreases='+str(len(r['point_decreases'])),flush=True)
 raise SystemExit(0 if r['passed'] else 1)
