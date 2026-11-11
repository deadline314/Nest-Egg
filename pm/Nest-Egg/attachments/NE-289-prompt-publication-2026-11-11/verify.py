"""Verify original UI timing/geometry records independently of Godot assertions."""
from pathlib import Path
import hashlib,json,re,zipfile
HERE=Path(__file__).resolve().parent
FINAL='58b20d358282eb52effc2be4cc4ffbeafc91d4f3ac2f8e62981c0cef448771dd'
def sha(data):return hashlib.sha256(data).hexdigest()
def transform_rect(rect,t):
 x,y,w,h=rect;a,b,c,d,ox,oy=t
 points=[(a*px+c*py+ox,b*px+d*py+oy) for px,py in [(x,y),(x+w,y),(x,y+h),(x+w,y+h)]]
 left=min(x for x,y in points);top=min(y for x,y in points)
 return [left,top,max(x for x,y in points)-left,max(y for x,y in points)-top]
def intersects(a,b):return max(a[0],b[0])<min(a[0]+a[2],b[0]+b[2]) and max(a[1],b[1])<min(a[1]+a[3],b[1]+b[3])
def placed(value):return [value['prompt_base'][0]+value['prompt_nudge'][0],value['prompt_base'][1]+value['prompt_nudge'][1],*value['prompt_base'][2:]]
def reproject(rows):
 errors=[max(abs(a-b) for a,b in zip(transform_rect(r['actual_row'],r['canvas']),r['row_screen'])) for r in rows if 'row_screen' in r and r['actual_row'][2]>0]
 assert errors and max(errors)<0.001,'current world/HUD transforms must agree'
 return len(errors),max(errors)
def main():
 index=json.loads((HERE/'controlled-index.json').read_bytes());raw=(HERE/'controlled-raw.zip').read_bytes()
 assert sha(raw)==index['raw_sha256'] and len(raw)==index['raw_bytes'];checks=2
 expected={'original-red':(31,1,1),'layout-only-red':(31,1,1),'layout-nudge-old-row-red':(32,1,1),'current-row-only-red':(31,1,1),'first-both-green':(32,0,0),'first-wrong-target':(32,1,1),'first-stopped-layout':(32,4,1),'final-timer-green':(32,0,0),'final-wrong-target':(32,1,1),'final-stopped-layout':(32,4,1),'final-full-suite':(397,0,0)}
 ui={'tests/suite/test_quest_map.gd':'df0acf05d43adab2a3a66a441a9a9369ef3c12fe1fd153c0a961850f34926f59','game/level/world_prompt.gd':'aabe6690f993029361f413ce3421d86ea0c9fd1cadf868fda1467b4c88648981','ui/quest_guidance.gd':'4a3d4f05d181d9aa0697a1c82817875cec53ab896e666a0696b264dff9f564e5'}
 with zipfile.ZipFile(HERE/'controlled-raw.zip') as z:
  assert z.testzip() is None and set(z.namelist())==set(index['entries']);checks+=2
  for name,value in index['entries'].items():
   data=z.read(name);assert sha(data)==value['sha256'] and len(data)==value['bytes'],name;checks+=2
  source=z.read('final/tests/suite/test_quest_map.gd');assert sha(source)==FINAL and b'--wrong-target' not in source and b'--stop-layout' not in source;checks+=3
  assert b'placed.intersects(observation_row)' in source and b'create_timer(0.0, true, false, true)' in source;checks+=2
  events={};logs={}
  for label,(count,failures,code) in expected.items():
   receipt=json.loads(z.read(label+'/receipt.json'));log=z.read(label+'/process.log').decode('utf-8');logs[label]=log
   assert receipt['same_source'] is True and receipt['before']==receipt['after'] and receipt['exit']==code;checks+=3
   assert f'checks: {count}, failures: {failures}' in log and len(re.findall(r'^FAIL: ',log,re.M))==failures;checks+=2
   assert 'SCRIPT ERROR' not in log and '\nERROR:' not in log and 'ObjectDB instances leaked' not in log and 'resources still in use' not in log;checks+=4
   assert all(receipt['before'][name]==value for name,value in ui.items());checks+=3
   for name,value in receipt['before'].items():assert sha(z.read(label+'/source/'+name))==value;checks+=1
   assert sha(z.read(label+'/executed-runner.py'))==receipt['runner_sha256'];checks+=1
   events[label]=[json.loads(line.split('PROMPT_BUFFERED ',1)[1]) for line in log.splitlines() if 'PROMPT_BUFFERED ' in line]
  aligned=next(r for r in events['original-red'] if r['event']=='after_align')
  failed=next(r for r in events['original-red'] if r['event'].startswith('assert_false_the prompt itself'))
  assert aligned['process']==failed['process'] and aligned['prompt_layout_frame']==failed['prompt_layout_frame']<failed['process'];checks+=3
  assert aligned['prompt_nudge']==failed['prompt_nudge'] and aligned['prompt_target']==failed['prompt_target'];checks+=2
  assert not intersects(placed(failed),failed['initial_row']);checks+=1
  for label in ['first-both-green','final-timer-green','final-full-suite']:
   count,error=reproject(events[label]);checks+=count
   good=next(r for r in events[label] if r['event'].startswith('assert_true_the prompt itself'))
   assert intersects(placed(good),good['actual_row']);checks+=1
   if label!='final-full-suite':assert not intersects(placed(good),good['initial_row']);checks+=1
  for label in ['final-wrong-target','first-wrong-target']:
   wrong=next(r for r in events[label] if r['event']=='wrong_target_control')
   assert wrong['prompt_nudge']==wrong['prompt_target'] and not intersects(placed(wrong),wrong['actual_row']);checks+=2
   assert 'FAIL: the prompt itself stays in place' in logs[label];checks+=1
  stopped=next(r for r in events['final-stopped-layout'] if r['event'].startswith('assert_false_prompt layout publishes'))
  assert stopped['prompt_is_processing'] is False;checks+=1
 print(json.dumps({'checks':checks,'failures':0,'controlled_raw_sha256':index['raw_sha256'],'scope':'controlled UI timing and source records only; official affected results are separate'}))
 return checks
if __name__=='__main__':main()
