from pathlib import Path
import copy,json,sys
import numpy as np
from verify_bg49_held import affine,contrast,load_pixels,raster,section,verify_owners

LABELS=['before','before-repeat','after','restore','after-final']

def geometry(record):
 models=copy.deepcopy(record['models'])
 for m in models:
  m.pop('fill',None);m.pop('cap',None)
 return models

def contains(world,box):
 x,y,w,h=world;a,b,c,d=box
 return a>=x and b>=y and a+c<=x+w and b+d<=y+h

def group(folder,g):
 assert g['controls_valid'] and g['passed']
 records=g['records'];assert [r['label'] for r in records]==LABELS
 first=records[0];assert first['raw_sha256']==records[1]['raw_sha256']==records[3]['raw_sha256']
 assert records[2]['raw_sha256']==records[4]['raw_sha256']
 observed=[];cache={}
 for r in records:
  assert r['held']==first['held'] and geometry(r)==geometry(first) and r['focus']==first['focus']
  assert r['world_environment']['active'] and r['world_environment']['glow_enabled']
  assert r['width']==640 and r['height']==360 and r['format'] in [10,11,14,15]
  assert r['focus']['position']==(r['player']['feet'] if r['player_visible'] else r['camera_world'])
  verify_owners(r['held']['lighting_owners'],r['canvas_transform_values'])
  if g['zone']!='warehouse_interior' and not r['material_edge']:assert r['raw_sha256']==first['raw_sha256']
  if g['zone']=='warehouse_interior' and not r['models']:assert r['raw_sha256']==first['raw_sha256']
  key=r['raw_sha256']
  if key not in cache:cache[key]=load_pixels(folder,r)
  rgb=cache[key];values={'enemies':[],'creatures':[]}
  if r['player_visible']:
   p=r['player'];fx,fy=p['feet'];contact=r['held']['player_support']
   assert contact['valid'] and contact['found'] and contact['solver_contact'] and contact['solver_normal'][1]<-.99
   assert abs(contact['gap'])<=contact['safe_margin']+.001
   assert abs(contact['floor'][1]-fy-contact['gap'])<1e-5
   body=raster([fx-9,fy-58,18,54],r);outer=raster([fx-29,fy-78,58,94],r)
   assert body==p['screen_rect'] and outer==p['outer_screen_rect']
   v=contrast(rgb,body,outer);assert all(abs(v[k]-p['parts'][k])<2e-6 for k in v)
   value=max(v['bright'],v['dark']);assert abs(value-p['contrast'])<2e-6
   edge=raster([fx-24,fy,48,3],r);below=raster([fx-24,fy+8,48,6],r)
   assert edge==p['edge_screen_rect'] and below==p['below_screen_rect'] and min(edge[2:]+below[2:])>0
   luma=rgb@[.2126,.7152,.0722];ev=float((section(luma,edge).mean()-section(luma,below).mean())/(section(luma,below).mean()+.02))
   assert abs(ev-p['edge_contrast'])<2e-6
   values.update(player=value,edge=ev)
  for e in r['enemies']:
   x,y=e['feet'];body=raster([x-9,y-44,18,40],r);outer=raster([x-29,y-64,58,80],r)
   assert body==e['screen_rect'] and outer==e['outer_screen_rect']
   v=contrast(rgb,body,outer);assert all(abs(v[k]-e['parts'][k])<2e-6 for k in v)
   value=max(v['bright'],v['dark']);assert abs(value-e['contrast'])<2e-6
   a,b,w,h=e['visual_world_bounds_values'];full=[min(a,x-9),min(b,y-44),max(a+w,x+9)-min(a,x-9),max(b+h,y-4)-min(b,y-44)]
   assert contains(r['view_world'],full)==e['fully_framed']
   ex=e['exposure'];assert np.max(np.abs(np.array(full)-ex['world_rect']))<1e-5
   area_rect=raster([full[0]-1,full[1]-1,full[2]+2,full[3]+2],r);assert area_rect==ex['screen_rect']
   area=section(rgb,area_rect);white=int(np.all(area>.92,axis=-1).sum());assert area.size and white==ex['white_pixels_including_background'] and abs(float(area.max())-ex['peak'])<2e-6
   assert ex['zero_proves_actor_zero']==(white==0)
   values['enemies'].append({'id':e['id'],'instance':e['instance'],'legacy':value,'full':e['fully_framed'],'white_including_background':white})
  for c in r['collision_enemies']:
   w,h=c['data_size'];assert w>0 and h>0
   assert c['id']=='drone' and [w,h]==[20,14] and not c['uses_gravity']
   matrix=affine(c['shape_transform']);corners=np.array([[-w/2,-h/2,1],[w/2,-h/2,1],[-w/2,h/2,1],[w/2,h/2,1]])@matrix.T
   start=corners[:,:2].min(axis=0);end=corners[:,:2].max(axis=0);box=[*start,*(end-start)]
   assert np.max(np.abs(np.array(c['world_rect'])-box))<1e-5,'Physical collision rectangle mismatch'
   body=raster(box,r);outer=raster([box[0]-20,box[1]-20,box[2]+40,box[3]+40],r)
   assert min(body[2:]+outer[2:])>0 and body==c['screen_rect'] and outer==c['outer_screen_rect']
   v=contrast(rgb,body,outer);value=max(v['bright'],v['dark']);assert all(abs(v[k]-c['parts'][k])<2e-6 for k in v) and abs(value-c['contrast'])<2e-6
   legacy=next(e for e in values['enemies'] if e['instance']==c['instance']);assert abs(legacy['legacy']-c['legacy_18x40'])<2e-6
   values['creatures'].append({'instance':c['instance'],'contrast':value,'legacy':legacy['legacy']})
  observed.append(values)
 final=observed[-1]
 if 'player' in final:assert final['player']>=.6 and final['edge']>=1
 collision={c['instance']:c for c in final['creatures']}
 for e in final['enemies']:
  if g.get('target_instance',0) and e['instance']!=g['target_instance']:continue
  if e['instance'] in collision:assert collision[e['instance']]['contrast']>=.45
  elif e['full']:assert e['legacy']>=.45
 assert {(e['id'],e['instance']) for e in final['enemies'] if not e['full'] and e['instance'] not in collision and (not g.get('target_instance',0) or e['instance']==g['target_instance'])}=={(e['id'],e['instance']) for e in g['cropped_humanoids']}
 return {'before':observed[0],'after':final,'images':len(records)}

