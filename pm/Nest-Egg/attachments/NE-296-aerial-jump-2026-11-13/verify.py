from pathlib import Path
import hashlib,json,zipfile,io,re
r=Path(__file__).resolve().parent
index=json.loads((r/'index.json').read_bytes())
for name,row in index['files'].items():
 raw=(r/name).read_bytes();assert len(raw)==row['bytes'] and hashlib.sha256(raw).hexdigest()==row['sha256'],name
source=json.loads((r/'source-manifest.json').read_bytes())
with zipfile.ZipFile(r/'source.zip') as z:
 assert z.testzip() is None
 for name,wanted in source['files'].items():assert hashlib.sha256(z.read('final/'+name)).hexdigest()==wanted,name
with zipfile.ZipFile(r/'raw.zip') as z:
 assert z.testzip() is None
 def read(name):return json.loads(z.read(name))
 final=read('changed-final-v2/receipt.json')
 assert final['accepted'] and final['exit_code']==0 and final['source_exact'] and final['c_unchanged'] and final['all_four_queue_gates']
 assert b'checks: 92936, new failures: 0, known failures (tests/known_failures.txt): 0' in z.read('changed-final-v2/engine.log')
 tested=read('changed-final-v2/source-after.json')
 assert all(tested[n]==sha for n,sha in source['files'].items())
 shards=[n for n in z.namelist() if re.fullmatch(r'changed-final-v2/test-logs/shard_\d+\.log',n)]
 assert len(shards)==6
 for name in shards:
  lines=z.read(name).decode('utf-8',errors='replace').splitlines()
  assert not any('SCRIPT ERROR' in line for line in lines),name
  assert not any('DummyTexture' in line and 'leaked at exit' in line for line in lines),name
 assert read('changed-v1/receipt.json')['exit_code']==1
 assert b'checks: 92935, new failures: 2' in z.read('changed-v1/engine.log')
 assert b'checks: 28, failures: 2' in z.read('hud-original-red-v1/engine.log')
 assert b'checks: 28, failures: 0' in z.read('hud-original-fixed-v1/engine.log')
 assert read('hud-original-fixed-v1/receipt.json')['accepted']
 native=read('capture-final-v1/captures/result.json')
 assert native['checks']==11 and native['failures']==0 and native['hdr_2d'] and native['renderer']=='forward_plus'
 for row in native['frames']:
  assert row['format']==14 and row['size']==[1280,720]
  for suffix,field in [('.raw','raw_sha256'),('.png','png_sha256')]:
   raw=z.read('capture-final-v1/captures/'+row['tag']+suffix)
   assert hashlib.sha256(raw).hexdigest()==row[field]
   if suffix=='.raw':assert len(raw)==1280*720*3*2
 assert read('capture-final-v1/receipt.json')['accepted']
print('PASS: exact final four sources; original 65/92936 green, two original HUD reds retained then 28/0, native 11/0, six logs no SCRIPT/DummyTexture diagnostics. Stock resource messages retained.')
