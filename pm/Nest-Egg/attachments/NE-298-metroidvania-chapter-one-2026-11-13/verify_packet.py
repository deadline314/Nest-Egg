"""Read-only adapter around the recorded original NE298 readers; no engine."""
from pathlib import Path
import hashlib, importlib.util, json, sys, zipfile

def sha(p):
    with p.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()

def verify(root):
    root = Path(root)
    for m in json.loads((root / 'artifact-manifest.json').read_bytes())['artifacts']:
        p = root / m['path']
        assert p.stat().st_size == m['bytes'] and sha(p) == m['sha256'], m['path']
        if p.suffix == '.zip':
            with zipfile.ZipFile(p) as z:
                assert z.testzip() is None, m['path']
    source = json.loads((root / 'source-v8/source-manifest.json').read_bytes())
    with zipfile.ZipFile(root / 'source-v8/source.zip') as z:
        assert set(z.namelist()) == set(source['owned'])
        for n, m in source['owned'].items():
            b = z.read(n)
            assert len(b) == m['size'] and hashlib.sha256(b).hexdigest() == m['sha256'], n
    history = json.loads((root / 'history-index.json').read_bytes())
    for m in history['archives']:
        assert sha(root / m['path']) == m['sha256']
    spec = importlib.util.spec_from_file_location('ne298_native_reader', root / 'native-v8-high/verify.py')
    reader = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(reader)
    result = reader.verify(root / 'native-v8-high')
    result['source_scope'] = '92521 + owned21 v8; not integrated74 official'
    return result

if __name__ == '__main__':
    print(json.dumps(verify(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent), indent=2))
