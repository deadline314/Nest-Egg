"""Read-only NE-259 packet verification; Python 3.10+ and existing Pillow."""
from pathlib import Path
import hashlib,json,math,statistics,struct,sys
from PIL import Image
ROOT=Path(__file__).resolve().parent
CHECKS=0
FAIL=[]
def check(value,name):
 global CHECKS
 CHECKS+=1
 if not value:FAIL.append(name)
def digest(path):
 h=hashlib.sha256()
 with path.open('rb') as f:
  for part in iter(lambda:f.read(1024*128),b''):h.update(part)
 return h.hexdigest()
def read(path):return json.loads(path.read_text(encoding='utf-8'))
for row in read(ROOT/'manifest.json'):
 p=ROOT/row['path']
 check(p.resolve().is_relative_to(ROOT),'member stays in packet: '+row['path'])
 check(p.is_file() and p.stat().st_size==row['bytes'] and digest(p)==row['sha256'],'member bytes: '+row['path'])
for row in read(ROOT/'frozen-candidate/sources.json'):
 p=ROOT/'frozen-candidate'/row['path']
 check(digest(p)==row['sha256'] and p.read_bytes().count(b'\r\n')==0,'final LF source: '+row['path'])
 if len(sys.argv)>1:
  check(digest(Path(sys.argv[1])/row['path'])==row['sha256'],'workspace final source: '+row['path'])
expected={
 'cpu-red-v1':(1,b'ENEMY_GLOW_CPU_RESULT:2/2',0),
 'cpu-green-v1':(0,b'ENEMY_GLOW_CPU_RESULT:15/0',0),
 'cpu-green-v2':(0,b'ENEMY_GLOW_CPU_RESULT:15/0',0),
 'cpu-green-final':(0,b'ENEMY_GLOW_CPU_RESULT:15/0',0),
 'anchor-red-v1':(1,b'NE259_ANCHOR_RESULT:38/20',1),
 'anchor-red-v2':(1,b'NE259_ANCHOR_RESULT:38/18',1),
 'anchor-green-v1':(0,b'NE259_ANCHOR_RESULT:39/0',1),
 'anchor-green-v2':(0,b'NE259_ANCHOR_RESULT:40/0',1),
 'eye-control-v1':(0,b'NE259_EYE_CONTROL:',0),
 'eye-receipts-final':(0,b'NE259_EYE_RECEIPTS:',0),
 **{f'native-{q}-{epoch}':(0,b'ENEMY_GLOW_PROBE:ch1_warehouse failures 0',0) for q in ['low','high'] for epoch in ['v1','final']}}
frozen={r['path']:r['sha256'] for r in read(ROOT/'frozen-candidate/sources.json')}
for name,(exitcode,marker,errors) in expected.items():
 folder=ROOT/'cases'/name
 result=read(folder/'result.json');launch=read(folder/'launch.json');raw=(folder/'raw.log').read_bytes()
 check(result['natural_exit']==exitcode,name+' natural exit')
 check(marker in raw,name+' actual terminal result')
 check(raw.count(b'SCRIPT ERROR:')==0,name+' no script error')
 check(sum(x.startswith(b'ERROR:') for x in raw.splitlines())==errors,name+' raw engine error classification')
 check(launch['source_before']==result['source_after'],name+' actual source before/after')
 for path,sha in launch['source_before'].items():
  check(digest(folder/'source'/path)==sha,name+' source snapshot: '+path)
  if name in ['cpu-green-final','anchor-green-v2','native-low-final','native-high-final','eye-receipts-final'] and path in frozen:
   check(sha==frozen[path],name+' matches final candidate: '+path)
 if errors:
  check(b'test_missing_prop_bone' in raw,name+' expected missing-part fault is retained')
 for png in folder.glob('*.png'):
  data=png.read_bytes();check(data[:8]==b'\x89PNG\r\n\x1a\n' and min(struct.unpack('>II',data[16:24]))>0,name+' valid PNG '+png.name)
for q in ['low','high']:
 for epoch in ['v1','final']:
  name='native-'+q+'-'+epoch;folder=ROOT/'cases'/name
  data=read(folder/(q+'-index.json'));perf=data['perf'];pairs=perf['pairs'];result=read(folder/'result.json')
  check(len(pairs)==60 and all(p['round']==i and p['on_first']==(i%2==0) for i,p in enumerate(pairs)),name+' original complete sixty alternating pairs')
  check(all(math.isfinite(p['on_ms']) and math.isfinite(p['off_ms']) and min(p['on_ms'],p['off_ms'])>0 for p in pairs),name+' finite positive timings')
  ratio=statistics.median(p['on_ms']/p['off_ms'] for p in pairs)
  check(abs(ratio-perf['ratio_raw'])<1e-12 and ratio<=1.05 and perf['passed'],name+' independent unrounded 105% gate')
  check(perf['glowing_enemies']==6 and perf['active_lights']==8 and perf['max_lights']==(8 if q=='low' else 24),name+' six glows and original quality cap')
  raw=(folder/'raw.log').read_bytes()
  check(b'Forward+' in raw and b'9070 XT' in raw,name+' physical Forward+ GPU')
  check(result['profile_under_redirected_dir'] and result['reported_user_data_dir']==data['user_data_dir'],name+' actual isolated user data receipt')
  check(result['tool_sha_matches'] and data['tool_sha256']==digest(folder/'source/tools/enemy_glow_probe.gd'),name+' exact native probe source')
  for state in ['calm','alert','telegraph']:
   row=data['states'][state]
   check(row['sweeper（不帶燈）']['glow'] is False,name+' plain control '+state)
   for enemy in ['watchdog','heavy_gunner']:
    check(row[enemy]['state']==state,name+' actual state '+enemy+' '+state)
    check(abs(row[enemy]['level']-{'calm':1.0,'alert':1.7,'telegraph':2.1}[state])<=.010000001,name+' diagnostic rounded level '+enemy+' '+state)
  for enemy in ['watchdog','heavy_gunner']:
   colors=[data['states'][state][enemy]['color'] for state in ['calm','alert','telegraph']]
   check(colors[0]==colors[1] and colors[0]!=colors[2],name+' own/alert/red color '+enemy)
  death=data['death']
  check(death['initial_light_valid'] and death['passed'] and 0<=death['dark_after_seconds']<=3,name+' actual initial light and original extinction limit')
  if epoch=='final':
   check(death['dark_image_saved'] and (folder/(q+'-death-dark.png')).is_file(),name+' actual dark frame retained')
   check(death['dark_source']['node_valid'] and not death['dark_source']['enabled'] and death['dark_source']['energy']==0,name+' actual retained light object is extinguished')
  first=folder/'independent-first-reader-float-boundary.json'
  if first.exists():check(read(first)['failures']==2,name+' original diagnostic-reader floating boundary failure retained')
