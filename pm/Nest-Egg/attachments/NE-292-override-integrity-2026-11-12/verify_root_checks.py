from pathlib import Path
import hashlib,json,re,zipfile
HERE=Path(__file__).resolve().parent
i=json.loads((HERE/'root-checks-index.json').read_bytes());p=HERE/i['archive']
assert p.stat().st_size==i['bytes']and hashlib.sha256(p.read_bytes()).hexdigest()==i['sha256']
with zipfile.ZipFile(p)as z:
 assert z.testzip()is None and set(z.namelist())==set(i['entries'])
 for n,v in i['entries'].items():
  b=z.read(n);assert len(b)==v['bytes']and hashlib.sha256(b).hexdigest()==v['sha256']
 c=json.loads(z.read('root-checks.json'));r=json.loads(z.read('c-union-permanent.json'));s=json.loads(z.read('original-affected.json'))
 assert r['exit']==s['exit']==0 and len(c['c_guard_after'])==355
 assert hashlib.sha256(z.read(r['log'])).hexdigest()==r['sha256']and hashlib.sha256(z.read(s['log'])).hexdigest()==s['sha256']
 assert b'Ran 8 tests'in z.read(r['log'])and re.search(rb'^OK\r?$',z.read(r['log']),re.M)
 assert s['command']==['C:/Program Files/Git/bin/bash.exe','tools/run_tests_changed.sh',c['base']]
 assert '沒有受影響的測試要跑'in z.read(s['log']).decode()
 print('Root C union8/0; original affected entry selects zero Godot groups for four Python/CPU-CI changes; 355 source guard retained')
