from pathlib import Path
import hashlib,json,re,zipfile
h=Path(__file__).resolve().parent;i=json.loads((h/'original-selector-index.json').read_bytes());p=h/i['archive']
assert p.stat().st_size==i['bytes'] and hashlib.sha256(p.read_bytes()).hexdigest()==i['sha256']
with zipfile.ZipFile(p) as z:
 assert z.testzip() is None and set(z.namelist())==set(i['entries'])
 for n,v in i['entries'].items():
  b=z.read(n);assert len(b)==v['bytes'] and hashlib.sha256(b).hexdigest()==v['sha256']
 c=json.loads(z.read('official/candidate.json'));r=json.loads(z.read('official/exit.json'))
 assert c['base']==i['base'] and c['source_sha256']==i['source_sha256'] and len(c['source_sha256'])==1
 assert r['exit']==0 and r['sources_unchanged'] and not r['changed_sources']
 assert r['command']==['C:/Program Files/Git/bin/bash.exe','tools/run_tests_changed.sh',i['base']]
 imported=json.loads(z.read('official/import.json'));assert imported['exit']==0 and imported['error_lines']==[] and imported['sources_unchanged']
 assert hashlib.sha256(z.read('executed-runner.py')).hexdigest()==json.loads(z.read('official/runner-before.json'))['sha256']
 for n,v in c['source_sha256'].items():assert hashlib.sha256(z.read('candidate-source/'+n)).hexdigest()==v==r['source_after'][n]
 log=z.read('official/logs/shard_0.log').decode('utf-8');assert 'SCRIPT ERROR' not in log and not re.search(r'^FAIL:',log,re.M)
 assert re.findall(r'^checks: (\d+), failures: (\d+)',log,re.M)==[('94','0')]
 assert re.findall(r'^SUITE_TIME (\S+) ',log,re.M)==['CombatHudSuite']
 assert 'Running 1 groups in 1 processes' in z.read('official/full.log').decode('utf-8')
print('Original affected selector: CombatHudSuite 94 / 0 new / 0 known; source unchanged; no unmerged UI product')
