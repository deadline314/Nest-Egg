from pathlib import Path
import hashlib,json,re,zipfile
HERE=Path(__file__).resolve().parent
def main():
 index=json.loads((HERE/'raw-index.json').read_bytes());archive=HERE/index['archive']
 assert archive.stat().st_size==index['bytes'] and hashlib.sha256(archive.read_bytes()).hexdigest()==index['sha256']
 with zipfile.ZipFile(archive) as z:
  assert z.testzip() is None and set(z.namelist())==set(index['entries'])
  for name,item in index['entries'].items():
   data=z.read(name);assert len(data)==item['bytes'] and hashlib.sha256(data).hexdigest()==item['sha256'],name
  receipt=json.loads(z.read('official/exit.json'));candidate=json.loads(z.read('official/candidate.json'));assert receipt['exit']==0 and receipt['sources_unchanged'] and len(candidate['source_sha256'])==1
  assert receipt['command']==['C:/Program Files/Git/bin/bash.exe','tools/run_tests_changed.sh',index['base']]
  assert hashlib.sha256(z.read('official-executed-runner.py')).hexdigest()==json.loads(z.read('official/runner-before.json'))['sha256']
  summary=z.read('official/full.log').decode('utf-8');assert 'Running 16 groups in 4 processes' in summary and 'checks: 6298, new failures: 0, known failures (tests/known_failures.txt): 0' in summary
  checked=0;suites=[]
  for i in range(4):
   log=z.read(f'official/logs/shard_{i}.log').decode('utf-8');assert not re.search(r'SCRIPT ERROR|^FAIL:',log,re.M)
   count=re.findall(r'^checks: (\d+), failures: (\d+)',log,re.M);assert len(count)==1 and int(count[0][1])==0;checked+=int(count[0][0]);suites+=re.findall(r'^SUITE_TIME (\S+) ',log,re.M)
  assert checked==6298 and len(set(suites))==len(suites)==16
  before=z.read('native/before/executed-main_menu.gd');after=z.read('native/after/executed-main_menu.gd')
  assert before.replace('選擇難度，從第一章開始'.encode(),'選擇難度，從序章開始'.encode())==after
  assert hashlib.sha256(after).hexdigest()==candidate['source_sha256']['ui/main_menu.gd']
  for label,hint in [('before','選擇難度，從第一章開始'),('after','選擇難度，從序章開始')]:
   result=json.loads(z.read('native/'+label+'/receipt.json'));view=json.loads(z.read('native/'+label+'/menu.json'));log=z.read('native/'+label+'/process.log').decode('utf-8')
   assert result['exit']==0 and not result['error_lines'] and result['sources_unchanged'] and result['renderer_forward_plus'] and result['gpu_rx9070xt']
   assert view['tooltip']==view['focus_hint']==hint and view['button_focused'] and view['quit_via_actual_menu_signal'] and view['hdr_2d'] and view['size']==[1280,720]
   assert not re.search(r'SCRIPT ERROR|ERROR:|ObjectDB.*leak|resources still in use',log)
  bad=z.read('rejected-forced-quit/before/process.log').decode('utf-8');assert '4 ObjectDB' in bad and '1 resources still in use' in bad
 print(json.dumps(dict(groups=16,checks=6298,new_failures=0,known_failures=0,exit=0,native_pair_clean=True,rejected_forced_quit_preserved=True)))
if __name__=='__main__':main()
