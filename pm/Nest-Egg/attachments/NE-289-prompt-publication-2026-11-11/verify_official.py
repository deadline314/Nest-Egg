"""Verify the original selector run, frozen source, and unmodified raw log."""
from pathlib import Path
import hashlib,json,re,zipfile
HERE=Path(__file__).resolve().parent
def main():
 index=json.loads((HERE/'official-index.json').read_bytes());raw=HERE/index['archive']
 assert hashlib.sha256(raw.read_bytes()).hexdigest()==index['sha256'] and raw.stat().st_size==index['bytes']
 with zipfile.ZipFile(raw) as z:
  assert z.testzip() is None and set(z.namelist())==set(index['entries'])
  for name,item in index['entries'].items():
   data=z.read(name);assert len(data)==item['bytes'] and hashlib.sha256(data).hexdigest()==item['sha256'],name
  receipt=json.loads(z.read('official/exit.json'));candidate=json.loads(z.read('official/candidate.json'))
  assert receipt['exit']==0 and receipt['sources_unchanged'] and not receipt['changed_sources']
  assert candidate['base']==index['base'] and receipt['command']==['C:/Program Files/Git/bin/bash.exe','tools/run_tests_changed.sh',index['base']]
  assert json.loads(z.read('official/import.json'))['error_lines']==[]
  assert hashlib.sha256(z.read('executed-runner.py')).hexdigest()==json.loads(z.read('official/runner-before.json'))['sha256']
  for name,wanted in candidate['source_sha256'].items():
   assert hashlib.sha256(z.read('source/'+name)).hexdigest()==wanted==receipt['source_after'][name]
  summary=z.read('official/full.log').decode('utf-8');log=z.read('official/logs/shard_0.log').decode('utf-8')
  assert 'QuestMapSuite' in summary and 'checks: 397, new failures: 0, known failures (tests/known_failures.txt): 0' in summary
  assert not re.search(r'SCRIPT ERROR|\nERROR:|ObjectDB instances leaked|resources still in use',log)
 print(json.dumps(dict(groups=1,checks=397,new_failures=0,known_failures=0,exit=0,raw_sha256=index['sha256'])))
if __name__=='__main__':main()
