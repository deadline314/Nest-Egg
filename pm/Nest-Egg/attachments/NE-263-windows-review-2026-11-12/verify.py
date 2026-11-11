from pathlib import Path
import hashlib,json,re,zipfile
HERE=Path(__file__).resolve().parent
i=json.loads((HERE/'index.json').read_bytes());p=HERE/i['archive']
assert p.stat().st_size==i['bytes'] and hashlib.sha256(p.read_bytes()).hexdigest()==i['sha256']
with zipfile.ZipFile(p) as z:
 assert z.testzip() is None and set(z.namelist())==set(i['entries'])
 for n,v in i['entries'].items():
  b=z.read(n);assert len(b)==v['bytes'] and hashlib.sha256(b).hexdigest()==v['sha256']
 c=json.loads(z.read('context.json'));r=json.loads(z.read('exit.json'));s=z.read('unit.log')
 assert c['platform']=='win32' and c['locale']=='cp950' and c['stdout_encoding']=='cp950' and c['utf8_mode']==0
 assert c['PYTHONUTF8'] is None and c['PYTHONIOENCODING'] is None
 assert r['exit']==0 and r['sources_unchanged'] and b'Ran 19 tests' in s and b'\nOK' in s and b'skipped=' not in s
 for n,v in c['sources'].items():assert hashlib.sha256(z.read('source/'+n)).hexdigest()==v==r['source_after'][n]
print('Actual Windows cp950: 19 tests / 0 failures / 0 skips; original bytes and source hashes verified')
