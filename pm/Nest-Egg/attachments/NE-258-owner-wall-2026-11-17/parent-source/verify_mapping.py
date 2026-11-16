"""Verify the parent comment change against the exact archived tested sources."""
from pathlib import Path
import hashlib
import json
import tarfile

ROOT = Path(__file__).resolve().parent
sha = lambda data: hashlib.sha256(data).hexdigest()
code = lambda data: [line for line in data.decode('utf-8-sig').splitlines()
                     if line.strip() and not line.lstrip().startswith('#')]
mapping = json.loads((ROOT / 'comment-mapping.json').read_text(encoding='utf-8'))
old = (ROOT / 'light_kit-tested.gd.txt').read_bytes()
current = (ROOT / 'light_kit-comment.gd.txt').read_bytes()
assert sha(old) == mapping['tested_sha256']
assert sha(current) == mapping['published_comment_sha256']
assert code(old) == code(current)
sources = json.loads((ROOT / 'git-source-mapping.json').read_text(encoding='utf-8'))
assert len(sources) == 13
with tarfile.open(ROOT.parent / 'raw-owner-wall.tar.xz', 'r:xz') as archive:
    for row in sources:
        original = archive.extractfile('source/freeze-wall-v4/' + row['path']).read()
        delivered = current if row['path'] == 'core/light_kit.gd' else original
        if row['path'] == 'core/light_kit.gd':
            assert original == old
        assert sha(delivered) == row['raw_sha256'], row['path']
        assert sha(delivered.replace(b'\r\n', b'\n')) == row['git_lf_sha256'], row['path']
print('13 delivered source mappings verified; only one comment differs from the tested code')
