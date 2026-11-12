from pathlib import Path
import hashlib,json,zipfile,io
root=Path(__file__).resolve().parent
index=json.loads((root/'index.json').read_text(encoding='utf8'))
for name,row in index['files'].items():
 data=(root/name).read_bytes();assert len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256'],name
manifest=json.loads((root/'candidate-manifest.json').read_text(encoding='utf8'))
with zipfile.ZipFile(root/'candidate-source.zip') as z:
 assert z.testzip() is None
 assert set(z.namelist())==set(manifest['files'])
 for name,row in manifest['files'].items():
  data=z.read(name);assert b'\r' not in data and len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256'],name
with zipfile.ZipFile(root/'raw.zip') as z:
 assert z.testzip() is None
 baseline=json.loads(z.read('baseline-generation.json'));green=json.loads(z.read('generation-green.json'))
 assert len(baseline['generated'])==216 and baseline['generated']==green['generated'] and green['different']==[]
 assert all(r['exit']==0 for r in baseline['runs']+green['runs'])
 with zipfile.ZipFile(io.BytesIO(z.read('baseline-generated.zip'))) as original:
  assert original.testzip() is None
  for name,row in baseline['generated'].items():
   data=original.read(name);assert len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256'],name
 red=json.loads(z.read('old-red.stdout'));assert red['failures']==3 and all(not r['passed'] for r in red['cases'])
 unit=z.read('unit.stderr').decode('utf8');assert 'Ran 10 tests' in unit and 'OK' in unit
 rows=[json.loads(line) for line in z.read('original-channel.stdout').decode('utf8').splitlines() if line.startswith('{')]
 assert sum(r['checks'] for r in rows)==29 and all(r['failures']==[] for r in rows)
 for name in ('select-base.stdout','select-final-base.stdout'):assert not z.read(name).strip()
 for name in ('cpu-validation.json','final-validation.json'):
  r=json.loads(z.read(name));assert r['source_before']==r['source_after']
  assert all(c['exit']==c.get('expected_exit',0) for c in r.get('commands',r.get('results',[])))
 final=json.loads(z.read('final-validation.json'));assert final['source_after']==manifest['files']
print('PASS: source6, original3 reds, unit10, channel29, generated216 exact, both changed0; no Godot/CI gameplay claim')
