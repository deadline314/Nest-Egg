"""Verify the frozen ST2 packets and the exact published candidate, without Godot."""
from pathlib import Path
import argparse, hashlib, json, zipfile

here = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--root', type=Path, default=here.parents[3])
args = parser.parse_args()
index = json.loads((here / 'index.json').read_bytes())
for name, record in index['archives'].items():
    data = (here / name).read_bytes()
    assert len(data) == record['bytes'] and hashlib.sha256(data).hexdigest() == record['sha256'], name
for name, wanted in index['candidate'].items():
    assert hashlib.sha256((args.root / name).read_bytes()).hexdigest() == wanted, name
with zipfile.ZipFile(here / 'original-proof.zip') as z:
    members = json.loads(z.read('portable-files-sha256.json'))
    assert len(members) == 97 and len(z.namelist()) == 98
    assert set(z.namelist()) == {r['path'] for r in members} | {'portable-files-sha256.json'}
    for row in members:
        data = z.read(row['path'])
        assert len(data) == row['bytes'] and hashlib.sha256(data).hexdigest() == row['sha256'], row['path']
    for name, wanted in index['candidate'].items():
        assert hashlib.sha256(z.read('candidate-files/' + name)).hexdigest() == wanted
with zipfile.ZipFile(here / 'latest-main-integration.zip') as z:
    assert z.testzip() is None
    receipt = json.loads(z.read('exit.json'))
    assert receipt['exit_code'] == 0 and receipt['checks'] == 2732 and receipt['failures'] == 0 and not receipt['diagnostics']
    assert json.loads(z.read('source-before.json')) == json.loads(z.read('source-after.json'))
print(json.dumps(dict(accepted=True, candidate_files=7, original_members=97, integration_checks=2732, scope='Frozen source/raw verification only; no new engine/GPU/native-language/full-chapter claim.'), indent=2))
