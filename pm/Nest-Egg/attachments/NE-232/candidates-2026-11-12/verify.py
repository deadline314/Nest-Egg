"""Read immutable build/native receipts; optionally hash the six local binaries."""
from pathlib import Path
import argparse,hashlib,json,re,struct,zipfile
HERE=Path(__file__).resolve().parent
def sha(data):return hashlib.sha256(data).hexdigest()
def main():
 p=argparse.ArgumentParser();p.add_argument('--check-artifacts',action='store_true');a=p.parse_args()
 index=json.loads((HERE/'raw-index.json').read_bytes());candidates=json.loads((HERE/'candidates.json').read_bytes());archive=HERE/index['archive'];checks=0
 assert archive.stat().st_size==index['bytes'] and sha(archive.read_bytes())==index['sha256'];checks+=2
 with zipfile.ZipFile(archive) as z:
  assert z.testzip() is None and set(z.namelist())==set(index['entries']);checks+=2
  for name,item in index['entries'].items():
   raw=z.read(name);assert len(raw)==item['bytes'] and sha(raw)==item['sha256'],name;checks+=2
  for candidate in candidates['candidates']:
   chapter=candidate['chapter'];prefix=chapter+'/';source=json.loads(z.read(prefix+'stage/source-manifest.json'));export=json.loads(z.read(prefix+'stage/export-manifest.json'))
   assert source['source_sha']==export['source_sha']==candidates['base'];assert source['resource_closure']['issues']==[];checks+=2
   assert not source['readiness']['ready_for_product_export'] and not export['is_release'] and not export['chapter_acceptance_verified'];checks+=3
   assert export['windows_clean_launch']['verified'] and not export['linux_clean_launch']['verified'];checks+=2
   launch=z.read(prefix+'stage/clean-launch-windows.log').decode('utf-8');match=re.search(r'^EDITION_INFO (.+)$',launch,re.M);assert match
   report=json.loads(match.group(1));assert report['through']==chapter and report['issues']==[] and report['development'] is False;checks+=3
   assert report['first_level_included'] and report['first_level']=='res://data/levels/ch1_prologue.tres';checks+=2
   assert not re.search(r'SCRIPT ERROR|ERROR:|ObjectDB instances leaked|resources still in use',launch);checks+=1
   steps=json.loads(z.read(prefix+'build/receipts.json'));assert len(steps)==3 and all(step['exit']==0 for step in steps);checks+=1
   for step in steps:assert sha(z.read(prefix+'build/'+step['log']))==step['log_sha256'];checks+=1
   native=json.loads(z.read(prefix+'native-menu/receipt.json'));assert native['exit']==0 and native['frames']==90 and native['executable_unchanged'];checks+=3
   raw=z.read(prefix+'native-menu/persisted-godot.log').decode('utf-8');assert 'Forward+' in raw and 'RX 9070 XT' in raw;checks+=2
   assert not re.search(r'SCRIPT ERROR|ERROR:|ObjectDB instances leaked|resources still in use',raw);checks+=1
   frames=sorted(name for name in z.namelist() if name.startswith(prefix+'native-menu/frames/') and name.endswith('.png'));assert len(frames)==90;checks+=1
   for frame in frames:
    png=z.read(frame);assert png[:8]==b'\x89PNG\r\n\x1a\n' and struct.unpack('>II',png[16:24])==(1280,720);checks+=1
   if chapter=='ch1_kasa':
    correction=json.loads(z.read(prefix+'native-menu/persisted-log-verification.json'));assert correction['native_exit']==0 and correction['runner_rejection_preserved'] and native['renderer_forward_plus'] is False;checks+=3
   else:assert native['renderer_forward_plus'] and native['gpu_rx9070xt'];checks+=2
   if a.check_artifacts:
    for platform in ['windows','linux']:
     item=candidate[platform];path=Path(candidate['stage'])/'artifacts'/item['file']
     with path.open('rb') as f:actual=hashlib.file_digest(f,'sha256').hexdigest()
     assert path.stat().st_size==item['bytes'] and actual==item['sha256'];checks+=2
  for prefix in ['os-new-game/','os-cold-resume/']:
   result=json.loads(z.read(prefix+'exit.json'));assert result['exit']==0 and result['error_lines']==[] and result['exe_unchanged'];checks+=3
  cold=json.loads(z.read('os-cold-resume/exit.json'));assert len(cold['stable_fields'])==7 and all(cold['stable_fields'].values());checks+=1
  slots=[]
  for suffix in ['before','after']:
   slot=json.loads(z.read('os-cold-resume/slot-'+suffix+'.json'));assert sha(slot['payload'].encode('utf-8'))==slot['checksum'];slots.append(json.loads(slot['payload']));checks+=1
  for key in cold['stable_fields']:assert slots[0][key]==slots[1][key];checks+=1
  events=[json.loads(line) for line in z.read('os-key-diagnostic/events.jsonl').decode('utf-8').splitlines()]
  keys=[row for row in events if row['stage']=='input' and row['pressed'] and row['keycode'] in [80,4194305]]
  assert len(keys)==2 and {row['physical_keycode'] for row in keys}=={4194313};checks+=2
  assert next(row for row in keys if row['keycode']==80)['logical_p'] is True and all(not row['physical_p'] for row in keys);checks+=2
 print(json.dumps(dict(checks=checks,failures=0,cumulative_candidates=3,native_menus=3,cold_resume=True,binaries_hashed=a.check_artifacts,formal_release=False,physical_controller=False)))
if __name__=='__main__':main()
