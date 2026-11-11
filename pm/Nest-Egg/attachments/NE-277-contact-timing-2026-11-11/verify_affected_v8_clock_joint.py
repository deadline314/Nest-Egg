from pathlib import Path
import hashlib,json,re,zipfile
HERE=Path(__file__).resolve().parent

def main():
 index=json.loads((HERE/'affected-v8-clock-joint-index.json').read_bytes());archive=HERE/index['archive']
 assert archive.stat().st_size==index['bytes'] and hashlib.sha256(archive.read_bytes()).hexdigest()==index['sha256']
 with zipfile.ZipFile(archive) as z:
  assert z.testzip() is None and set(z.namelist())==set(index['entries'])
  for n,v in index['entries'].items():
   data=z.read(n);assert len(data)==v['bytes'] and hashlib.sha256(data).hexdigest()==v['sha256'],n
  receipt=json.loads(z.read('official/exit.json'));candidate=json.loads(z.read('official/candidate.json'))
  assert receipt['exit']==0 and receipt['sources_unchanged'] and not receipt['changed_sources']
  assert candidate['base']==index['base'] and len(candidate['source_sha256'])==33
  assert receipt['command']==['C:/Program Files/Git/bin/bash.exe','tools/run_tests_changed.sh',index['base']]
  imported=json.loads(z.read('official/import.json'));assert imported['exit']==0 and imported['error_lines']==[] and imported['sources_unchanged']
  assert hashlib.sha256(z.read('executed-runner.py')).hexdigest()==json.loads(z.read('official/runner-before.json'))['sha256']
  before=json.loads(z.read('official/source-before.json'));assert before==candidate['source_sha256']
  for n,wanted in candidate['source_sha256'].items():
   assert hashlib.sha256(z.read('candidate-source/'+n)).hexdigest()==wanted==receipt['source_after'][n]
  summary=z.read('official/full.log').decode('utf-8');assert 'Running 70 groups in 4 processes' in summary
  assert f"checks: {index['checks']}, new failures: 0, known failures (tests/known_failures.txt): 0" in summary
  checks=0;suites=[];diagnostics=0
  for i in range(4):
   log=z.read(f'official/logs/shard_{i}.log').decode('utf-8');assert not re.search(r'SCRIPT ERROR|^FAIL:',log,re.M)
   counts=re.findall(r'^checks: (\d+), failures: (\d+)',log,re.M);assert len(counts)==1 and int(counts[0][1])==0
   checks+=int(counts[0][0]);suites+=re.findall(r'^SUITE_TIME (\S+) ',log,re.M);diagnostics+=len(re.findall(r'^ERROR:',log,re.M))
  assert checks==index['checks'] and len(suites)==len(set(suites))==70
 print(json.dumps(dict(groups=70,checks=checks,new_failures=0,known_failures=0,exit=0,expected_or_filtered_error_lines=diagnostics,scope=index['scope'])))
if __name__=='__main__':main()
