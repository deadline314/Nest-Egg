"""Read-only original float-pixel BG42 counterfactual; unchanged .6/.45/1 thresholds."""
from pathlib import Path
import argparse,hashlib,json
import numpy as np
from verify_bg49_held import affine,contrast,load_pixels,raster,section,verify_owners
LABELS=['A0','A1','product-old','restore-old','reference-new','product-new','restore-new','restore-original','authored-final']
REFERENCE=[True,True,False,True,True,False,True,True,False]
CANDIDATE=[False,False,False,False,True,True,True,False,True]
WORLD_KEYS=['actors','rain','fog_time','shader_time_scale','camera','player','aim','player_support','weapon_light_position','weapon_light_energy']

def verify(folder):
 receipt=json.loads((folder/'exit.json').read_bytes())
 assert receipt['strict_clean'] and receipt['exit']==0 and receipt['sources_unchanged'] and receipt['host_helpers_unchanged'] and receipt['queue_clear_before_after']
 assert json.loads((folder/'source-before.json').read_bytes())==receipt['source_after']
 observations=[]
 for index in sorted(folder.glob('*/*-index.json')):
  data=json.loads(index.read_bytes());assert data['level']in ['ch2_ledger_front','ch2_ledger_office','ch2_lounge_front']
  assert float(data['columns']).is_integer() and float(data['rows']).is_integer()
  columns,rows=int(data['columns']),int(data['rows']);assert columns>0 and rows>0
  assert len(data['shots'])==columns*rows
  assert {(s['column'],s['row'])for s in data['shots']}=={(x,y)for x in range(columns)for y in range(rows)}
  for shot in data['shots']:
   group=shot['bg42'];assert group['controls_valid'];records=group['records'];assert [r['label']for r in records]==LABELS
   assert len({records[i]['raw_sha256']for i in [0,1,3,7]})==1
   assert records[4]['raw_sha256']==records[6]['raw_sha256'] and records[5]['raw_sha256']==records[8]['raw_sha256']
   original=records[0];witness={k:original['held'][k]for k in WORLD_KEYS};cache={};values_by_label={}
   for i,r in enumerate(records):
    assert {k:r['held'][k]for k in WORLD_KEYS}==witness
    assert r['ambient']==original['ambient'] and r['fog_density']==original['fog_density']
    assert r['held']['lamps']==original['held']['lamps'] and r['held']['fog_visible']==original['held']['fog_visible']
    assert r['enemy_inventory']==original['enemy_inventory']
    assert r['profile_valid'] and r['world_environment']['active'] and r['world_environment']['glow_enabled']
    assert r['prop_reference']==REFERENCE[i] and r['profile_candidate']==CANDIDATE[i]
    if CANDIDATE[i] and data['level']=='ch2_ledger_office':
     assert abs(r['character_floor']-.5)<1e-6 and abs(r['enemy_fill_scale']-1)<1e-6
    else:assert r['character_floor']==original['character_floor'] and r['enemy_fill_scale']==original['enemy_fill_scale']
    for kind,visible in [('added',not REFERENCE[i]),('removed',REFERENCE[i])]:
     for entry in group['prop_delta'][kind]:
      nodes=[n for n in r['props']if n['id']==entry['id']];assert len(nodes)==1 and nodes[0]['visible']==visible
    selected={p['id']for p in group['prop_delta']['added']+group['prop_delta']['removed']}
    assert [p for p in r['props']if p['id']not in selected]==[p for p in original['props']if p['id']not in selected]
    verify_owners(r['held']['lighting_owners'],r['canvas_transform_values'])
    final=affine(r['held']['lighting_owners']['viewport_final_transform_values'])
    assert np.max(np.abs(final-np.diag([r['density'],r['density'],1])))<1e-5
    assert r['weapon_light']['origin_error']<=1e-5 and r['weapon_light']['fade_level']>=.999
    key=r['raw_sha256']
    if key not in cache:cache[key]=load_pixels(index.parent,r)
    rgb=cache[key];assert np.isfinite(rgb).all()
    row={'enemies':[]}
    if r['player_visible']:
     assert r['held']['player_support']['valid'] and r['held']['player_support']['solver_contact']
     p=r['player'];fx,fy=p['feet'];body=raster([fx-9,fy-58,18,54],r);outer=raster([fx-29,fy-78,58,94],r)
     assert body==p['screen_rect'] and outer==p['outer_screen_rect']
     parts=contrast(rgb,body,outer);assert all(abs(parts[k]-p['parts'][k])<2e-6 for k in parts)
     value=float(max(parts['bright'],parts['dark']));assert abs(value-p['contrast'])<2e-6
     edge=raster([fx-24,fy,48,3],r);below=raster([fx-24,fy+8,48,6],r)
     assert edge==p['edge_screen_rect'] and below==p['below_screen_rect']
     luma=rgb@[.2126,.7152,.0722];ev=float((section(luma,edge).mean()-section(luma,below).mean())/(section(luma,below).mean()+.02))
     assert abs(ev-p['edge_contrast'])<2e-6;row.update(player=value,edge=ev)
    for e in r['enemies']:
     ex,ey=e['feet'];body=raster([ex-9,ey-44,18,40],r);outer=raster([ex-29,ey-64,58,80],r)
     assert body==e['screen_rect'] and outer==e['outer_screen_rect']
     parts=contrast(rgb,body,outer);assert all(abs(parts[k]-e['parts'][k])<2e-6 for k in parts)
     value=float(max(parts['bright'],parts['dark']));assert abs(value-e['contrast'])<2e-6
     row['enemies'].append({'id':e['id'],'feet':e['feet'],'contrast':value})
    values_by_label[r['label']]=row
   baseline=values_by_label['A0'];final=values_by_label['authored-final'];newref=values_by_label['reference-new']
   absolute=('player'not in final or final['player']>=.6 and final['edge']>=1)and all(e['contrast']>=.45 for e in final['enemies'])
   deltas={k:final[k]-baseline[k]for k in ['player','edge']if k in final}
   enemy_deltas=[]
   assert len(final['enemies'])==len(baseline['enemies'])
   for a,b in zip(baseline['enemies'],final['enemies']):
    assert (a['id'],a['feet'])==(b['id'],b['feet']);enemy_deltas.append(b['contrast']-a['contrast'])
   observations.append(dict(level=data['level'],column=shot['column'],row=shot['row'],absolute_pass=absolute,baseline=baseline,final=final,candidate_prop_reference=newref,deltas=deltas,enemy_deltas=enemy_deltas,no_worse=all(v>=0 for v in deltas.values())and all(v>=0 for v in enemy_deltas)))
 assert observations
 return dict(absolute_pass=all(o['absolute_pass']for o in observations),no_worse=all(o['no_worse']for o in observations),cells=len(observations),standable=sum('player'in o['final']for o in observations),enemy_observations=sum(len(o['final']['enemies'])for o in observations),decreases=[o for o in observations if not o['no_worse']],observations=observations,scope='Current held geometry with original BG42 prop delta and only proposed local office profile; unchanged thresholds; no head exposure or performance acceptance',reader_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest())

if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('folder',type=Path);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
 result=verify(a.folder);a.out.write_text(json.dumps(result,indent=2)+'\n',encoding='utf-8',newline='\n');print(json.dumps({k:v for k,v in result.items()if k!='observations'}));raise SystemExit(0 if result['absolute_pass']and result['no_worse']else 1)