def verify(folder):
 summaries=[];total={'cells':0,'standing':0,'logical_hdr':0,'extra_views':0,'humanoid_observations':0,'creature_observations':0};legacy=[];white=[]
 for path in sorted(folder.glob('*/formal-index.json')):
  index=json.loads(path.read_text());assert index['capture_size']==[640,360]
  cols,rows=int(index['columns']),int(index['rows']);assert len(index['shots'])==cols*rows
  assert {(s['column'],s['row']) for s in index['shots']}=={(x,y) for x in range(cols) for y in range(rows)}
  points=[]
  for s in index['shots']:
   assert s['passed'];v=group(path.parent,s['bg30']);total['cells']+=1;total['standing']+=int('player' in v['after']);total['logical_hdr']+=v['images']
   required={c['instance'] for c in s['bg30']['cropped_humanoids']};actual=set()
   for e in s['full_framed_views']:
    x=group(path.parent,e);target=next(t for t in x['after']['enemies'] if t['instance']==e['target_instance']);assert e['target_complete'] and target['full'] and target['legacy']>=.45
    actual.add(e['target_instance']);total['extra_views']+=1;total['logical_hdr']+=x['images']
   assert actual==required
   for e in v['after']['enemies']:
    if e['white_including_background']:white.append({'level':index['level'],'cell':[s['column'],s['row']],**e})
    if e['id']=='drone':
     total['creature_observations']+=1
     if e['legacy']<.45:legacy.append({'level':index['level'],'cell':[s['column'],s['row']],**e})
    elif e['full']:total['humanoid_observations']+=1
   points.append({'cell':[s['column'],s['row']],**v})
  summaries.append({'level':index['level'],'cells':len(points),'points':points})
 assert len(summaries)==12 and total['cells']==288
 values=[p['after'] for s in summaries for p in s['points']]
 return {'passed':True,**total,'minimum_player':min(v['player'] for v in values if 'player' in v),'minimum_edge':min(v['edge'] for v in values if 'edge' in v),'minimum_full_humanoid':min(e['legacy'] for v in values for e in v['enemies'] if e['full'] and e['id']!='drone'),'minimum_physical_creature':min(c['contrast'] for v in values for c in v['creatures']),'legacy_nonhuman_below':legacy,'white_including_background':white,'levels':summaries,'scope':'original grid, same formulas and gates; cropped humanoids retain legacy values and require geometry-chosen full-framed supplemental views; nonhuman physical rectangles supplement original legacy windows, no historical full-checkout or natural combat/FPS/VRAM claim'}

if __name__=='__main__':
 folder=Path(sys.argv[1]);r=verify(folder);(folder/'independent.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({k:v for k,v in r.items() if k not in ['levels','legacy_nonhuman_below','white_including_background']},indent=2))
