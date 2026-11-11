from pathlib import Path
import hashlib,json,re,zipfile
HERE=Path(__file__).resolve().parent
def sha(data):return hashlib.sha256(data).hexdigest()
i=json.loads((HERE/'index.json').read_bytes());p=HERE/i['archive']
assert p.stat().st_size==i['bytes'] and sha(p.read_bytes())==i['sha256']
with zipfile.ZipFile(p)as z:
 assert z.testzip()is None and set(z.namelist())==set(i['entries'])
 for n,v in i['entries'].items():
  b=z.read(n);assert len(b)==v['bytes'] and sha(b)==v['sha256']
 c=json.loads(z.read('review.json'));assert c['base']==i['base'] and c['sources']==c['source_after'] and len(c['sources'])==i['sources']==1522
 for n,v in c['sources'].items():assert sha(z.read('source/'+n))==v
 total=0
 for r in c['receipts']:
  assert r['exit']==0 and not r['diagnostics'] and r['sources_unchanged']
  b=z.read(r['mode']+'.log');assert sha(b)==r['log_sha256']
  text=b.decode('utf-8');assert not re.search(r'SCRIPT ERROR|ERROR:|ObjectDB.*leak|RID.*leak|resources still in use',text,re.I)
  matches=re.findall(r'\[RunSaveProbe\] '+r['mode']+r' checks=(\d+) failures=(\d+)',text)
  assert [list(v)for v in matches]==r['summary'] and len(matches)==1 and matches[0][1]=='0';total+=int(matches[0][0])
 assert total==i['checks']==18
count=0
for h in i['historical']:
 folder=HERE.parent/h['folder'];p=folder/h['archive'];m=folder/h['manifest']
 assert p.stat().st_size==h['bytes'] and sha(p.read_bytes())==h['sha256'] and sha(m.read_bytes())==h['manifest_sha256']
 rows=json.loads(m.read_bytes());assert len(rows)==h['members']
 with zipfile.ZipFile(p)as z:
  assert z.testzip()is None and set(z.namelist())=={v['path']for v in rows}
  for v in rows:
   data=z.read(v['path']);assert len(data)==v['bytes'] and sha(data)==v['sha256']
 count+=len(rows)
print('Current published Main: two fresh processes / 18 checks / 0 failures; 1522 exact sources; historical original archive members verified:',count)