control=read(ROOT/'cases/eye-control-v1/control-index.json')
check(control['glow_z']==1 and control['head_local_z']==2 and control['head_alpha_at_marker']==1.0,'actual original opaque head covers lower marker')
check(math.dist(control['current_marker_screen'],control['eye_screen_from_authored_image'])>25,'actual original marker is displaced from source eye')
receipt=read(ROOT/'cases/eye-receipts-final/receipts.json');rows=receipt['stages']
check(len(rows)==3 and rows[0]['z']==1 and rows[1]['z']==3 and rows[2]['z']==3,'three explicit rendering intervention stages')
check(math.dist(rows[0]['source_pixel'],rows[1]['source_pixel'])<.001,'raising Z alone leaves wrong source point unchanged')
check(math.dist(rows[2]['source_pixel'],[160.5,120.5])<.001,'eye-position stage actually projects to source eye center')
check(len({r['head_transform'] for r in rows})==1,'actual head pose is fixed across intervention stages')
for row in rows:
 check(digest(ROOT/'cases/eye-receipts-final'/(row['name']+'.png'))==row['png_sha256'],'receipt native frame '+row['name'])
geo=read(ROOT/'eye-source-geometry.json');im=Image.open(ROOT/geo['source']).convert('RGBA');a,b,c,d=geo['review_bbox']
pixels=[{'x':x,'y':y,'rgba':list(im.getpixel((x,y)))} for y in range(b,d) for x in range(a,c) if (lambda v:v[3]>200 and v[0]>90 and v[0]>1.6*v[1] and v[0]>1.6*v[2])(im.getpixel((x,y)))]
check(pixels==geo['pixels'] and len(pixels)==14,'independent source-eye red pixel predicate')
check([min(p['x'] for p in pixels),min(p['y'] for p in pixels),max(p['x'] for p in pixels)+1,max(p['y'] for p in pixels)+1]==geo['eye_bbox_half_open'],'actual half-open eye source bbox')
check(all(abs((e-p)*geo['texture_scale']-offset)<1e-12 for e,p,offset in zip(geo['eye_center'],geo['pivot'],geo['offset_game_units'])),'eye source coordinates convert to game pixels once')
official=ROOT/'official';result=read(official/'result.json');launch=read(official/'launch.json');raw=(official/'raw.log').read_bytes()
check(result['natural_exit']==0 and result['source_held'] and result['source_after']==launch['source_before'],'official changed command naturally passes with frozen source')
for path,sha in launch['source_before'].items():
 check(sha==frozen[path],'official matches frozen candidate: '+path)
for row in read(official/'policy-source.json'):
 check(row['byte_equal_to_baseline'] and digest(official/'source'/row['path'])==row['sha256']==row['base_sha256'],'original official policy source: '+row['path'])
selection=read(official/'selection-scope.json')
check(selection['natural_exit']==0 and selection['same_groups'] and len(selection['groups'])==34,'private fixtures do not change official selected scope')
summary=read(official/'summary.json')
check(summary['groups']==34 and summary['shards']==2 and summary['new_failures']==0,'official actual 34 groups / two processes / zero new failures')
check(summary['checks']>0 and summary['checks']==sum(x['checks'] for x in summary['shard_results']),'official real nonempty check counts')
for entry in summary['shard_results']:
 data=(official/entry['file']).read_bytes()
 check(('checks: %d, failures: %d'%(entry['checks'],entry['failures'])).encode() in data,'raw official shard terminal summary '+entry['file'])
 check(entry['script_errors']==data.count(b'SCRIPT ERROR:')==0,'raw official shard script error count '+entry['file'])
 check(entry['raw_engine_errors']==sum(x.startswith(b'ERROR:') for x in data.splitlines()),'raw official engine ERROR count retained '+entry['file'])
 check(not entry['eof_diagnostics'],'official EOF has no resource leak diagnostic '+entry['file'])
print(json.dumps({'checks':CHECKS,'failures':len(FAIL),'failure_names':FAIL},indent=2))
raise SystemExit(1 if FAIL else 0)
