"""Read-only native metric, legacy-control and source-hash recount; no Godot/GPU."""
from pathlib import Path
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = next(parent for parent in HERE.parents if (parent / 'project.godot').is_file())
frames = json.loads((HERE / 'continuous-final/frames.json').read_text(encoding='utf-8'))
metrics = json.loads((HERE / 'verification.json').read_text(encoding='utf-8'))
contacts = [frame for frame in frames if frame['phase'] in ('turn', 'recoil')]
assert len(frames) == metrics['sampled_frames'] == 194
assert len(contacts) == metrics['contact_frames'] == 65
assert max(frame['error'] for frame in contacts) == metrics['worst_contact_error_world_px'] < .25
assert len(list((HERE / 'continuous-final').glob('*.png'))) == metrics['raw_captures'] == 45
native = (HERE / 'ne240-radio-native-continuous-final.log').read_text(encoding='utf-8-sig')
assert native.count('\nPASS ') == 12
assert not any(marker in native for marker in ['SCRIPT ERROR', 'ERROR:', 'leaked'])
unit = (HERE / 'ne240-radio-unit-final3.log').read_text(encoding='utf-8-sig')
assert 'checks: 266, failures: 0' in unit and 'SCRIPT ERROR' not in unit
for prefix in ['RADIO_LEGACY_REFUSED', 'RADIO_LEGACY_SAVED']:
    observed = {}
    for line in unit.splitlines():
        if line.startswith(prefix + ' '):
            _, mode, value = line.split(' ', 2)
            observed[mode] = json.loads(value)
    assert observed['baseline'] == observed['save'], prefix
sources = json.loads((HERE / 'source-hashes.json').read_text(encoding='utf-8'))
git_sources = json.loads((HERE / 'git-source-hashes.json').read_text(encoding='utf-8'))
for name, expected in sources.items():
    raw = (HERE / 'raw-source' / name).read_bytes()
    assert hashlib.sha256(raw).hexdigest() == expected, name
    normalized = hashlib.sha256(raw.replace(b'\r\n', b'\n')).hexdigest()
    assert normalized == git_sources[name], name
    assert hashlib.sha256((ROOT / name).read_bytes().replace(b'\r\n', b'\n')).hexdigest() == normalized, name
sealed = (ROOT / 'data/story_contracts/migration-5a.json').read_bytes()
assert len(sealed) == metrics['sealed_bytes'] == 141463
assert hashlib.sha256(sealed).hexdigest() == metrics['sealed_sha256']
print('NE240 evidence verified: 194 frames, 65 contacts, 45 native PNGs, 12 native PASS, 266 checks, 2 legacy controls, 13 source hashes, sealed unchanged')
