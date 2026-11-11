"""Recheck the sealed CPU evidence offline. Never launches Godot or reads live managed inputs."""
from pathlib import Path,PurePosixPath
import hashlib,json,stat,sys,tempfile,zipfile
from audit import Audit

HERE=Path(__file__).resolve().parent
def sha(data):return hashlib.sha256(data).hexdigest()

def safe_member(name):
 path=PurePosixPath(name)
 assert name and not path.is_absolute() and '..' not in path.parts and '\\' not in name and ':' not in name,'unsafe ZIP path'

def actor_checks(data):
 assert data['checks']==37 and not data['failures']
 rows=data['records'];grunt=next(r for r in rows if r.get('actor')=='grunt-positive-control')
 assert grunt['authored_credit_value']>0 and grunt['published_credit_pickups']==[grunt['authored_credit_value']]
 yong=[r for r in rows if r.get('actor')=='yong'];assert {r['route'] for r in yong}=={'cut','keep'}
 for row in yong:
  assert row['subdued'] and not row['dying'] and row['health']==row['floor_health']==1
  assert row['health_died_signals']==0 and not row['published_credit_pickups'] and row['authored_credit_value']==120
 janus=next(r for r in rows if r.get('actor')=='janus')
 assert janus['health_died_signals']==1 and not janus['published_credit_pickups'] and janus['authored_credit_value']==1
 tx=[r for r in rows if 'transaction' in r];assert len(tx)==2
 assert {r['transaction']:r['authored_delta'] for r in tx}=={'ch2.yong_subdued':120,'ch3.gate_disabled':100}
 for row in tx:
  assert row['after_first']-row['before']==row['authored_delta'] and row['after_second']==row['after_first']
  assert row['first_result']['applied'] is True and row['second_result']['status']=='already_recorded' and row['second_result']['credits_delta']==0

def verify(folder=HERE):
 assert not sys.flags.optimize,'guards require normal Python execution, not -O'
 folder=Path(folder);index=json.loads((folder/'index.json').read_bytes());raw=(folder/index['raw']).read_bytes()
 assert len(raw)==index['bytes'] and sha(raw)==index['sha256']
 with tempfile.TemporaryDirectory(prefix='ne231-evidence-') as directory:
  root=Path(directory).resolve()
  with zipfile.ZipFile(folder/index['raw']) as archive:
   assert archive.testzip() is None
   assert len(archive.namelist())==len(set(archive.namelist())) and set(archive.namelist())==set(index['members'])
   for entry in archive.infolist():
    safe_member(entry.filename);assert not stat.S_ISLNK(entry.external_attr>>16)
    data=archive.read(entry);assert sha(data)==index['members'][entry.filename]
    target=(root/entry.filename).resolve();assert target.is_relative_to(root)
    target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
  assert (folder/'audit.py').read_bytes()==(root/'authoring/audit.py').read_bytes()
  read=lambda name:json.loads((root/name).read_bytes())
  frozen=read('frozen-inputs/manifest.json')
  for version,files in frozen['files'].items():
   for name,digest in files.items():assert sha((root/'frozen-inputs'/version/name).read_bytes())==digest
  for name,item in index['final_sources'].items():
   assert sha((root/'frozen-inputs/baseline'/name).read_bytes())==item['before_sha256']
   assert sha((root/'frozen-inputs/candidate'/name).read_bytes())==item['after_sha256']
  for name in ['original-ledger','original-actor-controls','candidate-v2-controls','candidate-v3-controls']:
   exit=read(name+'/exit.json');assert exit['exit']==0 and exit['economic_sources_same'] and exit['context_same'] and not exit['diagnostics']
   before=read(name+'/source-before.json');after=read(name+'/source-after.json')
   assert before['economic_inputs']==after['economic_inputs'] and before['base']==after['base'] and before['other_working_context']==after['other_working_context']
   text=(root/name/'engine.log').read_text(encoding='utf-8',errors='replace')
   assert not any(mark in text for mark in ['SCRIPT ERROR','ERROR:','ObjectDB instances leaked','resources still in use'])
  before=read('candidate-v3-controls/source-before.json');after=read('candidate-v3-controls/source-after.json')
  assert before['tracked_test_context']==after['tracked_test_context'] and before['work_probe']==after['work_probe']
  actor_checks(read('original-actor-controls/boss-drops.json'))
  controls=read('candidate-v3-controls/candidate-control.json');assert controls['accepted']
  cases=controls['cases'];assert len(cases)==6
  assert [r['checks'] for r in cases]==[68,68,68,68,6,6]
  assert [len(r['observed_rejections']) for r in cases]==[0,2,2,0,2,0]
  assert all(len(r['observed_rejections'])==r['expected_rejections'] for r in cases)
  old=read('original-ledger/ledger.json');new=read('candidate-v3-controls/candidate-ledger.json')
  old_audit=Audit(root/'frozen-inputs/baseline').verify(old)
  new_audit=Audit(root/'frozen-inputs/candidate').verify(new)
  assert old_audit['checks']==new_audit['checks']==607 and old_audit['growth_total']==new_audit['growth_total']==2300
  assert [p['spare'] for p in old['plan']]==[402,1298,1253]
  assert [p['spare'] for p in new['plan']]==[402,1195,1163]
  assert [a['map_main']['total']-b['map_main']['total'] for a,b in zip(old['chapters'],new['chapters'])]==[0,120,1]
  return {'raw_members':len(index['members']),'frozen_files_each':len(frozen['files']['baseline']),'original_independent_checks':old_audit['checks'],'candidate_independent_checks':new_audit['checks'],'actor_controls':'37/0','data_contract_matrix':'68/0,68/2,68/2,68/0; Economy 6/2 -> 6/0','formal_affected':index['formal_affected'],'performance':False,'engine_started':False}

if __name__=='__main__':print(json.dumps(verify(),ensure_ascii=False))
