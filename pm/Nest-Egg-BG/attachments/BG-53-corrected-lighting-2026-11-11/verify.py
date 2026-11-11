from pathlib import Path
import json,hashlib,zipfile,sys
base=Path(sys.argv[1])if len(sys.argv)>1 else Path(__file__).resolve().parent
count=0
for record in json.loads((base/'archives.json').read_bytes()):
 path=base/record['zip'];assert hashlib.sha256(path.read_bytes()).hexdigest()==record['sha256'],path
 with zipfile.ZipFile(path)as z:
  m=json.loads(z.read('manifest-raw.json'));assert set(z.namelist())==set(m)|{'manifest-raw.json'}
  for name,item in m.items():
   raw=z.read(name);assert len(raw)==item['bytes']and hashlib.sha256(raw).hexdigest()==item['sha256'],(path,name);count+=1
  b=json.loads(z.read('source-before.json'));e=json.loads(z.read('exit.json'));assert b==e['source_after'],path
  for name,sha in b.items():assert hashlib.sha256(z.read('source/'+name)).hexdigest()==sha,(path,name)
print(f'PASS: {count} original files, archive SHA, exact source bytes and stable per-run source hashes')
