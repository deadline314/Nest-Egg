"""Recompute archived source integrity, actual cause and fail-closed fixture controls."""
from pathlib import Path
import hashlib,json,re,zipfile
HERE=Path(__file__).resolve().parent
FINAL='f45c5a9e3f41288d6013991b4dd21281309cbf23bf0332f2f1414826d4da7449'
def sha(data):return hashlib.sha256(data).hexdigest()
def cause(events):
 for value in events:
  if value.get('event')!='put_down' or value.get('carry_phase')!=1 or value.get('held') is not True:continue
  buttons=value.get('buttons',{})
  if buttons.get('dash')!=[False,True] or any(buttons.get(name)!=[False,False] for name in ['melee','block','shoot','interact']):continue
  functions=[part['function'] for part in value.get('stack',[])]
  if not all(name in functions for name in ['put_down','handle_input','_process_normal','_physics_process']):continue
  expected={'handle_input':'res://game/player/player_carry.gd','_process_normal':'res://game/player/player.gd','_physics_process':'res://game/player/player.gd'}
  if not all(any(part.get('function')==name and part.get('source')==path for part in value['stack']) for name,path in expected.items()):continue
  same=[e for e in events if e.get('physics')==value['physics'] and e.get('process')==value['process']]
  if any(e.get('held') is False and e.get('carry_phase')==0 and e.get('event','').startswith('after_phase_change') for e in same):return value
 raise AssertionError('actual dash-driven same-step LIFTING to NONE put_down stack required')
def main():
 index=json.loads((HERE/'controlled-index.json').read_bytes());raw=(HERE/'controlled-raw.zip').read_bytes()
 assert sha(raw)==index['raw_sha256'] and len(raw)==index['raw_bytes']
 checks=2
 expected={'original-stack-red':(595,5,1),'neutral-key-only':(595,2,1),'wrong-readiness-proposal':(10017,7,1),'ready-seven-grid':(10017,0,0),'final-seven-grid':(1015,0,0),'missing-mouse-negative':(145,11,1),'bound-shift-negative':(145,11,1),'stopped-carry-negative':(145,3,1),'stopped-visual-negative':(145,2,1),'formal-path-original-carry':(145,0,0)}
 with zipfile.ZipFile(HERE/'controlled-raw.zip') as z:
  assert z.testzip() is None and set(z.namelist())==set(index['entries']);checks+=2
  for name,entry in index['entries'].items():
   data=z.read(name);assert sha(data)==entry['sha256'] and len(data)==entry['bytes'],name;checks+=2
  assert sha(z.read('final/tests/helpers/interaction_holster_checks.gd'))==FINAL;checks+=1
  logs={}
  for label,(count,failures,exit_code) in expected.items():
   receipt=json.loads(z.read(label+'/receipt.json'));log=z.read(label+'/process.log').decode('utf-8');logs[label]=log
   assert receipt['same_source'] is True and receipt['before']==receipt['after'] and receipt['exit']==exit_code;checks+=3
   assert f'checks: {count}, failures: {failures}' in log and len(re.findall(r'^FAIL: ',log,re.M))==failures;checks+=2
   assert 'SCRIPT ERROR' not in log and '\nERROR:' not in log and 'ObjectDB instances leaked' not in log and 'resources still in use' not in log;checks+=4
   for name,value in receipt['before'].items():assert sha(z.read(label+'/source/'+name))==value;checks+=1
   assert sha(z.read(label+'/executed-runner.py'))==receipt['runner_sha256'];checks+=1
  original=z.read('original-stack-red/source/tests/helpers/interaction_holster_checks.gd')
  neutral=z.read('neutral-key-only/source/work/ne277-contact-order/holster_neutral.gd')
  assert neutral==original.replace(b'KEY_SHIFT',b'KEY_CAPSLOCK') and original.count(b'KEY_SHIFT')==1;checks+=2
  events=[json.loads(line.split('HOLSTER_BUFFERED ',1)[1]) for line in logs['original-stack-red'].splitlines() if 'HOLSTER_BUFFERED ' in line]
  contact=cause(events);assert contact['paused'] is False and contact['interaction'] is False;checks+=3
  assert any(e.get('event','').startswith('assertion_pass_false_reading preserves') for e in events) and any(e.get('event','').startswith('assertion_pass_false_return from reading') for e in events);checks+=2
  assert any(e.get('event','').startswith('assertion_pass_false_reading preserves') and e.get('carry_phase')==0 and e.get('held') is False and e.get('last_item_state')==0 for e in events);checks+=1
  for line in logs['neutral-key-only'].splitlines():
   if line.startswith('FAIL: '):assert 'close option' in line or 'death cannot' in line;checks+=1
  controls={'missing-mouse-negative':['all three synthetic device events actually dispatch'],'bound-shift-negative':['synthetic keyboard device event is unbound'],'stopped-carry-negative':['HOLDING support is actually published','first synchronous reading frame preserves the published','reading preserves the frozen'],'stopped-visual-negative':['HOLDING support is actually published','first synchronous reading frame preserves both actual support hand contacts']}
  for label,phrases in controls.items():
   failures=[line for line in logs[label].splitlines() if line.startswith('FAIL: ')]
   assert all(any(phrase in line for phrase in phrases) for line in failures) and all(any(phrase in line for line in failures) for phrase in phrases);checks+=2
  assert '--original-carry' in json.loads(z.read('formal-path-original-carry/command.json'));checks+=1
  assert sha(z.read('formal-path-original-carry/source/tests/helpers/interaction_holster_checks.gd'))==FINAL;checks+=1
 print(json.dumps({'checks':checks,'failures':0,'controlled_raw_sha256':index['raw_sha256'],'scope':'controlled evidence only; official affected result is recorded separately'}))
 return checks
if __name__=='__main__':main()
