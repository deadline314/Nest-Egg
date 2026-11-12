from pathlib import Path
import hashlib, json, runpy, zipfile
root=Path(__file__).resolve().parent
manifest=json.loads((root/'original-delivery-manifest.json').read_bytes())
for name,row in manifest['files'].items():
    data=(root/'original'/name).read_bytes()
    assert len(data)==row['bytes'] and hashlib.sha256(data).hexdigest()==row['sha256'],name
adoption=json.loads((root/'source-adoption.json').read_bytes())
for name,wanted in adoption['canonical_after'].items():
    assert hashlib.sha256((root/'original/source'/name).read_bytes()).hexdigest()==wanted
context=json.loads((root/'protected-context-v23.json').read_bytes())
assert context['count']==len(context['files'])==393
with zipfile.ZipFile(root.parent/'ST-9-death-thresholds-2026-11-12/proof-raw.zip') as z:
    previous_bytes=z.read('c-native-context-v22.json')
    assert hashlib.sha256(previous_bytes).hexdigest()==context['metadata_erratum']['previous_sha256']
    previous=json.loads(previous_bytes)
    assert previous['count']==388 and len(previous['files'])==392
    assert set(previous['files'])<=set(context['files'])
    for name,wanted in previous['files'].items():
        if name not in adoption['physical_after']:
            assert context['files'][name]==wanted,name
runpy.run_path(str(root/'original/verify.py'),run_name='__main__')
print('PASS: exact original21-file packet; canonical source3; old v22 metadata preserved and new actual393-file context checked.')
